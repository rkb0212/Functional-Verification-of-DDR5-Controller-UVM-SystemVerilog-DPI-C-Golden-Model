// =============================================================================
// GLOBAL TB PARAMETERS
// =============================================================================
package ddr5_tb_params_pkg;
  parameter int ADDR_W            = 32;
  parameter int DATA_W            = 32;
  parameter int ROW_W             = 4;
  parameter int COL_W             = 4;
  parameter int RANKS             = 2;
  parameter int BANK_GROUPS       = 4;
  parameter int BANKS_PER_GROUP   = 4;
  parameter int BURST_LEN         = 16;
  parameter int DATA_BUS_W        = DATA_W * BURST_LEN;
  parameter int MEM_DEPTH         = 4096;
  parameter int MEM_IDX_W         = $clog2(MEM_DEPTH);

  parameter int tRCD              = 4;
  parameter int tRAS              = 8;
  parameter int tRP               = 4;
  parameter int tRC               = 12;
  parameter int tWTR              = 4;
  parameter int CL                = 4;
  parameter int tCWL              = 4;
  parameter int tRTW              = 6;
  parameter int tRFC              = 16;
  parameter int tCCD_L            = 8;
  parameter int tCCD_S            = 4;
  parameter int tRAS_MAX          = 64;
endpackage
