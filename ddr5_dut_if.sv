// =============================================================================
// INTERFACE
// =============================================================================
interface ddr5_dut_if(input logic clk);
  import ddr5_tb_params_pkg::*;

  logic                  rst_n;

  logic                  req_valid;
  logic                  req_ready;
  logic                  req_write;
  logic [ADDR_W-1:0]     req_addr;
  logic [DATA_BUS_W-1:0] req_wdata;

  logic                  rsp_valid;
  logic [DATA_BUS_W-1:0] rsp_rdata;
  logic                  busy;

  logic                  cmd_valid;
  logic [2:0]            cmd_code;
  logic [$clog2(RANKS)-1:0]           cmd_rank;
  logic [$clog2(BANK_GROUPS)-1:0]     cmd_bg;
  logic [$clog2(BANKS_PER_GROUP)-1:0] cmd_bank;
  logic [ROW_W-1:0]      cmd_row;
  logic [COL_W-1:0]      cmd_col;

  // Driver clocking block
  clocking drv_cb @(posedge clk);
    default input #1step output #1step;
    output rst_n;
    output req_valid;
    output req_write;
    output req_addr;
    output req_wdata;
    input  req_ready;
    input  rsp_valid;
    input  rsp_rdata;
    input  busy;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n;
    input req_valid;
    input req_ready;
    input req_write;
    input req_addr;
    input req_wdata;
    input rsp_valid;
    input rsp_rdata;
    input busy;
    input cmd_valid;
    input cmd_code;
    input cmd_rank;
    input cmd_bg;
    input cmd_bank;
    input cmd_row;
    input cmd_col;
  endclocking

endinterface
