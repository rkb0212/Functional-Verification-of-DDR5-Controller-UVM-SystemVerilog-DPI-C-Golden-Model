// =============================================================================
// AGENT
// =============================================================================
class ddr5_agent extends uvm_agent;
  `uvm_component_utils(ddr5_agent)

  ddr5_driver driver;
  ddr5_monitor monitor;
  uvm_sequencer #(ddr5_req_txn) sequencer;

  uvm_analysis_port #(ddr5_req_txn) req_ap;
  uvm_analysis_port #(ddr5_req_txn) rsp_ap;
  uvm_analysis_port #(ddr5_cmd_txn) cmd_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    req_ap  = new("req_ap", this);
    rsp_ap  = new("rsp_ap", this);
    cmd_ap  = new("cmd_ap", this);

    monitor = ddr5_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = uvm_sequencer #(ddr5_req_txn)::type_id::create("sequencer", this);
      driver    = ddr5_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);

    monitor.req_ap.connect(req_ap);
    monitor.rsp_ap.connect(rsp_ap);
    monitor.cmd_ap.connect(cmd_ap);
  endfunction
endclass
