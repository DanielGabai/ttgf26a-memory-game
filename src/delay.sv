module delay (
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic [7:0] ui_in, // switch input, uses switches 0-4
    input logic load_delay,

    output logic finish
);

    logic [2:0] _unused = ui_in[7:5];

    logic [31:0] counter;
    logic [4:0] adj_delay;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            counter <= '0;
            adj_delay <= '0;
        end else begin
            
            if (load_delay) begin
                adj_delay <= ui_in[4:0];
            end

            // 2. Auto-resetting counter
            if (en) begin
                if (!finish) begin
                    counter <= counter + 1'b1;
                end
            end else begin
                counter <= '0; // Clears the timer when the FSM drops 'en'
            end
            
        end
    end

    always_comb begin
        finish = counter[adj_delay];
    end

endmodule
