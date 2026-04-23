// 2-FF synchronizer + debounce filter for the switch input bus.
// Prevents metastability from asynchronous switch changes,
// then requires DEBOUNCE_CYCLES of stable input before updating output.
//
// At 50 MHz, DEBOUNCE_CYCLES = 500_000 gives ~10ms debounce.
// For simulation/testing, override to a small value (e.g. 4).
module synchronizer #(
    parameter int WIDTH           = 8,
    parameter int DEBOUNCE_CYCLES = 500_000
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] async_in,
    output logic [WIDTH-1:0] sync_out
);

    // Counter width: ceil(log2(DEBOUNCE_CYCLES))
    localparam int CNT_W = $clog2(DEBOUNCE_CYCLES + 1);

    // --- Stage 1: 2-FF metastability synchronizer ---
    logic [WIDTH-1:0] stage1, stage2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            stage1 <= '0;
            stage2 <= '0;
        end else begin
            stage1 <= async_in;
            stage2 <= stage1;
        end
    end

    // --- Stage 2: Debounce filter ---
    // When the synchronized value differs from the accepted output,
    // start counting. If it stays different for DEBOUNCE_CYCLES
    // consecutive cycles, accept it. If it changes back, reset the counter.
    logic [CNT_W-1:0] db_count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sync_out <= '0;
            db_count <= '0;
        end else begin
            if (stage2 != sync_out) begin
                if (db_count == DEBOUNCE_CYCLES[CNT_W-1:0] - 1) begin
                    sync_out <= stage2;
                    db_count <= '0;
                end else begin
                    db_count <= db_count + 1;
                end
            end else begin
                db_count <= '0;
            end
        end
    end

endmodule