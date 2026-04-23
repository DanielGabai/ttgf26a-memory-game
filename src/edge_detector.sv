/* Edge detector module used for processing switch inputs
   Detects the falling edge
*/

module edge_detector (
    input logic clk,
    input logic rst_n,
    input logic btn_in,
    output logic pulse_out
);

logic current, prior;

always_ff @( posedge clk ) begin
    if (!rst_n) begin
        current <= 1'b0;
        prior <= 1'b0;
    end else begin
        current <= btn_in;
        prior <= current;
    end
end

assign pulse_out = ~current & prior;

endmodule
