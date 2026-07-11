// Parametrized round-robin arbiter. One-hot request in, one-hot grant out.
// Priority pointer advances to (granted + 1) on each accepted grant so no
// requester can starve a lower-priority peer indefinitely. Pure
// synthesizable RTL; protocol checks live in verif/sva/common_sva.sv.
module round_robin_arb #(
    parameter int NUM_REQ = 4
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [NUM_REQ-1:0]    req,
    input  logic                  grant_accept,  // downstream consumed the grant this cycle

    output logic [NUM_REQ-1:0]    grant,
    output logic                  grant_valid,
    output logic [$clog2(NUM_REQ)-1:0] grant_idx
);

  localparam int IdxW = $clog2(NUM_REQ);

  logic [IdxW-1:0] base_ptr;
  logic [2*NUM_REQ-1:0] req_dbl;
  logic [IdxW-1:0] win_idx;
  logic             any_req;

  always_comb begin
    req_dbl = {req, req};
    any_req = |req;
    win_idx = '0;

    // Scan starting at base_ptr, first requester found wins.
    for (int unsigned i = 0; i < NUM_REQ; i++) begin
      automatic int unsigned scan_pos = {{(32 - IdxW) {1'b0}}, base_ptr} + i;
      if (req_dbl[scan_pos]) begin
        win_idx = IdxW'(scan_pos % NUM_REQ);
        break;
      end
    end
  end

  assign grant_valid = any_req;
  assign grant_idx    = win_idx;

  always_comb begin
    grant = '0;
    if (any_req) begin
      grant[win_idx] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      base_ptr <= '0;
    end else if (grant_valid && grant_accept) begin
      base_ptr <= (win_idx == IdxW'(NUM_REQ - 1)) ? '0 : win_idx + 1'b1;
    end
  end

endmodule
