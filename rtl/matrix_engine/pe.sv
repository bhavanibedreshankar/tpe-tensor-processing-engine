// Systolic Processing Element (one MAC) -- the fundamental unit of
// rtl/matrix_engine/mac_array.sv. Weight-stationary: the weight is loaded
// once (weight_load) and held for the whole tile; activations stream east
// (a_in -> a_out, one cycle of pipeline delay) and partial sums stream
// south (acc_in -> acc_out, one cycle of pipeline delay), each PE adding
// its own a_in*weight contribution as the sum passes through.
//
// Timing note (see mac_array.sv and matrix_engine_ctrl.sv for the full
// derivation): for PE[r][c]'s acc_out to correctly sum contributions from
// all rows 0..r for the same (m, c), the controller must inject row r's
// activation for a given m exactly r cycles later than row 0's -- this PE
// itself has no notion of "which row it is", the caller is responsible for
// that skew.
module pe #(
    parameter int OPERAND_WIDTH = 8,
    parameter int ACCUM_WIDTH   = 32
) (
    input logic clk,
    input logic rst_n,

    input logic                          weight_load,
    input logic signed [OPERAND_WIDTH-1:0] weight_in,

    input logic                            valid_in,
    input logic signed [OPERAND_WIDTH-1:0] a_in,
    input logic signed [ACCUM_WIDTH-1:0]   acc_in,
    input logic                            ovf_in,

    output logic                            valid_out,
    output logic signed [OPERAND_WIDTH-1:0] a_out,
    output logic signed [ACCUM_WIDTH-1:0]   acc_out,
    output logic                            ovf_out
);

  localparam logic signed [ACCUM_WIDTH-1:0] AccumMax = {1'b0, {(ACCUM_WIDTH - 1) {1'b1}}};
  localparam logic signed [ACCUM_WIDTH-1:0] AccumMin = {1'b1, {(ACCUM_WIDTH - 1) {1'b0}}};

  logic signed [OPERAND_WIDTH-1:0] weight_reg;
  logic signed [ACCUM_WIDTH-1:0] product;
  logic signed [ACCUM_WIDTH-1:0] sum;
  logic signed [ACCUM_WIDTH-1:0] sum_saturated;
  logic this_add_overflows;

  assign sum = acc_in + product;
  // Signed-add overflow: operands share a sign but the result doesn't.
  assign this_add_overflows = (acc_in[ACCUM_WIDTH-1] == product[ACCUM_WIDTH-1]) &&
                               (sum[ACCUM_WIDTH-1] != acc_in[ACCUM_WIDTH-1]);
  // On overflow, clamp rather than silently wrap: the shared operand sign
  // tells us which rail to saturate to.
  assign sum_saturated = !this_add_overflows ? sum : (acc_in[ACCUM_WIDTH-1] ? sum : AccumMax);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_reg <= '0;
    end else if (weight_load) begin
      weight_reg <= weight_in;
    end
  end

  // OPERAND_WIDTH=8 x OPERAND_WIDTH=8 -> 16-bit product, comfortably within
  // the 32-bit accumulator with headroom for K-deep sums (see
  // docs/architecture/tpe_architecture_spec.md section 2).
  assign product = $signed(a_in) * $signed(weight_reg);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_out     <= '0;
      acc_out   <= '0;
      valid_out <= 1'b0;
      ovf_out   <= 1'b0;
    end else begin
      a_out     <= a_in;
      acc_out   <= sum_saturated;
      valid_out <= valid_in;
      // Sticky within this pass: once set (by this PE or a north
      // neighbor), stays set as the partial sum continues south.
      ovf_out   <= ovf_in || this_add_overflows;
    end
  end

endmodule
