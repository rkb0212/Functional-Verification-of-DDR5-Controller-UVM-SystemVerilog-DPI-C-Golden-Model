DDR5 Controller Verification using UVM
Overview

This project implements a UVM-based verification environment for a custom DDR5 Controller DUT written in SystemVerilog.

The controller models realistic DDR5 behavior, including:

Multi-rank, multi-bank architecture
Command scheduling (ACT, READ, WRITE, PRE, REFRESH)
Strict timing enforcement across multiple constraints

The verification environment ensures:

Protocol correctness
Timing constraint validation
Data integrity across memory operations
DUT Description

File: design.sv

The DUT is a cycle-accurate DDR5 controller model with:

Key Features
Per-bank state machines
Row-buffer based memory access
Full address mapping (Rank → Bank Group → Bank → Row → Column)
Refresh handling with bank draining
Forced precharge using tRAS_MAX watchdog
Timing Constraints Implemented
tRCD — ACT to READ/WRITE delay
tRAS — Minimum row active time
tRP — Precharge time
tRC — Row cycle time
CL — Read latency
tCWL — Write latency
tWTR — Write to Read turnaround
tRTW — Read to Write turnaround
tCCD_L / tCCD_S — Column command spacing
tRFC — Refresh cycle time
Design Highlights
Timing counters use countdown logic (command allowed at 0)
Bank-group aware scheduling (tCCD handling)
Separate pipelines for READ and WRITE
Row-buffer + backing memory model
Correct refresh sequencing and observability
UVM Testbench Architecture

The verification environment follows standard UVM layering:

Test
 └── Env
      ├── Agent
      │    ├── Driver
      │    ├── Monitor
      │    └── Sequencer
      ├── Scoreboard
      └── Coverage
UVM Components
Interface
ddr5_dut_if.sv
Defines DUT signals and clocking blocks for synchronized driving and sampling.
Transaction
transactions.sv
Defines randomized DDR5 transactions:
Command type (ACT, READ, WRITE, PRE, REFRESH)
Address fields (BG, Bank, Row, Column)
Write data
Sequences
sequences.sv

Implements:

Row hit / Row miss
Bank conflict
Write → Read (tWTR)
Read → Write (tRTW)
Refresh scenario
Timing violation (negative testing)
Random stress
Driver
driver.sv
Drives DUT signals based on sequence transactions.
Monitor
monitor.sv
Observes DUT activity and reconstructs transactions.
Scoreboard
scoreboard.sv

Validates:

Correct write operations
Correct read responses
Unwritten memory returns zero
No data corruption
Coverage
coverage.sv

Tracks:

Command types
Bank access (all BG × Bank combinations)
Row hit / miss / empty
Timing violations
Command transitions
Refresh activity
Column range distribution
Bank conflicts
tCCD, tWTR, tRTW coverage
Agent
agent.sv
Encapsulates driver, monitor, and sequencer.
Environment
env.sv
Connects agent, scoreboard, and coverage.
Tests
tests.sv

Includes:

Directed tests for each scenario
Full regression test
Top Module
tb_top.sv

Instantiates:

DUT
Interface
UVM environment

Starts simulation using run_test().

Simulation Results
Functional Results
Writes executed: 145
Reads executed: 147
Read PASS: 147
Read FAIL: 0

Example logs:

WRITE accepted addr=0x10000024 wdata=0xa5a50001
READ of unwritten addr=0x40000036 got zero as expected
Coverage Results
Covergroup	Coverage
Command types	100%
Bank access	100%
Row access	100%
Timing errors	100%
Refresh	100%
Column range	100%
Bank conflict	100%
BG cross	100%
tCCD	100%
tRTW	100%
Command sequence	85.3%
tWTR	50%
tCCD_S	50%
Total Functional Coverage

➡️ 91.2%

Verification Summary
Achieved
Full functional correctness
No data mismatches
All major DDR5 timing constraints validated
Strong coverage across banks, rows, and commands
Remaining Gaps
tWTR coverage not fully stressed
tCCD_S scenarios need more cross-bank traffic
Command sequence combinations can be expanded
How to Run (EDA Playground)
Add all files:
design.sv
All UVM files
Settings:
Top module: tb_top
Enable UVM 1.2
Run simulation
View:
Console logs
Waveforms (.vcd)