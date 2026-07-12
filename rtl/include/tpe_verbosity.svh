// Leveled debug printing for RTL, selected at runtime via `+VERBOSITY=<LEVEL>`
// (default NONE -- silent, no $display output and no behavior/timing change
// versus before this existed). Levels mirror UVM's uvm_verbosity naming
// (UVM_NONE/UVM_LOW/UVM_MEDIUM/UVM_HIGH/UVM_DEBUG) without depending on UVM
// itself -- this repo's RTL sim doesn't use it, see docs/flows/build_flow.md.
// The C++ golden model reads the equivalent TPE_VERBOSITY env var
// (model/include/Verbosity.hpp), so `run_sim -verbosity <LEVEL>` controls
// both design and model with one flag (docs/flows/run_sim_flow.md).
//
// Usage: `include "tpe_verbosity.svh" once per module (after `import
// tpe_pkg::*;`), then e.g.:
//   `TPE_LOG_HIGH("dma", $sformatf("state %0s -> %0s", state_q.name(), state_d.name()))
`ifndef TPE_VERBOSITY_SVH
`define TPE_VERBOSITY_SVH

`define TPE_LOG(lvl, name, msg) \
  if (tpe_pkg::tpe_verbosity() >= (lvl)) \
    $display("%0t [%-6s] %-16s %s", $time, tpe_pkg::tpe_verbosity_name(lvl), name, msg)

`define TPE_LOG_LOW(name, msg)    `TPE_LOG(tpe_pkg::TPE_VERB_LOW,    name, msg)
`define TPE_LOG_MEDIUM(name, msg) `TPE_LOG(tpe_pkg::TPE_VERB_MEDIUM, name, msg)
`define TPE_LOG_HIGH(name, msg)   `TPE_LOG(tpe_pkg::TPE_VERB_HIGH,   name, msg)
`define TPE_LOG_DEBUG(name, msg)  `TPE_LOG(tpe_pkg::TPE_VERB_DEBUG,  name, msg)

`endif
