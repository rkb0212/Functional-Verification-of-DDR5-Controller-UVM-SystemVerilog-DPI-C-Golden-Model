// =============================================================================
// DRIVER
// =============================================================================
class ddr5_driver extends uvm_driver #(ddr5_req_txn);
  `uvm_component_utils(ddr5_driver)
  virtual ddr5_dut_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ddr5_dut_if)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "ddr5_driver: no vif")
  endfunction

  task run_phase(uvm_phase phase);
    ddr5_req_txn txn;

    vif.drv_cb.req_valid <= 0;
    vif.drv_cb.req_write <= 0;
    vif.drv_cb.req_addr  <= '0;
    vif.drv_cb.req_wdata <= '0;
    vif.drv_cb.rst_n     <= 0;

    repeat (5) @(vif.drv_cb);
    vif.drv_cb.rst_n <= 1;
    repeat (3) @(vif.drv_cb);

    forever begin
      seq_item_port.get_next_item(txn);
      drive_item(txn);
      seq_item_port.item_done();
    end
  endtask

task drive_item(ddr5_req_txn txn);
  @(vif.drv_cb);
  while (!vif.drv_cb.req_ready || vif.drv_cb.rsp_valid) @(vif.drv_cb);

  vif.drv_cb.req_valid <= 1;
  vif.drv_cb.req_write <= txn.is_write;
  vif.drv_cb.req_addr  <= txn.addr;
  vif.drv_cb.req_wdata <= txn.wdata;
  txn.issue_time       = $time;

  @(vif.drv_cb);
  vif.drv_cb.req_valid <= 0;
  vif.drv_cb.req_write <= 0;
  vif.drv_cb.req_addr  <= '0;
  vif.drv_cb.req_wdata <= '0;

  // one idle cycle to avoid req/rsp overlap in monitor sampling
  @(vif.drv_cb);

  `uvm_info("DRV", txn.convert2string(), UVM_HIGH)
endtask
endclass
