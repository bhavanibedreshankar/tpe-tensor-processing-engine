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
//
// The _CMD variants (TPE_LOG_CMD_LOW/MEDIUM/HIGH/DEBUG) are for a line about
// one specific in-flight command -- they prefix a "[CMD tag=%0d op=%0s]"
// block so every line touching that command can be grepped/read as one
// thread through the log, e.g.:
//   `TPE_LOG_CMD_MEDIUM("scheduler", cmd_q.tag, cmd_q.opcode, "decode -> STAT_OK")
// Only use these where tag/opcode are actually known to belong to the
// command the line is about (e.g. not before a scheduler has popped/latched
// one) -- see tpe_scheduler.sv for the ST_IDLE/ST_POP carve-out.
`ifndef TPE_VERBOSITY_SVH
`define TPE_VERBOSITY_SVH

// $time here is in units of the compile's time *precision* (this repo
// builds with `--timescale 1ns/1ps`, no module sets its own timescale, and
// nothing calls $timeformat), i.e. picoseconds -- hence the literal "ps"
// suffix rather than leaving the raw integer unitless.
`define TPE_LOG(lvl, name, msg) \
  if (tpe_pkg::tpe_verbosity() >= (lvl)) \
    $display("%0tps [%-6s] %-16s %s", $time, tpe_pkg::tpe_verbosity_name(lvl), name, msg)

`define TPE_LOG_LOW(name, msg)    `TPE_LOG(tpe_pkg::TPE_VERB_LOW,    name, msg)
`define TPE_LOG_MEDIUM(name, msg) `TPE_LOG(tpe_pkg::TPE_VERB_MEDIUM, name, msg)
`define TPE_LOG_HIGH(name, msg)   `TPE_LOG(tpe_pkg::TPE_VERB_HIGH,   name, msg)
`define TPE_LOG_DEBUG(name, msg)  `TPE_LOG(tpe_pkg::TPE_VERB_DEBUG,  name, msg)

// NOTE: the macro parameter is `comp` (component name), not `name` --
// `opcode.name()` below is a *method call*, and `` `define ``'s expansion
// is pure token substitution, so a parameter literally called `name` would
// also rewrite the `name` in `.name()` (e.g. into `.scheduler()`) and break
// the call. Don't rename this back to `name` without renaming the method
// call site too.
`define TPE_LOG_CMD(lvl, comp, tag, opcode, msg) \
  if (tpe_pkg::tpe_verbosity() >= (lvl)) \
    $display("%0tps [%-6s] %-16s [CMD tag=%0d op=%-14s] %s", $time, \
              tpe_pkg::tpe_verbosity_name(lvl), comp, tag, opcode.name(), msg)

`define TPE_LOG_CMD_LOW(comp, tag, opcode, msg)    `TPE_LOG_CMD(tpe_pkg::TPE_VERB_LOW,    comp, tag, opcode, msg)
`define TPE_LOG_CMD_MEDIUM(comp, tag, opcode, msg) `TPE_LOG_CMD(tpe_pkg::TPE_VERB_MEDIUM, comp, tag, opcode, msg)
`define TPE_LOG_CMD_HIGH(comp, tag, opcode, msg)   `TPE_LOG_CMD(tpe_pkg::TPE_VERB_HIGH,   comp, tag, opcode, msg)
`define TPE_LOG_CMD_DEBUG(comp, tag, opcode, msg)  `TPE_LOG_CMD(tpe_pkg::TPE_VERB_DEBUG,  comp, tag, opcode, msg)

`endif
