// =============================================================================
// REQUEST / RESPONSE TRANSACTION
// =============================================================================
class ddr5_req_txn extends uvm_sequence_item;
  `uvm_object_utils(ddr5_req_txn)

  rand bit                  is_write;
  rand bit [ADDR_W-1:0]     addr;
  rand bit [DATA_BUS_W-1:0] wdata;

  rand bit [ROW_W-1:0]      row;
  rand bit [$clog2(RANKS)-1:0]           rank;
  rand bit [$clog2(BANK_GROUPS)-1:0]     bg;
  rand bit [$clog2(BANKS_PER_GROUP)-1:0] bank;
  rand bit [COL_W-1:0]      col;

  bit [DATA_BUS_W-1:0]      rdata;
  bit                       rsp_seen;
  time                      issue_time;
  time                      rsp_time;

  constraint c_rw   { is_write dist {1 := 50, 0 := 50}; }
  constraint c_row  { row  inside {[0:(1<<ROW_W)-1]}; }
  constraint c_col  { col  inside {[0:(1<<COL_W)-1]}; }
  constraint c_bank { bank inside {[0:BANKS_PER_GROUP-1]}; }
  constraint c_bg   { bg   inside {[0:BANK_GROUPS-1]}; }
  constraint c_rank { rank inside {[0:RANKS-1]}; }

constraint c_addr_pack {
  addr[COL_W-1:0] == col;
  addr[COL_W +: $clog2(BANKS_PER_GROUP)] == bank;
  addr[COL_W + $clog2(BANKS_PER_GROUP) +: $clog2(BANK_GROUPS)] == bg;
  addr[COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) +: $clog2(RANKS)] == rank;
  addr[ADDR_W-1 -: ROW_W] == row;

  // keep unused middle bits zero so addr is canonical
  if ((ADDR_W - ROW_W) > (COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) + $clog2(RANKS))) {
    addr[ADDR_W-ROW_W-1 :
         COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) + $clog2(RANKS)] == '0;
  }
}

  function new(string name = "ddr5_req_txn");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%08h idx=0x%0h row=%0d rank=%0d bg=%0d bank=%0d col=%0d wdata[31:0]=0x%08h rdata[31:0]=0x%08h rsp=%0d",
                     is_write ? "WR" : "RD",
                     addr, get_mem_idx(addr), row, rank, bg, bank, col,
                     wdata[31:0], rdata[31:0], rsp_seen);
  endfunction
endclass


// =============================================================================
// COMMAND OBSERVATION TRANSACTION
// =============================================================================
class ddr5_cmd_txn extends uvm_sequence_item;
  `uvm_object_utils(ddr5_cmd_txn)

  bit [$clog2(RANKS)-1:0]           cmd_rank;
  bit [$clog2(BANK_GROUPS)-1:0]     cmd_bg;
  bit [$clog2(BANKS_PER_GROUP)-1:0] cmd_bank;
  bit [2:0]                         cmd_code;
  bit [ROW_W-1:0]                   cmd_row;
  bit [COL_W-1:0]                   cmd_col;
  int                               cycle_num;

  function new(string name = "ddr5_cmd_txn");
    super.new(name);
  endfunction
endclass
