// =============================================================================
// BASE SEQUENCE
// =============================================================================
class ddr5_base_seq extends uvm_sequence #(ddr5_req_txn);
  `uvm_object_utils(ddr5_base_seq)

  function new(string name = "ddr5_base_seq");
    super.new(name);
  endfunction

  task send(bit wr, bit [ADDR_W-1:0] a, bit [DATA_BUS_W-1:0] d = '0);
    ddr5_req_txn t;
    t = ddr5_req_txn::type_id::create("t");
    start_item(t);
    if (!t.randomize() with {
      is_write == wr;
      addr     == a;
      wdata    == d;
    }) begin
      `uvm_fatal("RAND", "send() randomize failed")
    end
    finish_item(t);
  endtask
endclass


// =============================================================================
// DIRECTED SEQUENCES
// =============================================================================
class ddr5_row_hit_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_row_hit_seq)
  function new(string name = "ddr5_row_hit_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a;
    a = tb_make_addr(4'd1, 1'd0, 2'd0, 2'd2, 4'd4);
    send(1, a, make_burst_data(32'hA5A5_0001));
    send(0, a);
    send(0, a);
  endtask
endclass

class ddr5_row_miss_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_row_miss_seq)
  function new(string name = "ddr5_row_miss_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a0, a1;
    a0 = tb_make_addr(4'd2, 1'd0, 2'd1, 2'd1, 4'd8);
    a1 = tb_make_addr(4'd3, 1'd0, 2'd1, 2'd1, 4'd8);
    send(1, a0, make_burst_data(32'h1111_0002));
    send(1, a1, make_burst_data(32'h2222_0003));
    send(0, a1);
  endtask
endclass

class ddr5_multi_bank_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_multi_bank_seq)
  function new(string name = "ddr5_multi_bank_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a;
    bit [1:0] bg_v, bk_v;

    for (int bg_i = 0; bg_i < 4; bg_i++) begin
      for (int bk_i = 0; bk_i < 4; bk_i++) begin
        bg_v = bg_i;
        bk_v = bk_i;
        a = tb_make_addr((bg_i*4+bk_i+1) & 4'hF, 1'd0, bg_v, bk_v, (bg_i*4+bk_i) & 4'hF);
        send(1, a, make_burst_data(32'h1000_0000 | (bg_i << 8) | (bk_i << 4)));
      end
    end

    for (int bg_i = 0; bg_i < 4; bg_i++) begin
      for (int bk_i = 0; bk_i < 4; bk_i++) begin
        bg_v = bg_i;
        bk_v = bk_i;
        a = tb_make_addr((bg_i*4+bk_i+1) & 4'hF, 1'd0, bg_v, bk_v, (bg_i*4+bk_i) & 4'hF);
        send(0, a);
      end
    end
  endtask
endclass

class ddr5_multi_rank_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_multi_rank_seq)
  function new(string name = "ddr5_multi_rank_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a0, a1;
    a0 = tb_make_addr(4'd7, 1'd0, 2'd3, 2'd1, 4'd9);
    a1 = tb_make_addr(4'd8, 1'd1, 2'd3, 2'd1, 4'd10);
    send(1, a0, make_burst_data(32'hAAAA_0001));
    send(1, a1, make_burst_data(32'hBBBB_0002));
    send(0, a0);
    send(0, a1);
  endtask
endclass

class ddr5_wtr_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_wtr_seq)
  function new(string name = "ddr5_wtr_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a;
    a = tb_make_addr(4'd9, 1'd0, 2'd3, 2'd0, 4'd8);
    send(1, a, make_burst_data(32'hDEAD_BEEF));
    send(0, a);
  endtask
endclass

class ddr5_rtw_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_rtw_seq)
  function new(string name = "ddr5_rtw_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a0, a1;
    a0 = tb_make_addr(4'd10, 1'd0, 2'd0, 2'd0, 4'd1);
    a1 = tb_make_addr(4'd10, 1'd0, 2'd1, 2'd0, 4'd1);
    send(1, a0, make_burst_data(32'h1234_5678));
    send(0, a0);
    send(1, a1, make_burst_data(32'h8765_4321));
  endtask
endclass

class ddr5_ccd_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_ccd_seq)
  function new(string name = "ddr5_ccd_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a0, a1, a2;
    a0 = tb_make_addr(4'd5, 1'd0, 2'd0, 2'd0, 4'd4);
    a1 = tb_make_addr(4'd5, 1'd0, 2'd1, 2'd0, 4'd4);
    a2 = tb_make_addr(4'd5, 1'd0, 2'd1, 2'd1, 4'd4);

    send(1, a0, make_burst_data(32'hCC00_0000));
    send(1, a1, make_burst_data(32'hCC00_1000));
    send(1, a2, make_burst_data(32'hCC00_2000));

    send(0, a0);
    send(0, a1);
    send(0, a2);
  endtask
endclass

class ddr5_refresh_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_refresh_seq)
  function new(string name = "ddr5_refresh_seq"); super.new(name); endfunction
  task body();
    bit [ADDR_W-1:0] a;
    bit [1:0] bg_v, bk_v;

    for (int i = 0; i < 8; i++) begin
      bg_v = i % 4;
      bk_v = i / 4;
      a = tb_make_addr((i+1) & 4'hF, 1'd0, bg_v, bk_v, (i*2) & 4'hF);
      send(1, a, make_burst_data(32'hCAFE_0000 | i));
    end

    for (int i = 0; i < 8; i++) begin
      bg_v = i % 4;
      bk_v = i / 4;
      a = tb_make_addr((i+1) & 4'hF, 1'd0, bg_v, bk_v, (i*2) & 4'hF);
      send(0, a);
    end
  endtask
endclass

class ddr5_stress_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_stress_seq)
  int unsigned num_txns;
  function new(string name = "ddr5_stress_seq");
    super.new(name);
    num_txns = 200;
  endfunction

  task body();
    ddr5_req_txn t;
    repeat (num_txns) begin
      t = ddr5_req_txn::type_id::create("stress_t");
      start_item(t);
      if (!t.randomize()) `uvm_fatal("RAND", "stress randomize failed")
      if (t.is_write)
        t.wdata = make_burst_data($urandom());
      finish_item(t);
    end
  endtask
endclass
//////////////////////
class ddr5_trcd_exact_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_trcd_exact_seq)
  function new(string name = "ddr5_trcd_exact_seq"); super.new(name); endfunction

  task body();
    bit [ADDR_W-1:0] a;
    a = tb_make_addr(4'd4, 1'd0, 2'd0, 2'd1, 4'd3);

    send(1, a, make_burst_data(32'hABCD_1000));
    send(0, a);
  endtask
endclass

class ddr5_twtr_exact_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_twtr_exact_seq)
  function new(string name = "ddr5_twtr_exact_seq"); super.new(name); endfunction

  task body();
    bit [ADDR_W-1:0] a;
    a = tb_make_addr(4'd6, 1'd0, 2'd2, 2'd1, 4'd4);

    send(1, a, make_burst_data(32'hFACE_0001));
    send(0, a);
  endtask
endclass

class ddr5_trtw_exact_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_trtw_exact_seq)
  function new(string name = "ddr5_trtw_exact_seq"); super.new(name); endfunction

  task body();
    bit [ADDR_W-1:0] a0, a1;
    a0 = tb_make_addr(4'd7, 1'd0, 2'd0, 2'd0, 4'd2);
    a1 = tb_make_addr(4'd7, 1'd0, 2'd1, 2'd0, 4'd2);

    send(1, a0, make_burst_data(32'h1111_2222));
    send(0, a0);
    send(1, a1, make_burst_data(32'h3333_4444));
  endtask
endclass

class ddr5_tccd_s_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_tccd_s_seq)
  function new(string name = "ddr5_tccd_s_seq"); super.new(name); endfunction

  task body();
    bit [ADDR_W-1:0] a0, a1;
    a0 = tb_make_addr(4'd3, 1'd0, 2'd0, 2'd0, 4'd1);
    a1 = tb_make_addr(4'd3, 1'd0, 2'd1, 2'd0, 4'd1);

    send(1, a0, make_burst_data(32'hAAA0_0001));
    send(1, a1, make_burst_data(32'hBBB0_0002));
    send(0, a0);
    send(0, a1);
  endtask
endclass

class ddr5_twtr_later_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_twtr_later_seq)
  function new(string name = "ddr5_twtr_later_seq");
    super.new(name);
  endfunction

  task body();
    bit [ADDR_W-1:0] a0, a1, a2, a3;

    a0 = tb_make_addr(4'd6, 1'd0, 2'd2, 2'd1, 4'd4); // target
    a1 = tb_make_addr(4'd1, 1'd0, 2'd0, 2'd0, 4'd1);
    a2 = tb_make_addr(4'd2, 1'd0, 2'd1, 2'd0, 4'd2);
    a3 = tb_make_addr(4'd3, 1'd0, 2'd3, 2'd0, 4'd3);

    send(1, a0, make_burst_data(32'hFACE_1001)); // WRITE target

    // create extra delay
    send(1, a1, make_burst_data(32'h1111_0001));
    send(1, a2, make_burst_data(32'h2222_0002));
    send(1, a3, make_burst_data(32'h3333_0003));

    send(0, a0); // delayed READ -> should hit "later"
  endtask
endclass

class ddr5_trtw_later_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_trtw_later_seq)
  function new(string name = "ddr5_trtw_later_seq");
    super.new(name);
  endfunction

  task body();
    bit [ADDR_W-1:0] a0, a1, a2, a3;

    a0 = tb_make_addr(4'd7, 1'd0, 2'd0, 2'd0, 4'd2); // target read
    a1 = tb_make_addr(4'd1, 1'd0, 2'd1, 2'd1, 4'd1);
    a2 = tb_make_addr(4'd2, 1'd0, 2'd2, 2'd1, 4'd2);
    a3 = tb_make_addr(4'd3, 1'd0, 2'd3, 2'd1, 4'd3);

    send(1, a0, make_burst_data(32'hAAAA_1111));
    send(0, a0); // READ target

    // create extra delay
    send(0, a1);
    send(0, a2);
    send(0, a3);

    send(1, a1, make_burst_data(32'hBBBB_2222)); // delayed WRITE -> should hit "later"
  endtask
endclass

class ddr5_tccd_s_later_seq extends ddr5_base_seq;
  `uvm_object_utils(ddr5_tccd_s_later_seq)
  function new(string name = "ddr5_tccd_s_later_seq");
    super.new(name);
  endfunction

  task body();
    bit [ADDR_W-1:0] a_bg0, a_bg1, a_mid0, a_mid1;

    a_bg0  = tb_make_addr(4'd3, 1'd0, 2'd0, 2'd0, 4'd1);
    a_bg1  = tb_make_addr(4'd3, 1'd0, 2'd1, 2'd0, 4'd1);
    a_mid0 = tb_make_addr(4'd4, 1'd0, 2'd2, 2'd0, 4'd2);
    a_mid1 = tb_make_addr(4'd5, 1'd0, 2'd3, 2'd0, 4'd3);

    send(1, a_bg0, make_burst_data(32'hAAA0_1001));
    send(1, a_bg1, make_burst_data(32'hBBB0_1002));

    // first set of reads may already hit boundary
    send(0, a_bg0);

    // insert extra column traffic to increase gap
    send(0, a_mid0);
    send(0, a_mid1);

    send(0, a_bg1); // different BG with larger gap -> should hit "later"
  endtask
endclass
