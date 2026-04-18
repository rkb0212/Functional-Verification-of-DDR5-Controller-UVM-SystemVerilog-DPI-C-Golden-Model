// =============================================================================
// DDR5 Controller DUT 
// =============================================================================
module ddr5_controller_dut #(
  // -----------------------------------------------------------------------
  // Configurable parameters
  // -----------------------------------------------------------------------
  parameter int ADDR_W            = 32,
  parameter int DATA_W            = 32,
  parameter int ROW_W             = 4,
  parameter int COL_W             = 4,
  parameter int CHANNELS          = 1,   // kept for completeness; 1 channel modeled
  parameter int RANKS             = 2,
  parameter int BANK_GROUPS       = 4,
  parameter int BANKS_PER_GROUP   = 4,
  parameter int BURST_LEN         = 16,  // DDR5 mandates BL16; assertion checks this

  // -----------------------------------------------------------------------
  // Timing parameters (all in controller clock cycles)
  // -----------------------------------------------------------------------
  parameter int tRCD              = 4,   // ACT→CAS delay
  parameter int tRAS              = 8,   // min row-active time
  parameter int tRP               = 4,   // precharge time
  parameter int tRC               = 12,  // row-cycle time  (should be >= tRAS+tRP)
  parameter int tWTR              = 4,   // write→read turnaround  [FIX-1]
  parameter int CL                = 4,   // CAS (read) latency
  parameter int tRFC              = 16,  // refresh cycle time
  parameter int tRAS_MAX          = 64,
  // -----------------------------------------------------------------------
  // NEW timing parameters 
  // -----------------------------------------------------------------------
  parameter int tCCD_L            = 8,   // column-to-column, same bank group
  parameter int tCCD_S            = 4,   //  column-to-column, different bank group
  parameter int tCWL              = 4,   //  CAS write latency
  parameter int tRTW              = 6,   //  read→write turnaround (bus direction flip)
  
  parameter int MEM_DEPTH         = 4096
)(
  // -----------------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------------
  input  logic                  clk,
  input  logic                  rst_n,

  // -----------------------------------------------------------------------
  // Request interface
  // -----------------------------------------------------------------------
  input  logic                  req_valid,
  output logic                  req_ready,
  input  logic                  req_write,
  input  logic [ADDR_W-1:0]     req_addr,
  input  logic [DATA_W*BURST_LEN-1:0]     req_wdata,

  // -----------------------------------------------------------------------
  // Response interface
  // -----------------------------------------------------------------------
  output logic                  rsp_valid,
  output logic [DATA_W*BURST_LEN-1:0]     rsp_rdata,
  output logic                  busy,

  // -----------------------------------------------------------------------
  // Debug / observability command stream
  // -----------------------------------------------------------------------
  output logic                  cmd_valid,
  output logic [2:0]            cmd_code,
  output logic [$clog2(RANKS)-1:0]           cmd_rank,
  output logic [$clog2(BANK_GROUPS)-1:0]     cmd_bg,
  output logic [$clog2(BANKS_PER_GROUP)-1:0] cmd_bank,
  output logic [ROW_W-1:0]      cmd_row,
  output logic [COL_W-1:0]      cmd_col
);

  // -----------------------------------------------------------------------
  // Derived widths
  // -----------------------------------------------------------------------
  localparam int BG_W       = (BANK_GROUPS    > 1) ? $clog2(BANK_GROUPS)    : 1;
  localparam int BANK_W     = (BANKS_PER_GROUP > 1) ? $clog2(BANKS_PER_GROUP) : 1;
  localparam int RANK_W     = (RANKS          > 1) ? $clog2(RANKS)          : 1;
  localparam int BANKS_TOTAL = RANKS * BANK_GROUPS * BANKS_PER_GROUP;
  localparam int MEM_IDX_W  = $clog2(MEM_DEPTH);

  // -----------------------------------------------------------------------
  // Compile-time check: DDR5 mandates BL16
  // -----------------------------------------------------------------------
  // $error() is evaluated at elaboration time.
  // This will produce a compile error if BURST_LEN != 16.
  // The single-beat memory model is an intentional DUT abstraction:
  // BL16 serialisation on a physical DQ bus is not modeled; each access
  // is represented as one DATA_W-wide word with CL / tCWL latency only.
  // -----------------------------------------------------------------------
    initial begin
    if (BURST_LEN !== 16)
        $fatal(1, "DDR5 mandates BURST_LEN=16; got %0d", BURST_LEN);

    if (tRC < (tRAS + tRP))
        $fatal(1, "tRC must be >= tRAS + tRP; got tRC=%0d tRAS=%0d tRP=%0d",
            tRC, tRAS, tRP);

    if (tRAS_MAX < tRAS)
        $fatal(1, "tRAS_MAX must be >= tRAS; got tRAS_MAX=%0d tRAS=%0d",
            tRAS_MAX, tRAS);

    if ((ROW_W + RANK_W + BG_W + BANK_W + COL_W) > ADDR_W)
        $fatal(1,
        "Address field widths exceed ADDR_W: total=%0d ADDR_W=%0d",
        (ROW_W + RANK_W + BG_W + BANK_W + COL_W), ADDR_W);

    if ((1 << MEM_IDX_W) != MEM_DEPTH)
        $fatal(1, "MEM_DEPTH must be a power of 2; got %0d", MEM_DEPTH);
    end

  // -----------------------------------------------------------------------
  // Command encoding
  // -----------------------------------------------------------------------
  typedef enum logic [2:0] {
    CMD_NOP   = 3'd0,
    CMD_ACT   = 3'd1,
    CMD_READ  = 3'd2,
    CMD_WRITE = 3'd3,
    CMD_PRE   = 3'd4,
    CMD_REF   = 3'd5
  } cmd_t;

  // -----------------------------------------------------------------------
  // FSM states
  // -----------------------------------------------------------------------
  typedef enum logic [3:0] {
    ST_IDLE       = 4'd0,
    ST_PRE_WAIT   = 4'd1,
    ST_ACT_ISSUE  = 4'd2,
    ST_RCD_WAIT   = 4'd3,
    ST_COL_ISSUE  = 4'd4,
    ST_READ_WAIT  = 4'd5,
    ST_WRITE_WAIT = 4'd6,   //  new state for tCWL
    ST_REF_ISSUE  = 4'd7,
    ST_REF_WAIT   = 4'd8
  } state_t;

  // -----------------------------------------------------------------------
  // Per-bank state
  // -----------------------------------------------------------------------
  typedef struct packed {
    logic                 open;
    logic [ROW_W-1:0]     open_row;
    logic [15:0]          trcd_ctr;   // ACT→CAS
    logic [15:0]          tras_ctr;   // min active time (gates PRE)
    logic [15:0]          trp_ctr;    // precharge time  (gates ACT)
    logic [15:0]          trc_ctr;    // row-cycle time  (gates next ACT)
    logic [15:0]          twtr_ctr;   // write→read      (gates READ after WRITE)
    logic [15:0]      tras_max_ctr;
  } bank_state_t;

  bank_state_t bank_state [BANKS_TOTAL];

  // -----------------------------------------------------------------------
  // tCCD counter: counts down from tCCD_L/S after each COL command.
  // When non-zero, further COL commands to ANY bank in this BG are blocked.
  // -----------------------------------------------------------------------
  logic [15:0] bg_ccd_ctr [BANK_GROUPS];   // per BG cooldown after col command

  // -----------------------------------------------------------------------
  // Module-level RTW counter 
  // Counts down after a READ is issued; WRITE blocked while non-zero.
  // -----------------------------------------------------------------------
  logic [15:0] trtw_ctr;

   // -----------------------------------------------------------------------
  // Memory and misc
  // -----------------------------------------------------------------------
  localparam int FULL_MEM_DEPTH =
      RANKS * BANK_GROUPS * BANKS_PER_GROUP * (1 << ROW_W) * (1 << COL_W);

  logic [DATA_W*BURST_LEN-1:0] mem_array [0:FULL_MEM_DEPTH-1];
  //int unsigned                 latched_mem_idx;
localparam int FULL_MEM_IDX_W = $clog2(FULL_MEM_DEPTH);
logic [FULL_MEM_IDX_W-1:0] latched_mem_idx;

  logic [DATA_W*BURST_LEN-1:0] rowbuf_data  [BANKS_TOTAL][0:(1<<COL_W)-1];
  logic                        rowbuf_valid [BANKS_TOTAL][0:(1<<COL_W)-1];
  
  state_t state;

  // Latched request
  logic                  latched_write;
  logic [ADDR_W-1:0]     latched_addr;
  logic [DATA_W*BURST_LEN-1:0]     latched_wdata;
  logic [ROW_W-1:0]      latched_row;
  logic [COL_W-1:0]      latched_col;
  logic [RANK_W-1:0]     latched_rank;
  logic [BG_W-1:0]       latched_bg;
  logic [BANK_W-1:0]     latched_bank;
  logic [$clog2(BANKS_TOTAL)-1:0] target_bank_idx;

  // General-purpose counters
  logic [15:0] wait_ctr;
  logic [15:0] refresh_ctr;
  logic        refresh_pending;
  logic [DATA_W*BURST_LEN-1:0] read_data_q;

  // all_precharged declared at module level [FIX from previous review]
 // logic all_precharged;
  logic forced_precharge;

  // -----------------------------------------------------------------------
  // Address decode functions
  // -----------------------------------------------------------------------
  function automatic [ROW_W-1:0] get_row(input logic [ADDR_W-1:0] a);
    get_row = a[ADDR_W-1 -: ROW_W];
  endfunction

  function automatic [COL_W-1:0] get_col(input logic [ADDR_W-1:0] a);
    get_col = a[COL_W-1:0];
  endfunction

  function automatic [BANK_W-1:0] get_bank(input logic [ADDR_W-1:0] a);
    get_bank = a[COL_W +: BANK_W];
  endfunction

  function automatic [BG_W-1:0] get_bg(input logic [ADDR_W-1:0] a);
    get_bg = a[COL_W + BANK_W +: BG_W];
  endfunction

  function automatic [RANK_W-1:0] get_rank(input logic [ADDR_W-1:0] a);
    get_rank = a[COL_W + BANK_W + BG_W +: RANK_W];
  endfunction

  function automatic int unsigned flatten_bank(
    input logic [RANK_W-1:0] rank,
    input logic [BG_W-1:0]   bg,
    input logic [BANK_W-1:0] bank
  );
    flatten_bank = (rank * BANK_GROUPS * BANKS_PER_GROUP) + (bg * BANKS_PER_GROUP) + bank;
  endfunction

    function automatic int unsigned flatten_mem_index(
        input logic [RANK_W-1:0] rank,
        input logic [BG_W-1:0]   bg,
        input logic [BANK_W-1:0] bank,
        input logic [ROW_W-1:0]  row,
        input logic [COL_W-1:0]  col
    );
        flatten_mem_index =
        (((((rank * BANK_GROUPS) + bg) * BANKS_PER_GROUP + bank)
            * (1 << ROW_W)) + row)
            * (1 << COL_W) + col;
    endfunction

  // -----------------------------------------------------------------------
  // Helper check functions
  // -----------------------------------------------------------------------
  function automatic logic row_hit(input int unsigned idx, input logic [ROW_W-1:0] row);
    row_hit = bank_state[idx].open && (bank_state[idx].open_row == row);
  endfunction

  function automatic logic bank_idle_for_act(input int unsigned idx);
    // FIX-1 note: trc_ctr and trp_ctr are now loaded with tXXX+1,
    // so == 0 check gives exactly the right guard.
    bank_idle_for_act = (!bank_state[idx].open)
                      && (bank_state[idx].trp_ctr == 0)
                      && (bank_state[idx].trc_ctr == 0);
  endfunction

  function automatic logic can_precharge(input int unsigned idx);
    can_precharge = bank_state[idx].open && (bank_state[idx].tras_ctr == 0);
  endfunction

  // READ  : bank open, tRCD expired, tWTR (write→read) expired, CCD ok, tRTW not blocking write side
  // WRITE : bank open, tRCD expired, tRTW (read→write) expired, CCD ok
  function automatic logic can_readwrite(
    input int unsigned     idx,
    input logic            is_read,
    input logic [BG_W-1:0] bg
  );
    logic bank_ready;
    logic ccd_clear;

    bank_ready = bank_state[idx].open && (bank_state[idx].trcd_ctr == 0);
    // ccd_clear  = ccd_all_clear();
    ccd_clear = (bg_ccd_ctr[bg] == 0);

    if (is_read) begin
      // READ: blocked by write→read turnaround and any active CCD cooldown
      can_readwrite = bank_ready && ccd_clear && (bank_state[idx].twtr_ctr == 0);
    end else begin
      // WRITE: blocked by read→write turnaround and any active CCD cooldown
      can_readwrite = bank_ready && ccd_clear && (trtw_ctr == 0);
    end
  endfunction 

  function automatic logic [ADDR_W-1:0] make_addr(
  input logic [ROW_W-1:0]  row,
  input logic [RANK_W-1:0] rank,
  input logic [BG_W-1:0]   bg,
  input logic [BANK_W-1:0] bank,
  input logic [COL_W-1:0]  col
);
  logic [ADDR_W-1:0] a;
  a = '0;
  a[COL_W-1:0] = col;
  a[COL_W +: BANK_W] = bank;
  a[COL_W + BANK_W +: BG_W] = bg;
  a[COL_W + BANK_W + BG_W +: RANK_W] = rank;
  a[ADDR_W-1 -: ROW_W] = row;
  return a;
endfunction

function automatic logic [RANK_W-1:0] bank_to_rank(input int unsigned idx);
  return idx / (BANK_GROUPS * BANKS_PER_GROUP);
endfunction

function automatic logic [BG_W-1:0] bank_to_bg(input int unsigned idx);
  return (idx / BANKS_PER_GROUP) % BANK_GROUPS;
endfunction

function automatic logic [BANK_W-1:0] bank_to_bank(input int unsigned idx);
  return idx % BANKS_PER_GROUP;
endfunction

function automatic logic bank_must_close(input int unsigned idx);
  bank_must_close = bank_state[idx].open && (bank_state[idx].tras_max_ctr == 0);
endfunction

function automatic logic any_bank_must_close();
  logic must_close;
  must_close = 1'b0;
  for (int k = 0; k < BANKS_TOTAL; k++) begin
    if (bank_must_close(k))
      must_close = 1'b1;
  end
  return must_close;
endfunction

  // -----------------------------------------------------------------------
  // Combinational outputs
  // -----------------------------------------------------------------------

  assign req_ready = (state == ST_IDLE) &&
                   !refresh_pending &&
                   !any_bank_must_close() &&
                   !rsp_valid;
  assign busy      = (state != ST_IDLE);

  // -----------------------------------------------------------------------
  // Main sequential logic
  // -----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state           <= ST_IDLE;
      rsp_valid       <= 1'b0;
      rsp_rdata       <= '0;
      cmd_valid       <= 1'b0;
      cmd_code        <= CMD_NOP;
      cmd_rank        <= '0;
      cmd_bg          <= '0;
      cmd_bank        <= '0;
      cmd_row         <= '0;
      cmd_col         <= '0;
      wait_ctr        <= '0;
      refresh_ctr     <= 16'd100;
      refresh_pending <= 1'b0;
      latched_write   <= 1'b0;
      latched_addr    <= '0;
      latched_mem_idx <= '0;//////
      latched_wdata   <= '0;
      latched_row     <= '0;
      latched_col     <= '0;
      latched_rank    <= '0;
      latched_bg      <= '0;
      latched_bank    <= '0;
      target_bank_idx <= '0;
      read_data_q     <= '0;
      trtw_ctr        <= '0;   
      
      forced_precharge <= 1'b0;
      
      for (int k = 0; k < BANKS_TOTAL; k++) begin
        bank_state[k].open     <= 1'b0;
        bank_state[k].open_row <= '0;
        bank_state[k].trcd_ctr <= '0;
        bank_state[k].tras_ctr <= '0;
        bank_state[k].trp_ctr  <= '0;
        bank_state[k].trc_ctr  <= '0;
        bank_state[k].twtr_ctr <= '0;
        bank_state[k].tras_max_ctr <= '0;
      end

    // Reset row-buffer valid bits for every bank and every column
    for (int k = 0; k < BANKS_TOTAL; k++) begin
    for (int c = 0; c < (1<<COL_W); c++) begin
        rowbuf_valid[k][c] <= 1'b0;
        rowbuf_data[k][c]  <= '0;
    end
    end

      for (int g = 0; g < BANK_GROUPS; g++)  
        bg_ccd_ctr[g] <= '0;

    end else begin

      // ------------------------------------------------------------------
      // Default pulse outputs
      // ------------------------------------------------------------------
      rsp_valid <= 1'b0;
      cmd_valid <= 1'b0;
      cmd_code  <= CMD_NOP;

      // ------------------------------------------------------------------
      // Decrement all per-bank timing counters every cycle  
      // ------------------------------------------------------------------
      for (int k = 0; k < BANKS_TOTAL; k++) begin
        if (bank_state[k].trcd_ctr != 0) bank_state[k].trcd_ctr <= bank_state[k].trcd_ctr - 1;
        if (bank_state[k].tras_ctr != 0) bank_state[k].tras_ctr <= bank_state[k].tras_ctr - 1;
        if (bank_state[k].trp_ctr  != 0) bank_state[k].trp_ctr  <= bank_state[k].trp_ctr  - 1;
        if (bank_state[k].trc_ctr  != 0) bank_state[k].trc_ctr  <= bank_state[k].trc_ctr  - 1;
        if (bank_state[k].twtr_ctr != 0) bank_state[k].twtr_ctr <= bank_state[k].twtr_ctr - 1;
        if (bank_state[k].tras_max_ctr != 0) bank_state[k].tras_max_ctr <= bank_state[k].tras_max_ctr - 1;
      end

      // ------------------------------------------------------------------
      // Decrement per-BG CCD counters  
      // ------------------------------------------------------------------
      for (int g = 0; g < BANK_GROUPS; g++) begin
        if (bg_ccd_ctr[g] != 0) bg_ccd_ctr[g] <= bg_ccd_ctr[g] - 1;
      end

      // ------------------------------------------------------------------
      // Decrement RTW counter  
      // ------------------------------------------------------------------
      if (trtw_ctr != 0) trtw_ctr <= trtw_ctr - 1;

      // ------------------------------------------------------------------
      // Refresh countdown
      // ------------------------------------------------------------------
      if (refresh_ctr != 0) begin
        refresh_ctr <= refresh_ctr - 1;
      end else begin
        refresh_pending <= 1'b1;
      end

      // ------------------------------------------------------------------
      // FSM
      // ------------------------------------------------------------------
      case (state)

        // -----------------------------------------------------------------
        // IDLE
        // -----------------------------------------------------------------

        ST_IDLE: begin
            int forced_idx;
            logic found_forced_pre;

            found_forced_pre = 1'b0;
            forced_idx       = 0;

            // First priority: if any bank has exceeded tRAS_MAX, force it closed
            for (int k = 0; k < BANKS_TOTAL; k++) begin
                if (!found_forced_pre && bank_must_close(k)) begin
                found_forced_pre = 1'b1;
                forced_idx       = k;
                end
            end

            if (refresh_pending) begin
                forced_precharge <= 1'b0;
                state <= ST_REF_ISSUE;
            end else if (found_forced_pre) begin
                // Reuse PRE path machinery, but target the timed-out bank
                forced_precharge <= 1'b1;
                target_bank_idx <= forced_idx[$clog2(BANKS_TOTAL)-1:0];
                latched_rank    <= bank_to_rank(forced_idx);
                latched_bg      <= bank_to_bg(forced_idx);
                latched_bank    <= bank_to_bank(forced_idx);
                state <= ST_PRE_WAIT;
            end else if (req_valid && req_ready) begin
                forced_precharge <= 1'b0;  ////
                latched_write   <= req_write;
                latched_addr    <= req_addr;
                latched_mem_idx <= flatten_mem_index(
                                    get_rank(req_addr),
                                    get_bg(req_addr),
                                    get_bank(req_addr),
                                    get_row(req_addr),
                                    get_col(req_addr)
                                  );
                latched_wdata   <= req_wdata;
                latched_row     <= get_row(req_addr);
                latched_col     <= get_col(req_addr);
                latched_rank    <= get_rank(req_addr);
                latched_bg      <= get_bg(req_addr);
                latched_bank    <= get_bank(req_addr);
                target_bank_idx <= flatten_bank(
                                    get_rank(req_addr),
                                    get_bg(req_addr),
                                    get_bank(req_addr));

                if (row_hit(
                    flatten_bank(get_rank(req_addr), get_bg(req_addr), get_bank(req_addr)),
                    get_row(req_addr)))
                state <= ST_COL_ISSUE;
                else if (bank_state[flatten_bank(
                        get_rank(req_addr), get_bg(req_addr), get_bank(req_addr))].open)
                state <= ST_PRE_WAIT;
                else
                state <= ST_ACT_ISSUE;
            end
            end

        // -----------------------------------------------------------------
        // PRE_WAIT: wait until PRE is legal, then close the conflicting row
        // -----------------------------------------------------------------
        ST_PRE_WAIT: begin
          if (can_precharge(target_bank_idx)) begin
            cmd_valid <= 1'b1;
            cmd_code  <= CMD_PRE;
            cmd_rank  <= latched_rank;
            cmd_bg    <= latched_bg;
            cmd_bank  <= latched_bank;

            for (int c = 0; c < (1<<COL_W); c++) begin
            if (rowbuf_valid[target_bank_idx][c]) begin
                mem_array[flatten_mem_index(
                bank_to_rank(target_bank_idx),
                bank_to_bg(target_bank_idx),
                bank_to_bank(target_bank_idx),
                bank_state[target_bank_idx].open_row,
                c[COL_W-1:0]
                )] <= rowbuf_data[target_bank_idx][c];

                rowbuf_valid[target_bank_idx][c] <= 1'b0;
            end
            end

            bank_state[target_bank_idx].open    <= 1'b0;
            // Load tRP and wait until trp_ctr reaches 0 before allowing next ACT
            bank_state[target_bank_idx].trp_ctr <= 16'(tRP);
            if (forced_precharge) begin
                forced_precharge <= 1'b0;
                state <= ST_IDLE;
                end else begin
                state <= ST_ACT_ISSUE;
                end
          end
        end

        // -----------------------------------------------------------------
        // ACT_ISSUE: issue ACT when bank row-cycle and precharge are done
        // -----------------------------------------------------------------
        ST_ACT_ISSUE: begin
          if (bank_idle_for_act(target_bank_idx)) begin
            cmd_valid <= 1'b1;
            cmd_code  <= CMD_ACT;
            cmd_rank  <= latched_rank;
            cmd_bg    <= latched_bg;
            cmd_bank  <= latched_bank;
            cmd_row   <= latched_row;

            bank_state[target_bank_idx].open     <= 1'b1;
            bank_state[target_bank_idx].open_row <= latched_row;
// Counters are loaded with tXXX and decremented once per cycle.
// The guarded command becomes legal only when the counter reaches 0.
            bank_state[target_bank_idx].trcd_ctr <= 16'(tRCD);
            bank_state[target_bank_idx].tras_ctr <= 16'(tRAS);
            bank_state[target_bank_idx].trc_ctr  <= 16'(tRC);
            bank_state[target_bank_idx].tras_max_ctr <= 16'(tRAS_MAX);
            state <= ST_RCD_WAIT;
          end
        end

        // -----------------------------------------------------------------
        // RCD_WAIT: wait tRCD after ACT before column commands are legal
        // -----------------------------------------------------------------
        ST_RCD_WAIT: begin
          if (bank_state[target_bank_idx].trcd_ctr == 0)
            state <= ST_COL_ISSUE;
        end

        // -----------------------------------------------------------------
        // COL_ISSUE: issue READ or WRITE
        //   READ  → wait CL  cycles (ST_READ_WAIT) then return data
        //   WRITE → wait tCWL cycles (ST_WRITE_WAIT) then commit 
        // -----------------------------------------------------------------
        ST_COL_ISSUE: begin
          if (can_readwrite(target_bank_idx, !latched_write, latched_bg)) begin
            cmd_valid <= 1'b1;
            cmd_code  <= latched_write ? CMD_WRITE : CMD_READ;
            cmd_rank  <= latched_rank;
            cmd_bg    <= latched_bg;
            cmd_bank  <= latched_bank;
            cmd_col   <= latched_col;

            //start the CCD counter for this bank group.
            // All BGs use the same tCCD_L for same-BG and tCCD_S for different
            // BGs. We arm tCCD_L (the stricter) on the issuing BG; the
            // per-BG counter for OTHER BGs is armed with tCCD_S in the
            // second loop below.
            bg_ccd_ctr[latched_bg] <= 16'(tCCD_L);  // 
            for (int g = 0; g < BANK_GROUPS; g++) begin
              if (g != int'(latched_bg))
                // Only tighten if not already counting a stricter value
                if (bg_ccd_ctr[g] < 16'(tCCD_S))
                  bg_ccd_ctr[g] <= 16'(tCCD_S);
            end

            if (latched_write) begin
              //start tCWL wait before committing write data
              wait_ctr <= 16'(tCWL - 1);  // -1 because first decrement in ST_WRITE_WAIT
              state    <= ST_WRITE_WAIT;
            end else begin
              // READ: capture data now, return after CL cycles
              if (bank_state[target_bank_idx].open && bank_state[target_bank_idx].open_row == latched_row && rowbuf_valid[target_bank_idx][latched_col])
              read_data_q <= rowbuf_data[target_bank_idx][latched_col];
            else
              read_data_q <= mem_array[latched_mem_idx];
              wait_ctr    <= 16'(CL - 1);   // CL-1 because ST_READ_WAIT decrements first
              state       <= ST_READ_WAIT;

              // stsrt read→write turnaround counter
              trtw_ctr <= 16'(tRTW);
            end
          end
        end

        // -----------------------------------------------------------------
        // READ_WAIT: count CL cycles then present read data
        // -----------------------------------------------------------------
        ST_READ_WAIT: begin
          if (wait_ctr != 0) begin
            wait_ctr <= wait_ctr - 1;
          end else begin
            rsp_valid <= 1'b1;
            rsp_rdata <= read_data_q;
            state     <= ST_IDLE;
          end
        end

        // -----------------------------------------------------------------
        // WRITE_WAIT: count tCWL cycles then commit write  
        // -----------------------------------------------------------------
      ST_WRITE_WAIT: begin
        if (wait_ctr != 0) begin
          wait_ctr <= wait_ctr - 1;
        end else begin
          // Write-through update:
          // keep latest data in row buffer for row-hit reads,
          // but also immediately update backing store
          rowbuf_data[target_bank_idx][latched_col]  <= latched_wdata;
          rowbuf_valid[target_bank_idx][latched_col] <= 1'b1;

          mem_array[latched_mem_idx] <= latched_wdata;

          bank_state[target_bank_idx].twtr_ctr <= 16'(tWTR);
          state <= ST_IDLE;
        end
      end

        // -----------------------------------------------------------------
        // REF_ISSUE: drain all open banks then issue REF
        // every inline PRE now pulses cmd_valid
        // -----------------------------------------------------------------
        ST_REF_ISSUE: begin
          logic banks_ready;
          banks_ready = 1'b1;   // blocking assign to module-level signal

          for (int k = 0; k < BANKS_TOTAL; k++) begin
            if (bank_state[k].open || (bank_state[k].trp_ctr != 0) || (bank_state[k].tras_ctr != 0))
              banks_ready = 1'b0;
          end

          if (banks_ready) begin
            cmd_valid <= 1'b1;
            cmd_code  <= CMD_REF;
            wait_ctr  <= 16'(tRFC - 1);   // FIX-1
            state     <= ST_REF_WAIT;
          end else begin
            // assert cmd_valid for every PRE issued here
            // only one cmd_valid per cycle is possible; if multiple banks
            // qualify, they are issued on successive cycles (FSM loops back).
            // A production controller would issue them in parallel per-bank.
            for (int k = 0; k < BANKS_TOTAL; k++) begin
              if (bank_state[k].open && (bank_state[k].tras_ctr == 0)) begin
                cmd_valid              <= 1'b1;         // FIX-5
                cmd_code               <= CMD_PRE;       // FIX-5

            for (int c = 0; c < (1<<COL_W); c++) begin
            if (rowbuf_valid[k][c]) begin
                mem_array[flatten_mem_index(
                  bank_to_rank(k),
                  bank_to_bg(k),
                  bank_to_bank(k),
                  bank_state[k].open_row,
                  c[COL_W-1:0]
                )] <= rowbuf_data[k][c];

                rowbuf_valid[k][c] <= 1'b0;
            end
            end

                bank_state[k].open    <= 1'b0;
                bank_state[k].trp_ctr <= 16'(tRP); 
                break;  // issue at most one PRE per cycle 
              end
            end
          end
        end

        // -----------------------------------------------------------------
        // REF_WAIT: wait tRFC then resume normal traffic
        // -----------------------------------------------------------------
        ST_REF_WAIT: begin
          if (wait_ctr != 0) begin
            wait_ctr <= wait_ctr - 1;
          end else begin
            refresh_pending <= 1'b0;
            refresh_ctr     <= 16'd100;
            state           <= ST_IDLE;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
