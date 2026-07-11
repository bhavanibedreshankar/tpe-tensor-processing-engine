// Toolchain smoke-test DUT only. Not part of the TPE architecture.
// Purpose: prove cocotb + pyuvm + Verilator + coverage + waveform dump all
// work together on this machine before any real RTL is written.
module smoke_counter #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             en,
    input  logic             load,
    input  logic [WIDTH-1:0] load_value,
    output logic [WIDTH-1:0] count,
    output logic             overflow
);

  logic [WIDTH-1:0] count_q;
  logic             overflow_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_q    <= '0;
      overflow_q <= 1'b0;
    end else if (load) begin
      count_q    <= load_value;
      overflow_q <= 1'b0;
    end else if (en) begin
      {overflow_q, count_q} <= {1'b0, count_q} + 1'b1;
    end else begin
      // Idle (en=0, load=0): count_q holds by omission above, but
      // overflow_q must be explicitly cleared here -- without this branch
      // it would hold too, letting a wrap's overflow pulse stay asserted
      // across however many idle cycles follow it, violating
      // a_overflow_pulses_once below. Found via tools/regression.py: this
      // toolchain-smoke-only DUT's own driver randomizes en/load every
      // cycle without a fixed seed, so an idle cycle immediately after a
      // wrap wasn't reliably exercised until repeated regression runs hit
      // it. Not part of the TPE architecture proper, so not in
      // docs/verification/bug_list.md's intentional-bug catalog.
      overflow_q <= 1'b0;
    end
  end

  assign count    = count_q;
  assign overflow = overflow_q;

  // Immediate assertion: count must never be X/Z once out of reset.
  always_ff @(posedge clk) begin
    if (rst_n) begin
      a_no_unknown_count: assert (!$isunknown(count_q))
      else $error("smoke_counter: count went to X/Z");
    end
  end

  // Concurrent SVA: overflow pulses exactly one cycle after wrap.
  a_overflow_pulses_once :
  assert property (@(posedge clk) disable iff (!rst_n)
      overflow_q |=> !overflow_q);

  covergroup cg_count @(posedge clk);
    option.per_instance = 1;
    cp_count: coverpoint count_q {
      bins low    = {[0:63]};
      bins mid    = {[64:191]};
      bins high   = {[192:255]};
    }
    cp_overflow: coverpoint overflow_q;
  endgroup

  cg_count cg_count_inst = new();

endmodule
