// `include "lfsr.sv"
// `include "reg_file.sv"
// `include "decoder.sv"
// `include "reg_file.sv"

/* Top level file for the game
   Contains the game-state FSM 
   
   Input Switch Map:
   0 - MSB of User Input   | MSB of Seed Input | MSB of Delay Input
   1 - User Input          | Seed Input        | Delay Input
   2 - LSB of User Input   | Seed Input        | Delay Input
   3                       | Seed Input        | Delay Input
   4                       | Seed Input        | LSB of Delay Input
   5                       | LSB of Seed Input |
   6 - Submit Answer
   7 - Start / End Game

   Game Loop:
   1) All switches must be low to start, flip 7 high
   2) Enter seed value on switches[0:5], flip 6 high then low
   3) Game starts
   4) Flash a number on the seven seg; Wait for user input

   FSM Rules:
   1) If switch[7] ever goes low, go to reset state
   2) Switch[6] must be flipped high then low to detect input
    - Requires an intermediary state to catch correctly
   3) 
   */

module tt_um_memory_game_top #(
    parameter int DEBOUNCE_CYCLES = 500_000  // ~10ms at 50MHz; override in testbench
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] ui_in,    // Input Switches
    output logic [7:0] uo_out,   // Seven Seg Output

    // Unused IOs
    input  logic [7:0] uio_in,
    output logic [7:0] uio_out,
    output logic [7:0] uio_oe,
    input  logic       ena       // always 1 when design is powered
);

    // Unused
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire _unused = &{ena, uio_in, 1'b0};

    // --- Constants ---
    localparam logic [6:0] SEG_C = 7'b0111001; // Letter C on seven seg
    localparam logic [6:0] SEG_F = 7'b1110001; // Letter F on seven seg
    localparam logic [6:0] SEG_OFF = 7'b0000000; // Seven seg off


    // Synchronized switch inputs
    logic [7:0] ui_in_sync;

    synchronizer #(.WIDTH(8), .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) sw_sync (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (ui_in),
        .sync_out (ui_in_sync)
    );

    // User Inputs
    logic start_btn;
    logic submit_btn;
    logic [5:0] seed_in;
    logic [2:0] user_guess;

    assign start_btn  = ui_in_sync[7];
    assign submit_btn = ui_in_sync[6];
    assign seed_in    = ui_in_sync[5:0];
    assign user_guess = ui_in_sync[2:0];

    // Datapath Routing
    logic submit_pulse;
    logic [2:0] lfsr_val;
    logic [2:0] expected_val;
    logic [6:0] decoder_out;
    logic delay_finish;

    // Pointers & Status
    logic [3:0] index_ptr;
    logic [3:0] round_ptr;
    logic match;
    logic round_done;
    logic mem_full;

    // Control Signals (from FSM)
    logic lfsr_en, lfsr_load;
    logic reg_we;
    logic delay_en, delay_load;
    logic ptr_reset, index_inc, round_inc;
    logic [1:0] seg_mode;

    // --- Datapath Logic (Pointers and Comparators) ---
    
    // Status flag continuous assignments
    assign match      = (user_guess == expected_val);
    assign round_done = (index_ptr == round_ptr);
    assign mem_full   = (index_ptr == 4'd15);

    // Pointer Registers
    always_ff @(posedge clk) begin
        if (!rst_n || start_btn == 1'b0) begin
            index_ptr <= 4'd0;
            round_ptr <= 4'd0;
        end else begin
            if (ptr_reset) 
                index_ptr <= 4'd0;
            else if (index_inc) 
                index_ptr <= index_ptr + 1'b1;
            
            if (round_inc)
                round_ptr <= round_ptr + 1'b1;
        end
    end

    // --- Module Instantiations ---

    edge_detector edge_det (
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(submit_btn),
        .pulse_out(submit_pulse)
    );


    lfsr lfsr (
        .clk(clk),
        .rst_n(rst_n),
        .en(lfsr_en), 
        .load(lfsr_load),
        .seed(seed_in),
        .r_out(lfsr_val)
    );

    reg_file reg_file (
        .clk(clk),
        .we(reg_we),
        .in_reg(lfsr_val),
        .in_sel(index_ptr),     // Write to current index
        .out_sel(index_ptr),    // Read from current index
        .out_reg(expected_val)
    );

    delay delay (
        .clk(clk),
        .rst_n(rst_n),
        .en(delay_en),
        .load_delay(delay_load),
        .ui_in(ui_in_sync),     // Passes synchronized switches to delay loader
        .finish(delay_finish)
    );

    decoder decoder (
        .counter(expected_val),
        .segments(decoder_out)
    );

    game_fsm fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start_btn(start_btn),
        .submit_pulse(submit_pulse),
        .delay_finish(delay_finish),
        .match(match),
        .round_done(round_done),
        .mem_full(mem_full),
        .lfsr_en(lfsr_en),
        .lfsr_load(lfsr_load),
        .reg_we(reg_we),
        .delay_en(delay_en),
        .delay_load(delay_load),
        .ptr_reset(ptr_reset),
        .index_inc(index_inc),
        .round_inc(round_inc),
        .seg_mode(seg_mode)
    );

    // Output routing
    // Decides what shows up on the 7-segment display based on FSM state
    always_comb begin
        case (seg_mode)
            2'b00: uo_out = {1'b0, SEG_OFF}; // Blank screen
            2'b01: uo_out = {1'b0, decoder_out}; // Show numbers from memory
            2'b10: uo_out = {1'b0, SEG_C};       // Show 'C' for correct/win
            2'b11: uo_out = {1'b0, SEG_F};       // Show 'F' for fail
            default: uo_out = 8'b0;
        endcase
    end

endmodule