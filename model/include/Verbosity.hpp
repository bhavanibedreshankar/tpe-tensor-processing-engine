// Leveled debug logging for the golden model, selected once at process
// start via the TPE_VERBOSITY env var -- mirrors the RTL side's
// `+VERBOSITY=<LEVEL>` plusarg (rtl/include/tpe_verbosity.svh) so a single
// LEVEL string, set by `run_sim -verbosity <LEVEL>`, controls both design
// and model (docs/flows/run_sim_flow.md). Names mirror UVM's uvm_verbosity
// without depending on UVM itself. Unset TPE_VERBOSITY behaves exactly like
// before this existed: NONE, no extra output.
#pragma once

#include <cstdlib>
#include <iostream>
#include <string>

namespace tpe::model {

enum class Verbosity { NONE = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DEBUG = 4 };

inline Verbosity verbosity() {
  static const Verbosity level = [] {
    const char* env = std::getenv("TPE_VERBOSITY");
    if (!env) return Verbosity::NONE;
    const std::string s(env);
    if (s == "LOW") return Verbosity::LOW;
    if (s == "MEDIUM") return Verbosity::MEDIUM;
    if (s == "HIGH") return Verbosity::HIGH;
    if (s == "DEBUG") return Verbosity::DEBUG;
    return Verbosity::NONE;
  }();
  return level;
}

inline const char* verbosity_name(Verbosity v) {
  switch (v) {
    case Verbosity::LOW: return "LOW";
    case Verbosity::MEDIUM: return "MEDIUM";
    case Verbosity::HIGH: return "HIGH";
    case Verbosity::DEBUG: return "DEBUG";
    default: return "NONE";
  }
}

}  // namespace tpe::model

// msg may use `<<` chaining, e.g. TPE_LOG(Verbosity::HIGH, "row " << i << " done");
#define TPE_LOG(lvl, msg)                                                        \
  do {                                                                           \
    if (::tpe::model::verbosity() >= (lvl)) {                                   \
      std::cerr << "[" << ::tpe::model::verbosity_name(lvl) << "] " << msg << "\n"; \
    }                                                                            \
  } while (0)
