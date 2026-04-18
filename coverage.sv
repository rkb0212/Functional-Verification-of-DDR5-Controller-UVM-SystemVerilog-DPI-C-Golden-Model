// =============================================================================
// FUNCTIONAL COVERAGE
// Adapted for current TB:
//   - uses ddr5_req_txn for accepted requests
//   - uses ddr5_cmd_txn for DUT command stream
//   - tracks row hit / miss / empty bank
//   - tracks bank conflicts
//   - tracks READ/WRITE across all BG/banks
//   - tracks refresh
//   - tracks command transitions
//   - tracks timing boundary buckets from observed command spacing
// =============================================================================

`uvm_analysis_imp_decl(_cov_req)
`uvm_analysis_imp_decl(_cov_cmd)

class ddr5_coverage extends uvm_component;
  `uvm_component_utils(ddr5_coverage)

  // Analysis imports
  uvm_analysis_imp_cov_req #(ddr5_req_txn, ddr5_coverage) req_imp;
  uvm_analysis_imp_cov_cmd #(ddr5_cmd_txn, ddr5_coverage) cmd_imp;

  // --------------------------------------------------------------------------
  // Types
  // --------------------------------------------------------------------------
  typedef enum int {
    ROW_HIT   = 0,
    ROW_MISS  = 1,
    EMPTY_BANK= 2
  } row_access_e;

  typedef enum int {
    CMD_NOP_E   = 0,
    CMD_ACT_E   = 1,
    CMD_READ_E  = 2,
    CMD_WRITE_E = 3,
    CMD_PRE_E   = 4,
    CMD_REF_E   = 5
  } cmd_kind_e;

  // --------------------------------------------------------------------------
  // State used for classification
  // --------------------------------------------------------------------------
  row_access_e row_access_type;
  bit bank_conflict_seen;
  bit refresh_seen;
  bit timing_err_seen;
  bit timing_check_seen;

  bit [2:0] req_cmd_kind;     // pseudo command kind for request coverage
  bit [2:0] cmd_kind;         // sampled command kind from DUT cmd stream
  bit [2:0] last_cmd_kind;

  bit [$clog2(BANK_GROUPS)-1:0] req_bg_s;
  bit [$clog2(BANKS_PER_GROUP)-1:0] req_bank_s;
  bit [COL_W-1:0] req_col_s;

  bit [$clog2(BANK_GROUPS)-1:0] cmd_bg_s;
  bit [$clog2(BANKS_PER_GROUP)-1:0] cmd_bank_s;
  bit [COL_W-1:0] cmd_col_s;

  int ccd_delta;
  int wtr_delta;
  int rtw_delta;

  int ccd_same_bg_delta;
  int ccd_diff_bg_delta;
  bit ccd_diff_bg_seen;
  int last_any_col_cycle;
  bit [$clog2(BANK_GROUPS)-1:0] last_any_col_bg;
  bit last_any_col_valid;

  // Open-row model per bank
  bit              row_open   [RANKS][BANK_GROUPS][BANKS_PER_GROUP];
  bit [ROW_W-1:0]  open_row   [RANKS][BANK_GROUPS][BANKS_PER_GROUP];

  // Previous request info for bank-conflict classification
  bit prev_req_valid;
  bit [$clog2(RANKS)-1:0]       prev_req_rank;
  bit [$clog2(BANK_GROUPS)-1:0] prev_req_bg;
  bit [$clog2(BANKS_PER_GROUP)-1:0] prev_req_bank;
  bit [ROW_W-1:0]               prev_req_row;

  // Previous command info for transition/timing coverage
  bit last_col_seen_per_bg [BANK_GROUPS];
  int last_col_cycle_bg    [BANK_GROUPS];

  bit last_read_seen;
  int last_read_cycle;

  bit last_write_seen;
  int last_write_cycle;

  int curr_cycle;

  // --------------------------------------------------------------------------
  // COVERGROUP 1: Request type distribution
  // Goal: both READ and WRITE requests exercised
  // --------------------------------------------------------------------------
  covergroup cg_req_type;
    option.per_instance = 1;
    cp_req_cmd: coverpoint req_cmd_kind {
      bins read  = {CMD_READ_E};
      bins write = {CMD_WRITE_E};
    }
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 2: Bank group / bank access
  // Goal: all 16 banks exercised by accepted requests
  // --------------------------------------------------------------------------
  covergroup cg_bank_access;
    option.per_instance = 1;
    cp_bg: coverpoint req_bg_s {
      bins all_bg[] = {[0:BANK_GROUPS-1]};
    }
    cp_bank: coverpoint req_bank_s {
      bins all_bank[] = {[0:BANKS_PER_GROUP-1]};
    }
    cx_all_banks: cross cp_bg, cp_bank;
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 3: Row access patterns
  // Goal: row hit / row miss / empty bank all covered
  // --------------------------------------------------------------------------
  covergroup cg_row_access;
    option.per_instance = 1;
    cp_row_type: coverpoint row_access_type {
      bins row_hit  = {ROW_HIT};
      bins row_miss = {ROW_MISS};
      bins empty    = {EMPTY_BANK};
    }
    cp_bg: coverpoint req_bg_s {
      bins all_bg[] = {[0:BANK_GROUPS-1]};
    }
    cx_access_per_bg: cross cp_row_type, cp_bg;
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 4: Timing-event coverage
  // Goal: legal and violating timing situations both visible
  // Note: timing_err_seen is inferred from observed command spacing
  // --------------------------------------------------------------------------

covergroup cg_timing_err;
  option.per_instance = 1;

  cp_check: coverpoint timing_check_seen {
    bins checked = {1};
  }

  cp_status: coverpoint timing_err_seen iff (timing_check_seen) {
    bins legal = {0};
    illegal_bins unexpected_error = {1};
  }
endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 5: Command transition coverage
  // Goal: capture key protocol sequences
  // --------------------------------------------------------------------------
  covergroup cg_cmd_sequence;
    option.per_instance = 1;
    cp_last: coverpoint last_cmd_kind {
    bins act     = {CMD_ACT_E};
    bins read    = {CMD_READ_E};
    bins write   = {CMD_WRITE_E};
    bins pre     = {CMD_PRE_E};
    bins refresh = {CMD_REF_E};
    }
    cp_curr: coverpoint cmd_kind {
    bins act     = {CMD_ACT_E};
    bins read    = {CMD_READ_E};
    bins write   = {CMD_WRITE_E};
    bins pre     = {CMD_PRE_E};
    bins refresh = {CMD_REF_E};
    }

    cx_transitions: cross cp_last, cp_curr {
      bins act_then_read   = binsof(cp_last.act)   && binsof(cp_curr.read);
      bins act_then_write  = binsof(cp_last.act)   && binsof(cp_curr.write);
      bins write_then_pre  = binsof(cp_last.write) && binsof(cp_curr.pre);
      bins read_then_pre   = binsof(cp_last.read)  && binsof(cp_curr.pre);
      bins pre_then_act    = binsof(cp_last.pre)   && binsof(cp_curr.act);
      bins write_then_read = binsof(cp_last.write) && binsof(cp_curr.read);
      bins read_then_write = binsof(cp_last.read)  && binsof(cp_curr.write);
    }
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 6: Refresh coverage
  // --------------------------------------------------------------------------
  covergroup cg_refresh;
    option.per_instance = 1;
    cp_refresh: coverpoint refresh_seen {
      bins no_refresh = {0};
      bins refresh    = {1};
    }
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 7: Column range coverage
  // Since COL_W=4 in your current TB, bins are adapted to 0..15
  // --------------------------------------------------------------------------
  covergroup cg_col_range;
    option.per_instance = 1;
    cp_col: coverpoint req_col_s {
      bins low_col  = {[0:3]};
      bins mid_col  = {[4:11]};
      bins high_col = {[12:15]};
    }
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 8: Bank conflict scenario
  // Same rank/bg/bank, different row, consecutive accepted requests
  // --------------------------------------------------------------------------
  covergroup cg_bank_conflict;
    option.per_instance = 1;
    cp_conflict: coverpoint bank_conflict_seen {
      bins no_conflict = {0};
      bins conflict    = {1};
    }
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 9: Command x BG cross
  // Ensures all BGs see ACT/READ/WRITE/PRE
  // --------------------------------------------------------------------------
  covergroup cg_cmd_bg_cross;
    option.per_instance = 1;
    // in cg_cmd_bg_cross
    cp_cmd: coverpoint cmd_kind {
    bins act     = {CMD_ACT_E};
    bins read    = {CMD_READ_E};
    bins write   = {CMD_WRITE_E};
    bins pre     = {CMD_PRE_E};
    bins refresh = {CMD_REF_E};
    }
    cp_bg: coverpoint cmd_bg_s {
      bins all_bg[] = {[0:BANK_GROUPS-1]};
    }
    cx_cmd_bg: cross cp_cmd, cp_bg;
  endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 10: tCCD boundary buckets
  // --------------------------------------------------------------------------
covergroup cg_tccd;
  option.per_instance = 1;
  cp_delta: coverpoint ccd_delta iff (ccd_delta >= tCCD_L) {
    bins boundary = {[tCCD_L:tCCD_L+2]};
    bins later    = {[tCCD_L+3:1000]};
  }
endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 11: tWTR boundary buckets
  // --------------------------------------------------------------------------
covergroup cg_twtr;
  option.per_instance = 1;
  cp_delta: coverpoint wtr_delta iff (wtr_delta >= tWTR) {
    bins boundary = {[tWTR:tWTR+2]};
    bins later    = {[tWTR+3:1000]};
  }
endgroup

  // --------------------------------------------------------------------------
  // COVERGROUP 12: tRTW boundary buckets
  // --------------------------------------------------------------------------
covergroup cg_trtw;
  option.per_instance = 1;
  cp_delta: coverpoint rtw_delta iff (rtw_delta >= tRTW) {
    bins boundary = {[tRTW:tRTW+2]};
    bins later    = {[tRTW+3:1000]};
  }
endgroup
//////////////////////////////////////////////////////
covergroup cg_tccd_s;
  option.per_instance = 1;
  cp_delta: coverpoint ccd_diff_bg_delta iff (ccd_diff_bg_delta >= tCCD_S) {
    bins boundary = {[tCCD_S:tCCD_S+2]};
    bins later    = {[tCCD_S+3:1000]};
  }
endgroup
  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);

    req_imp = new("req_imp", this);
    cmd_imp = new("cmd_imp", this);

    cg_req_type      = new();
    cg_bank_access   = new();
    cg_row_access    = new();
    cg_timing_err    = new();
    cg_cmd_sequence  = new();
    cg_refresh       = new();
    cg_col_range     = new();
    cg_bank_conflict = new();
    cg_cmd_bg_cross  = new();
    cg_tccd          = new();
    cg_twtr          = new();
    cg_trtw          = new();

    cg_tccd_s = new();
    last_any_col_valid = 0;
    last_any_col_cycle = -1;
    last_any_col_bg    = '0;

    foreach (row_open[r,bg,bk]) begin
      row_open[r][bg][bk] = 0;
      open_row[r][bg][bk] = '0;
    end

    for (int g = 0; g < BANK_GROUPS; g++) begin
      last_col_seen_per_bg[g] = 0;
      last_col_cycle_bg[g]    = -1;
    end

    last_read_seen   = 0;
    last_write_seen  = 0;
    last_read_cycle  = -1;
    last_write_cycle = -1;
    prev_req_valid   = 0;
    curr_cycle       = 0;
    last_cmd_kind    = CMD_NOP_E;
  endfunction

  // --------------------------------------------------------------------------
  // Accepted request coverage
  // --------------------------------------------------------------------------
  function void write_cov_req(ddr5_req_txn t);
    req_cmd_kind = t.is_write ? CMD_WRITE_E : CMD_READ_E;
    req_bg_s     = t.bg;
    req_bank_s   = t.bank;
    req_col_s    = t.col;

    // Row hit / miss / empty bank classification
    if (!row_open[t.rank][t.bg][t.bank]) begin
      row_access_type = EMPTY_BANK;
    end
    else if (open_row[t.rank][t.bg][t.bank] == t.row) begin
      row_access_type = ROW_HIT;
    end
    else begin
      row_access_type = ROW_MISS;
    end

    // Bank conflict scenario:
    // consecutive accepted requests to same bank but different rows
    if (prev_req_valid &&
        (prev_req_rank == t.rank) &&
        (prev_req_bg   == t.bg)   &&
        (prev_req_bank == t.bank) &&
        (prev_req_row  != t.row)) begin
      bank_conflict_seen = 1;
    end
    else begin
      bank_conflict_seen = 0;
    end

    cg_req_type.sample();
    cg_bank_access.sample();
    cg_row_access.sample();
    cg_col_range.sample();
    cg_bank_conflict.sample();

    prev_req_valid = 1;
    prev_req_rank  = t.rank;
    prev_req_bg    = t.bg;
    prev_req_bank  = t.bank;
    prev_req_row   = t.row;
  endfunction

  // --------------------------------------------------------------------------
  // DUT command coverage
  // --------------------------------------------------------------------------
  function void write_cov_cmd(ddr5_cmd_txn c);
    curr_cycle = c.cycle_num;
    cmd_kind   = c.cmd_code;
    cmd_bg_s   = c.cmd_bg;
    cmd_bank_s = c.cmd_bank;
    cmd_col_s  = c.cmd_col;

    timing_check_seen = 0;
    timing_err_seen   = 0;

    refresh_seen    = (c.cmd_code == CMD_REF_E);
    timing_err_seen = 0;
    ccd_delta       = -1;
    wtr_delta       = -1;
    rtw_delta       = -1;

    // tCCD sampling for READ/WRITE commands within same BG
    ccd_same_bg_delta = -1;
    ccd_diff_bg_delta = -1;
    ccd_diff_bg_seen  = 0;

    if ((c.cmd_code == CMD_READ_E) || (c.cmd_code == CMD_WRITE_E)) begin
      // same-BG spacing
        if (last_col_seen_per_bg[c.cmd_bg]) begin
        timing_check_seen = 1;
        ccd_same_bg_delta = c.cycle_num - last_col_cycle_bg[c.cmd_bg];
        ccd_delta         = ccd_same_bg_delta;
        if (ccd_same_bg_delta < tCCD_L)
            timing_err_seen = 1;
        cg_tccd.sample();
        end

      // diff-BG spacing
        if (last_any_col_valid && (last_any_col_bg != c.cmd_bg)) begin
        timing_check_seen = 1;
        ccd_diff_bg_seen  = 1;
        ccd_diff_bg_delta = c.cycle_num - last_any_col_cycle;
        if (ccd_diff_bg_delta < tCCD_S)
            timing_err_seen = 1;
        cg_tccd_s.sample();
        end

      last_col_seen_per_bg[c.cmd_bg] = 1;
      last_col_cycle_bg[c.cmd_bg]    = c.cycle_num;

      last_any_col_valid = 1;
      last_any_col_cycle = c.cycle_num;
      last_any_col_bg    = c.cmd_bg;
    end

    // tWTR sampling: READ after WRITE
    if (c.cmd_code == CMD_READ_E) begin
        if (last_write_seen) begin
            timing_check_seen = 1;
            wtr_delta = c.cycle_num - last_write_cycle;
            if (wtr_delta < tWTR)
            timing_err_seen = 1;
        end
        cg_twtr.sample();
        last_read_seen  = 1;
        last_read_cycle = c.cycle_num;
        end

    // tRTW sampling: WRITE after READ
if (c.cmd_code == CMD_WRITE_E) begin
  if (last_read_seen) begin
    timing_check_seen = 1;
    rtw_delta = c.cycle_num - last_read_cycle;
    if (rtw_delta < tRTW)
      timing_err_seen = 1;
  end
  cg_trtw.sample();
  last_write_seen  = 1;
  last_write_cycle = c.cycle_num;
end

    // Update open-row model from actual DUT command stream
    case (c.cmd_code)
      CMD_ACT_E: begin
        row_open[c.cmd_rank][c.cmd_bg][c.cmd_bank] = 1;
        open_row[c.cmd_rank][c.cmd_bg][c.cmd_bank] = c.cmd_row;
      end

      CMD_PRE_E: begin
        row_open[c.cmd_rank][c.cmd_bg][c.cmd_bank] = 0;
      end

      CMD_REF_E: begin
        foreach (row_open[r,bg,bk]) begin
          row_open[r][bg][bk] = 0;
        end
      end

      default: begin
      end
    endcase

    cg_timing_err.sample();
    cg_cmd_sequence.sample();
    cg_refresh.sample();
    cg_cmd_bg_cross.sample();
    last_cmd_kind = cmd_kind;
  endfunction

  // --------------------------------------------------------------------------
  // Report
  // --------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    real total_cov;
    total_cov =
      (cg_req_type.get_coverage()      +
       cg_bank_access.get_coverage()   +
       cg_row_access.get_coverage()    +
       cg_timing_err.get_coverage()    +
       cg_cmd_sequence.get_coverage()  +
       cg_refresh.get_coverage()       +
       cg_col_range.get_coverage()     +
       cg_bank_conflict.get_coverage() +
       cg_cmd_bg_cross.get_coverage()  +
       cg_tccd.get_coverage()          +
       cg_twtr.get_coverage()          +
       cg_trtw.get_coverage()          +
       cg_tccd_s.get_coverage()) / 13.0;

    `uvm_info("COV", "========================================", UVM_MEDIUM)
    `uvm_info("COV", "     FUNCTIONAL COVERAGE REPORT         ", UVM_MEDIUM)
    `uvm_info("COV", "========================================", UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_req_type      : %0.1f%%", cg_req_type.get_coverage()),      UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_bank_access   : %0.1f%%", cg_bank_access.get_coverage()),   UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_row_access    : %0.1f%%", cg_row_access.get_coverage()),    UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_timing_err    : %0.1f%%", cg_timing_err.get_coverage()),    UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_cmd_sequence  : %0.1f%%", cg_cmd_sequence.get_coverage()),  UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_refresh       : %0.1f%%", cg_refresh.get_coverage()),       UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_col_range     : %0.1f%%", cg_col_range.get_coverage()),     UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_bank_conflict : %0.1f%%", cg_bank_conflict.get_coverage()), UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_cmd_bg_cross  : %0.1f%%", cg_cmd_bg_cross.get_coverage()),  UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_tccd          : %0.1f%%", cg_tccd.get_coverage()),          UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_twtr          : %0.1f%%", cg_twtr.get_coverage()),          UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_trtw          : %0.1f%%", cg_trtw.get_coverage()),          UVM_MEDIUM)
    `uvm_info("COV", $sformatf("cg_tccd_s        : %0.1f%%", cg_tccd_s.get_coverage()), UVM_MEDIUM)
    `uvm_info("COV", $sformatf("TOTAL COVERAGE   : %0.1f%%", total_cov),                        UVM_MEDIUM)

    `uvm_info("COV", "========================================", UVM_MEDIUM)
  endfunction

endclass
