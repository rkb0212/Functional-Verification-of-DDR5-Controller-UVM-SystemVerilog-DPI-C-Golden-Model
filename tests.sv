// =============================================================================
// TESTS
// =============================================================================
class ddr5_base_test extends uvm_test;
  `uvm_component_utils(ddr5_base_test)
  ddr5_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = ddr5_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_sequences();
    #500;
    phase.drop_objection(this);
  endtask

  virtual task run_sequences();
  endtask
endclass

class ddr5_regression_test extends ddr5_base_test;
  `uvm_component_utils(ddr5_regression_test)

  function new(string name = "ddr5_regression_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_sequences();
    ddr5_row_hit_seq    s1;
    ddr5_row_miss_seq   s2;
    ddr5_multi_bank_seq s3;
    ddr5_multi_rank_seq s4;
    ddr5_wtr_seq        s5;
    ddr5_rtw_seq        s6;
    ddr5_ccd_seq        s7;
    ddr5_refresh_seq    s8;
    ddr5_stress_seq     s9;
    ddr5_trcd_exact_seq s10;
    ddr5_twtr_exact_seq s11;
    ddr5_trtw_exact_seq s12;
    ddr5_tccd_s_seq     s13;
    ddr5_twtr_later_seq   s14;
    ddr5_trtw_later_seq   s15;
    ddr5_tccd_s_later_seq s16;

    s1 = ddr5_row_hit_seq   ::type_id::create("s1");
    s2 = ddr5_row_miss_seq  ::type_id::create("s2");
    s3 = ddr5_multi_bank_seq::type_id::create("s3");
    s4 = ddr5_multi_rank_seq::type_id::create("s4");
    s5 = ddr5_wtr_seq       ::type_id::create("s5");
    s6 = ddr5_rtw_seq       ::type_id::create("s6");
    s7 = ddr5_ccd_seq       ::type_id::create("s7");
    s8 = ddr5_refresh_seq   ::type_id::create("s8");
    s9 = ddr5_stress_seq    ::type_id::create("s9");
    s9.num_txns = 200;
    s10 = ddr5_trcd_exact_seq::type_id::create("s10");
    s11 = ddr5_twtr_exact_seq::type_id::create("s11");
    s12 = ddr5_trtw_exact_seq::type_id::create("s12");
    s13 = ddr5_tccd_s_seq    ::type_id::create("s13");
    s14 = ddr5_twtr_later_seq  ::type_id::create("s14");
    s15 = ddr5_trtw_later_seq  ::type_id::create("s15");
    s16 = ddr5_tccd_s_later_seq::type_id::create("s16");

    `uvm_info("TEST", "=== FULL REGRESSION START ===", UVM_MEDIUM)
    s1.start(env.agent.sequencer);
    s2.start(env.agent.sequencer);
    s3.start(env.agent.sequencer);
    s4.start(env.agent.sequencer);
    s5.start(env.agent.sequencer);
    s6.start(env.agent.sequencer);
    s7.start(env.agent.sequencer);
    s8.start(env.agent.sequencer);
    s9.start(env.agent.sequencer);
    s10.start(env.agent.sequencer);
    s11.start(env.agent.sequencer);
    s12.start(env.agent.sequencer);
    s13.start(env.agent.sequencer);
    s14.start(env.agent.sequencer);
    s15.start(env.agent.sequencer);
    s16.start(env.agent.sequencer);
    `uvm_info("TEST", "=== FULL REGRESSION COMPLETE ===", UVM_MEDIUM)
  endtask
endclass
