// =============================================================================
// MONITOR
// =============================================================================
class ddr5_monitor extends uvm_monitor;
  `uvm_component_utils(ddr5_monitor)

  virtual ddr5_dut_if vif;
  uvm_analysis_port #(ddr5_req_txn) req_ap;
  uvm_analysis_port #(ddr5_req_txn) rsp_ap;
  uvm_analysis_port #(ddr5_cmd_txn) cmd_ap;

  int cycle_num;
  int unsigned n_writes, n_reads, n_cmds, n_refresh;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    req_ap = new("req_ap", this);
    rsp_ap = new("rsp_ap", this);
    cmd_ap = new("cmd_ap", this);
    if (!uvm_config_db#(virtual ddr5_dut_if)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "ddr5_monitor: no vif")
  endfunction

task run_phase(uvm_phase phase);
  ddr5_req_txn req_t;
  ddr5_req_txn rsp_t;
  ddr5_cmd_txn cmd_t;

  cycle_num = 0;
  @(posedge vif.mon_cb.rst_n);
  repeat (2) @(vif.mon_cb);

  forever begin
    @(vif.mon_cb);
    cycle_num++;

    // 1) Capture response FIRST
    if (vif.mon_cb.rsp_valid) begin
      rsp_t = ddr5_req_txn::type_id::create("rsp_t", this);
      rsp_t.rdata    = vif.mon_cb.rsp_rdata;
      rsp_t.rsp_seen = 1'b1;
      rsp_t.rsp_time = $time;
      rsp_ap.write(rsp_t);
    end

    // 2) Capture command stream
    if (vif.mon_cb.cmd_valid) begin
      cmd_t = ddr5_cmd_txn::type_id::create("cmd_t", this);
      cmd_t.cmd_code  = vif.mon_cb.cmd_code;
      cmd_t.cmd_rank  = vif.mon_cb.cmd_rank;
      cmd_t.cmd_bg    = vif.mon_cb.cmd_bg;
      cmd_t.cmd_bank  = vif.mon_cb.cmd_bank;
      cmd_t.cmd_row   = vif.mon_cb.cmd_row;
      cmd_t.cmd_col   = vif.mon_cb.cmd_col;
      cmd_t.cycle_num = cycle_num;
      n_cmds++;
      if (cmd_t.cmd_code == 3'd5) n_refresh++;
      cmd_ap.write(cmd_t);
    end

    // 3) Capture request AFTER response
    if (vif.mon_cb.req_valid && vif.mon_cb.req_ready) begin
      req_t = ddr5_req_txn::type_id::create("req_t", this);
      req_t.is_write   = vif.mon_cb.req_write;
      req_t.addr       = vif.mon_cb.req_addr;
      req_t.wdata      = vif.mon_cb.req_wdata;
      req_t.col        = vif.mon_cb.req_addr[COL_W-1:0];
      req_t.bank       = vif.mon_cb.req_addr[COL_W +: $clog2(BANKS_PER_GROUP)];
      req_t.bg         = vif.mon_cb.req_addr[COL_W + $clog2(BANKS_PER_GROUP) +: $clog2(BANK_GROUPS)];
      req_t.rank       = vif.mon_cb.req_addr[COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) +: $clog2(RANKS)];
      req_t.row        = vif.mon_cb.req_addr[ADDR_W-1 -: ROW_W];
      req_t.issue_time = $time;

      if (req_t.is_write) n_writes++;
      else                n_reads++;

      req_ap.write(req_t);
    end
  end
endtask

  task monitor_requests();
    ddr5_req_txn t;
    forever begin
      @(vif.mon_cb);
      cycle_num++;
      if (vif.mon_cb.req_valid && vif.mon_cb.req_ready) begin
        t = ddr5_req_txn::type_id::create("req_t", this);
        t.is_write  = vif.mon_cb.req_write;
        t.addr      = vif.mon_cb.req_addr;
        t.wdata     = vif.mon_cb.req_wdata;
        t.col       = vif.mon_cb.req_addr[COL_W-1:0];
        t.bank      = vif.mon_cb.req_addr[COL_W +: $clog2(BANKS_PER_GROUP)];
        t.bg        = vif.mon_cb.req_addr[COL_W + $clog2(BANKS_PER_GROUP) +: $clog2(BANK_GROUPS)];
        t.rank      = vif.mon_cb.req_addr[COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) +: $clog2(RANKS)];
        t.row       = vif.mon_cb.req_addr[ADDR_W-1 -: ROW_W];
        t.issue_time = $time;

        if (t.is_write) n_writes++; else n_reads++;
        req_ap.write(t);
      end
    end
  endtask

  task monitor_responses();
    ddr5_req_txn t;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rsp_valid) begin
        t = ddr5_req_txn::type_id::create("rsp_t", this);
        t.rdata    = vif.mon_cb.rsp_rdata;
        t.rsp_seen = 1'b1;
        t.rsp_time = $time;
        rsp_ap.write(t);
      end
    end
  endtask

  task monitor_commands();
    ddr5_cmd_txn c;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.cmd_valid) begin
        c = ddr5_cmd_txn::type_id::create("cmd_t", this);
        c.cmd_code  = vif.mon_cb.cmd_code;
        c.cmd_rank  = vif.mon_cb.cmd_rank;
        c.cmd_bg    = vif.mon_cb.cmd_bg;
        c.cmd_bank  = vif.mon_cb.cmd_bank;
        c.cmd_row   = vif.mon_cb.cmd_row;
        c.cmd_col   = vif.mon_cb.cmd_col;
        c.cycle_num = cycle_num;
        n_cmds++;
        if (c.cmd_code == 3'd5) n_refresh++;
        cmd_ap.write(c);
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("MON",
      $sformatf("writes=%0d reads=%0d cmds=%0d refresh=%0d",
                n_writes, n_reads, n_cmds, n_refresh),
      UVM_MEDIUM)
  endfunction
endclass
