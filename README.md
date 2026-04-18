# Functional Verification of DDR5 Controller
### UVM · SystemVerilog · EDA Playground · Aldec Riviera-PRO

## Overview

This project builds a complete **UVM-based functional verification environment** for a custom DDR5 memory controller written in SystemVerilog. The DUT models realistic DDR5 DRAM protocol behavior — from per-bank state machines and address mapping all the way through refresh sequencing and timing enforcement — and the testbench is designed to prove correctness under the full range of protocol scenarios a production controller would face.

The project covers every major layer of the JEDEC DDR5 specification that applies to a behavioral controller model: timing parameter enforcement across 10 constraints, 4 bank groups × 4 banks × 2 ranks (16 banks total), BL16 burst data paths, write-to-read and read-to-write turnaround, CCD spacing within and across bank groups, and periodic refresh with bank draining.

The verification goal was to prove three things:

- **Safety** — no timing constraint is ever violated
- **Correctness** — every read returns the data from the most recent write to that address
- **Completeness** — the controller reaches every meaningful protocol state that JEDEC defines

---

## Repository Structure

.
├── ddr5_controller_DUT.sv    # DUT: cycle-accurate DDR5 controller model
├── ddr5_dut_if.sv            # Interface with driver and monitor clocking blocks
├── ddr5_tb_params_pkg.sv     # Global timing parameters and address-field widths
├── ddr5_tb_utils_pkg.sv      # Helper functions: address packing, burst data generation
├── ddr5_tb_pkg.sv            # Top-level TB package (imports all components)
├── transactions.sv           # UVM sequence item: ddr5_req_txn, ddr5_cmd_txn
├── sequences.sv              # All directed + stress sequences
├── driver.sv                 # UVM driver: request → DUT pin stimulus
├── monitor.sv                # UVM monitor: 3 parallel threads (req / rsp / cmd)
├── scoreboard.sv             # Data integrity + timing constraint checker
├── coverage.sv               # 12 functional covergroups
├── agent.sv                  # UVM agent
├── env.sv                    # UVM environment
├── tests.sv                  # All test classes + regression test
├── tb_top.sv                 # Testbench top: DUT + interface + UVM kickoff
└── waveform_DDR5.png         # Captured waveform screenshot

---

## DUT Description

**File:** `ddr5_controller_DUT.sv`

The DUT is a behavioral RTL model of a DDR5 memory controller scheduler and timing engine. It accepts a simple request interface (`req_valid`, `req_write`, `req_addr`, `req_wdata`) and drives a DRAM command bus (`cmd_code`, `cmd_bg`, `cmd_bank`, `cmd_row`, `cmd_col`) along with a response path (`rsp_valid`, `rsp_rdata`).

### Architecture

```
CPU Request Interface
        │
        ▼
  ┌─────────────┐
  │   ST_IDLE   │◄──────────────────────────────┐
  └──────┬──────┘                               │
         │ row hit / miss / empty bank          │
         ▼                                      │
  ┌─────────────┐    ┌─────────────┐            │
  │ ST_PRE_WAIT │───►│ST_ACT_ISSUE │            │
  └─────────────┘    └──────┬──────┘            │
                            │                   │
                     ┌──────▼──────┐            │
                     │ST_RCD_WAIT  │            │
                     └──────┬──────┘            │
                            │                   │
                     ┌──────▼──────┐            │
                     │ST_COL_ISSUE │            │
                     └──────┬──────┘            │
               ┌────────────┴────────────┐      │
               ▼                         ▼      │
       ┌──────────────┐        ┌───────────────┐│
       │ST_READ_WAIT  │        │ST_WRITE_WAIT  ││
       │  (CL cycles) │        │ (tCWL cycles) ││
       └──────┬───────┘        └───────┬───────┘│
              │                        │        │
              └───────────┬────────────┘        │
                          │                     │
                   ┌──────▼──────┐              │
                   │   ST_IDLE   │──────────────┘
                   └─────────────┘
                          │ (refresh_pending)
                   ┌──────▼──────┐    ┌─────────────┐
                   │ST_REF_ISSUE │───►│ ST_REF_WAIT │
                   └─────────────┘    └─────────────┘
```

### Timing Parameters

| Parameter | Value | What it enforces |
|-----------|-------|-----------------|
| `tRCD`    | 4     | ACT → first READ/WRITE |
| `tRAS`    | 8     | Minimum row active time before PRE |
| `tRP`     | 4     | PRE → next ACT on same bank |
| `tRC`     | 12    | ACT → ACT on same bank (= tRAS + tRP) |
| `CL`      | 4     | READ command → first data on bus |
| `tCWL`    | 4     | WRITE command → DRAM accepts data |
| `tWTR`    | 4     | Last WRITE → next READ (bus turnaround) |
| `tRTW`    | 6     | Last READ → next WRITE (bus direction flip) |
| `tCCD_L`  | 8     | Column command spacing within same bank group |
| `tCCD_S`  | 4     | Column command spacing across different bank groups |
| `tRFC`    | 16    | Refresh cycle time |
| `tRAS_MAX`| 64    | Maximum row open time (watchdog forced-PRE) |

### Address Mapping

```
addr[31:28]  = row   (ROW_W = 4)
addr[12]     = rank  (RANK_W = 1, 2 ranks)
addr[11:10]  = bg    (BG_W = 2, 4 bank groups)
addr[9:8]    = bank  (BANK_W = 2, 4 banks/group)
addr[7:4]    = col   (COL_W = 4)
addr[3:0]    = unused / zero
```

Total: 16 banks (2 ranks × 4 BGs × 4 banks per BG)

### Key Design Features

- **Per-bank countdown timers** — each of the 16 banks maintains its own `trcd_ctr`, `tras_ctr`, `trp_ctr`, `trc_ctr`, `twtr_ctr`, and `tras_max_ctr`
- **Row-buffer model** — writes land in a row buffer first; PRE or refresh flushes them to backing memory; reads check the row buffer before hitting the array
- **Write-through backing store** — writes commit immediately to `mem_array` in addition to the row buffer, ensuring data is never lost across refresh
- **Bank-group CCD enforcement** — `bg_ccd_ctr[]` per bank group, armed with `tCCD_L` on the issuing BG and `tCCD_S` on all others
- **tRAS_MAX watchdog** — any bank open longer than `tRAS_MAX` cycles is force-precharged before new requests are accepted
- **Refresh drain** — when `refresh_pending` asserts, the FSM drains all open banks (one PRE per cycle) before issuing CMD_REF

---

## UVM Testbench Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        TEST                             │
│  ┌───────────────────────────────────────────────────┐  │
│  │                      ENV                          │  │
│  │  ┌─────────────────────────┐  ┌────────────────┐  │  │
│  │  │         AGENT           │  │  SCOREBOARD    │  │  │
│  │  │  ┌──────────────────┐   │  │  ┌──────────┐  │  │  │
│  │  │  │    SEQUENCER     │   │  │  │ Data     │  │  │  │
│  │  │  └────────┬─────────┘   │  │  │ Integrity│  │  │  │
│  │  │  ┌────────▼─────────┐   │  │  │ Checker  │  │  │  │
│  │  │  │     DRIVER       │   │  │  └──────────┘  │  │  │
│  │  │  └──────────────────┘   │  │  ┌──────────┐  │  │  │
│  │  │  ┌──────────────────┐   │  │  │ Timing   │  │  │  │
│  │  │  │    MONITOR       │   │  │  │ Checker  │  │  │  │
│  │  │  │ (3 parallel      │   │  │  └──────────┘  │  │  │
│  │  │  │  threads)        │   │  └────────────────┘  │  │
│  │  │  └──────────────────┘   │  ┌────────────────┐  │  │
│  │  └─────────────────────────┘  │   COVERAGE     │  │  │
│  │                               │  (13 groups)   │  │  │
│  │                               └────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                   ┌───────▼────────┐
                   │   ddr5_dut_if  │
                   └───────┬────────┘
                           │
                   ┌───────▼────────┐
                   │ ddr5_controller│
                   │    _DUT.sv     │
                   └────────────────┘
```

### Component Details

#### Interface — `ddr5_dut_if.sv`
Two clocking blocks with `#1step` skew to prevent driver/DUT race conditions:
- `drv_cb` — output skew ensures signals are stable before the DUT's sampling edge
- `mon_cb` — read-only; samples all request, response, and command bus signals

#### Transaction — `transactions.sv`
Two transaction types:
- `ddr5_req_txn` — randomized request with `is_write`, `addr`, `wdata`, decoded sub-fields, and constraints that keep the address packing consistent with the DUT's field layout
- `ddr5_cmd_txn` — observed command from the DUT's observability bus (`cmd_code`, `cmd_bg`, `cmd_bank`, `cmd_row`, `cmd_col`, `cycle_num`)

#### Sequences — `sequences.sv`

| Sequence | What it targets |
|----------|----------------|
| `ddr5_row_hit_seq`    | Write then two back-to-back reads to the same address — row stays open |
| `ddr5_row_miss_seq`   | Two requests to the same bank but different rows — forces PRE + ACT |
| `ddr5_multi_bank_seq` | Writes to all 16 banks, then reads back — exercises full bank/BG matrix |
| `ddr5_multi_rank_seq` | Requests across both ranks — rank switching and address decode |
| `ddr5_wtr_seq`        | Write immediately followed by read — stresses tWTR turnaround |
| `ddr5_rtw_seq`        | Read immediately followed by write — stresses tRTW turnaround |
| `ddr5_ccd_seq`        | Back-to-back column commands across BGs — stresses tCCD_S |
| `ddr5_refresh_seq`    | Enough operations to span a refresh boundary — validates bank drain + resume |
| `ddr5_stress_seq`     | 200 fully-random transactions — constrained-random coverage closure |

#### Driver — `driver.sv`
Waits for `req_ready` then presents the request for exactly one cycle. Deasserts all signals cleanly afterwards. The wait-then-drive pattern ensures the DUT sees a stable request on the same cycle it is accepted, avoiding off-by-one timing errors in timing-parameter countdowns.

#### Monitor — `monitor.sv`
Three parallel threads running under `fork...join`:
1. **Request thread** — fires when `req_valid && req_ready`; publishes to `req_ap`
2. **Response thread** — fires when `rsp_valid`; publishes to `rsp_ap`
3. **Command thread** — fires when `cmd_valid`; captures full command bus + cycle count; publishes to `cmd_ap`

#### Scoreboard — `scoreboard.sv`
Two independent checking functions:

**Data integrity check:**
- All accepted WRITEs are stored in a `exp_by_addr[]` associative array keyed by full canonical address
- Accepted READs push their address onto `pending_reads[$]`
- Each `rsp_valid` pops from `pending_reads` and compares `rsp_rdata` against the stored expected value
- Reads of unwritten addresses expect zero

**Timing constraint check (on command stream):**
- `tCCD_L/S` — tracks per-BG last column command cycle; flags violations
- `tWTR` — tracks last WRITE cycle; flags READ arriving too soon
- `tRTW` — tracks last READ cycle; flags WRITE arriving too soon

#### Coverage — `coverage.sv`

12 functional covergroups tracking both the request side and the DUT command stream:

| Covergroup | What it measures |
|------------|-----------------|
| `cg_req_type`      | READ and WRITE both exercised |
| `cg_bank_access`   | All 16 BG × Bank combinations accessed |
| `cg_row_access`    | Row hit / row miss / empty bank per BG |
| `cg_timing_err`    | Both legal timing and at-boundary scenarios seen |
| `cg_cmd_sequence`  | Key command transitions: ACT→READ, WRITE→PRE, PRE→ACT, WRITE→READ, READ→WRITE |
| `cg_refresh`       | Refresh commands observed |
| `cg_col_range`     | Low / mid / high column addresses accessed |
| `cg_bank_conflict` | Back-to-back same-bank different-row scenarios |
| `cg_cmd_bg_cross`  | Every command type seen on every bank group |
| `cg_tccd`          | tCCD_L boundary buckets: same-cycle, too-early, exact, later |
| `cg_twtr`          | tWTR boundary buckets |
| `cg_trtw`          | tRTW boundary buckets |

---

## Simulation Results

### Functional Correctness

| Metric | Result |
|--------|--------|
| Writes accepted | 145 |
| Reads accepted  | 147 |
| Read PASS       | **147** |
| Read FAIL       | **0** |
| Data mismatches | **0** |

### Functional Coverage

| Covergroup | Coverage |
|------------|----------|
| Command types      | 100% |
| Bank access        | 100% |
| Row access         | 100% |
| Timing errors      | 100% |
| Refresh            | 100% |
| Column range       | 100% |
| Bank conflict      | 100% |
| BG cross           | 100% |
| tCCD               | 100% |
| tRTW               | 100% |
| Command sequence   | 85.3% |
| tWTR               | 50% |
| **Total**          | **91.2%** |

### Known Coverage Gaps and Why

| Gap | Root cause | Path to closure |
|-----|-----------|-----------------|
| `tWTR` at 50% | The stress sequence does not consistently generate back-to-back WRITE→READ pairs to the same bank because requests target random banks | Add a directed `tWTR_boundary_seq` that issues WRITE and READ to the same bank with zero NOP gap |
| Command sequence at 85.3% | Some rare transitions (e.g. REFRESH→WRITE) require refresh to fire at a very specific point in a sequence | Add a directed test that pre-loads banks, waits for refresh, then immediately issues a WRITE after the refresh window |

### Waveform

![DDR5 Controller Waveform](waveform_DDR5.png)

---

## How to Run

### EDA Playground (Aldec Riviera-PRO)

1. Go to [edaplayground.com](https://www.edaplayground.com) and log in
2. Select **Aldec Riviera-PRO 2025.04** as the simulator
3. Tick **UVM 1.2** in the libraries panel
4. Paste `ddr5_controller_DUT.sv` into the **Design** box
5. Paste all remaining `.sv` files into the **Testbench** box (compilation order matters — paste in this order):
   - `ddr5_tb_params_pkg.sv`
   - `ddr5_tb_utils_pkg.sv`
   - `ddr5_dut_if.sv`
   - `transactions.sv`
   - `sequences.sv`
   - `driver.sv`
   - `monitor.sv`
   - `scoreboard.sv`
   - `coverage.sv`
   - `agent.sv`
   - `env.sv`
   - `tests.sv`
   - `tb_top.sv`
6. Set **Top module** to `tb_top`
7. In **Run options**, add: `+UVM_TESTNAME=ddr5_regression_test +UVM_VERBOSITY=UVM_MEDIUM`
8. Tick **Open EPWave after run**
9. Click **Run**

### What to look for in the output

- `SCOREBOARD FINAL REPORT` — confirms `Read PASS` count and zero failures
- `FUNCTIONAL COVERAGE REPORT` — shows per-covergroup percentages
- `[CHK tRCD]`, `[CHK tRAS]` etc. — any of these firing means a timing violation was detected
- `*** TEST PASSED ***` at the end of the UVM report summary

---

## Verification Plan Summary

### What Was Verified

- All 10 timing constraints enforced and never violated by the DUT
- All 16 banks (2 ranks × 4 BGs × 4 banks) accessed and verified
- Row hit / row miss / empty bank paths all exercised
- BL16 burst data written and read back correctly across 147 read operations
- Refresh correctly drains open banks, waits tRFC, and resumes normal traffic
- tRAS_MAX watchdog forces PRE when a row is held open too long
- Write-to-read and read-to-write turnarounds respected
- tCCD_L and tCCD_S enforced across same-BG and cross-BG column commands

### What Is Not Covered (Known Limitations)

- **Per-bank refresh (REFPB)** — the DUT implements all-bank refresh only; REFPB requires a separate address scheduler and is out of scope
- **Rank-to-rank switching latency (tCMD_RATE)** — the FSM handles one rank at a time sequentially; rank interleaving is not modeled
- **Command bus timing (tCMD)** — the DUT does not model the physical CA bus; timing is at command-level only
- **Power-down modes** — CKE-based power-down and exit timing (tXP) are not implemented

---



