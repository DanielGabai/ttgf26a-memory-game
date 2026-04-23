/* 6-bit Linear Feedback Shift Register
   Used to generate pseudo-random sequences
   Shifts to the left
   Incoming bit is XOR of bits 5,4
   To generate sequence, watch bits 5,2,0
   */

module lfsr (
    input logic clk,
    input logic rst_n,
    input logic load,
    input logic en,

    input logic [5:0] seed,
    output logic [2:0] r_out
);
logic [5:0] r_store;
always_ff @(posedge clk) begin
    if (!rst_n) begin
        r_store <= 6'd1;
    end else if (load && ~en) begin
        r_store <= (seed == 6'd0) ? (6'd1) : seed;
    end else if (en) begin
        r_store <= { r_store[4:0], (r_store[5] ^ r_store[4]) };
    end
end

assign r_out = {r_store[5], r_store[2], r_store[0]};

endmodule
