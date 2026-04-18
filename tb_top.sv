`timescale 1ns/1ns
`include "uvm_macros.svh"
import uvm_pkg::*;

`include "ddr5_tb_params_pkg.sv"
`include "ddr5_tb_utils_pkg.sv"
`include "ddr5_dut_if.sv"
`include "ddr5_tb_pkg.sv"

import ddr5_tb_params_pkg::*;
import ddr5_tb_utils_pkg::*;
import ddr5_tb_pkg::*;

// =============================================================================
// DDR5 Controller DUT — Updated UVM Testbench (Riviera-safe)
// =============================================================================
// What this TB does:
//   1) Matches current DUT interface:
//        - req_wdata/rsp_rdata are DATA_W*BURST_LEN wide (512 bits)
//   2) Generates BL16 burst payloads for writes
//   3) Logs WRITEs explicitly in scoreboard so writes show in transcript
//   4) Tracks expected read data by FULL ADDRESS (not only mem_idx)
//      to match current DUT row-buffer behavior more closely
//   5) Monitors command stream and checks simple timing relationships:
//        - same-BG tCCD_L
//        - tWTR
//        - tRTW
//
// Not included yet:
//   - functional coverage
//   - assertions / SVA
//   - advanced protocol model
// =============================================================================

// =============================================================================
// TOP
// =============================================================================
module tb_top;
  logic clk;
  ddr5_dut_if dut_if(clk);

  initial clk = 0;
  always #5 clk = ~clk;

  ddr5_controller_dut #(
    .ADDR_W(32),
    .DATA_W(32),
    .ROW_W(4),
    .COL_W(4),
    .RANKS(2),
    .BANK_GROUPS(4),
    .BANKS_PER_GROUP(4),
    .BURST_LEN(16),
    .tRCD(4),
    .tRAS(8),
    .tRP(4),
    .tRC(12),
    .tWTR(4),
    .CL(4),
    .tCWL(4),
    .tRTW(6),
    .tRFC(16),
    .tCCD_L(8),
    .tCCD_S(4),
    .tRAS_MAX(64),
    .MEM_DEPTH(4096)
  ) dut (
    .clk       (clk),
    .rst_n     (dut_if.rst_n),
    .req_valid (dut_if.req_valid),
    .req_ready (dut_if.req_ready),
    .req_write (dut_if.req_write),
    .req_addr  (dut_if.req_addr),
    .req_wdata (dut_if.req_wdata),
    .rsp_valid (dut_if.rsp_valid),
    .rsp_rdata (dut_if.rsp_rdata),
    .busy      (dut_if.busy),
    .cmd_valid (dut_if.cmd_valid),
    .cmd_code  (dut_if.cmd_code),
    .cmd_rank  (dut_if.cmd_rank),
    .cmd_bg    (dut_if.cmd_bg),
    .cmd_bank  (dut_if.cmd_bank),
    .cmd_row   (dut_if.cmd_row),
    .cmd_col   (dut_if.cmd_col)
  );

  initial begin
    uvm_config_db#(virtual ddr5_dut_if)::set(uvm_root::get(), "*", "vif", dut_if);
    run_test("ddr5_regression_test");
  end

  initial begin
    #500_000;
    `uvm_fatal("TB", "Simulation timeout after 500us")
  end

  initial begin
    $dumpfile("ddr5_dut_waves.vcd");
    $dumpvars(0, tb_top);
  end
endmodule
