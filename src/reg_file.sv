/* 16 3-bit registers that can store random game sequence */

module reg_file (
    input logic clk,
    input logic we,
    
    input logic [2:0] in_reg,
    input logic [3:0] in_sel,
    input logic [3:0] out_sel,

    output logic [2:0] out_reg
);

logic [2:0] registers [15:0];

always_ff @(posedge clk) begin
    if (we) begin
        registers[in_sel] <= in_reg;
    end
end

always_comb begin
    out_reg = registers[out_sel];
end

endmodule
