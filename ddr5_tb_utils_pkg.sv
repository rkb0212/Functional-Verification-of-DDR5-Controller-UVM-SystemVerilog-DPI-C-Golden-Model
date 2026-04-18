// =============================================================================
// HELPER FUNCTIONS
// =============================================================================
package ddr5_tb_utils_pkg;
  import ddr5_tb_params_pkg::*;

  // Build a BL16 payload from a 32-bit seed.
  // Beat i contains (seed + i).
  function automatic bit [DATA_BUS_W-1:0] make_burst_data(input bit [31:0] seed);
    bit [DATA_BUS_W-1:0] tmp;
    for (int i = 0; i < BURST_LEN; i++) begin
      tmp[i*DATA_W +: DATA_W] = seed + i;
    end
    return tmp;
  endfunction

  function automatic int unsigned get_mem_idx(input bit [ADDR_W-1:0] addr);
    return addr[MEM_IDX_W-1:0];
  endfunction

  function automatic bit [ADDR_W-1:0] tb_make_addr(
    input bit [ROW_W-1:0] row,
    input bit [$clog2(RANKS)-1:0] rank,
    input bit [$clog2(BANK_GROUPS)-1:0] bg,
    input bit [$clog2(BANKS_PER_GROUP)-1:0] bank,
    input bit [COL_W-1:0] col
  );
    bit [ADDR_W-1:0] a;
    a = '0;
    a[COL_W-1:0] = col;
    a[COL_W +: $clog2(BANKS_PER_GROUP)] = bank;
    a[COL_W + $clog2(BANKS_PER_GROUP) +: $clog2(BANK_GROUPS)] = bg;
    a[COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) +: $clog2(RANKS)] = rank;
    a[ADDR_W-1 -: ROW_W] = row;
    return a;
  endfunction

  function automatic bit [ADDR_W-1:0] canonical_addr(input bit [ADDR_W-1:0] addr);
    bit [ADDR_W-1:0] a;
    a = '0;
    a[COL_W-1:0] = addr[COL_W-1:0];
    a[COL_W +: $clog2(BANKS_PER_GROUP)] =
        addr[COL_W +: $clog2(BANKS_PER_GROUP)];
    a[COL_W + $clog2(BANKS_PER_GROUP) +: $clog2(BANK_GROUPS)] =
        addr[COL_W + $clog2(BANKS_PER_GROUP) +: $clog2(BANK_GROUPS)];
    a[COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) +: $clog2(RANKS)] =
        addr[COL_W + $clog2(BANKS_PER_GROUP) + $clog2(BANK_GROUPS) +: $clog2(RANKS)];
    a[ADDR_W-1 -: ROW_W] = addr[ADDR_W-1 -: ROW_W];
    return a;
  endfunction
endpackage
