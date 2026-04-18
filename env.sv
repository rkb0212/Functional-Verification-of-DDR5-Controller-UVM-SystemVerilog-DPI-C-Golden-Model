// =============================================================================
// ENVIRONMENT
// =============================================================================
class ddr5_env extends uvm_env;
  `uvm_component_utils(ddr5_env)

  ddr5_agent      agent;
  ddr5_scoreboard scoreboard;
  ddr5_coverage   coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = ddr5_agent::type_id::create("agent", this);
    scoreboard = ddr5_scoreboard::type_id::create("scoreboard", this);
    coverage   = ddr5_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // scoreboard connections
    agent.req_ap.connect(scoreboard.req_imp);
    agent.rsp_ap.connect(scoreboard.rsp_imp);
    agent.cmd_ap.connect(scoreboard.cmd_imp);

    // coverage connections
    agent.req_ap.connect(coverage.req_imp);
    agent.cmd_ap.connect(coverage.cmd_imp);
  endfunction
endclass
