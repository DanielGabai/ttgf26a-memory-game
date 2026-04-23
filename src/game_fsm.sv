module game_fsm (
    input  logic clk,
    input  logic rst_n,
    
    // Inputs from User/Top
    input  logic start_btn,     // ui_in[7]
    input  logic submit_pulse,  // From edge_detector
    
    // Status Inputs from Datapath
    input  logic delay_finish,  
    input  logic match,         
    input  logic round_done,    
    input  logic mem_full,      

    // Control Outputs to Datapath
    output logic lfsr_en,
    output logic lfsr_load,
    output logic reg_we,
    output logic delay_en,
    output logic delay_load,
    output logic ptr_reset,     
    output logic index_inc,     
    output logic round_inc,     
    output logic [1:0] seg_mode 
);

    typedef enum logic [3:0] {
        S_RST,          // 0: Idle, waiting for start_btn
        S_LOAD_SEED,    // 1: Load seed into LFSR
        S_FILL_MEM,     // 2: Auto-fill reg_file with 16 LFSR values
        S_LOAD_DELAY,   // 3: Load delay setting, reset round_ptr
        S_ROUND_START,  // 4: Reset index_ptr to 0 for playback
        S_SHOW_SEQ,     // 5: Display current digit, wait for timer
        S_SEQ_DONE,     // 6: 1-cycle state to drop delay_en to 0
        S_SHOW_GAP,     // 7: Display blank screen, wait for timer
        S_GAP_DONE,     // 8: 1-cycle state to drop delay_en and increment index
        S_WAIT_INPUT,   // 9: Wait for user to flip submit switch
        S_CHECK_INPUT,  // 10: Evaluate guess
        S_WIN,          // 11: Display 'C'
        S_LOSE          // 12: Display 'F'
    } state_t;

    state_t state, next_state;

    // State Register with Global Reset overrides
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= S_RST;
        end else if (!start_btn && state != S_RST) begin
            // Global game reset if switch 7 is flipped low
            state <= S_RST; 
        end else begin
            state <= next_state;
        end
    end

    // Next State & Output Logic
    always_comb begin
        // Default assignments to prevent latches
        next_state = state;
        lfsr_en    = 1'b0;
        lfsr_load  = 1'b0;
        reg_we     = 1'b0;
        delay_en   = 1'b0;
        delay_load = 1'b0;
        ptr_reset  = 1'b0;
        index_inc  = 1'b0;
        round_inc  = 1'b0;
        seg_mode   = 2'b00; // Default blank screen

        case (state)
            S_RST: begin
                ptr_reset = 1'b1;
                if (start_btn) next_state = S_LOAD_SEED;
            end

            S_LOAD_SEED: begin
                lfsr_load = 1'b1;
                next_state = S_FILL_MEM;
            end

            S_FILL_MEM: begin
                lfsr_en = 1'b1;
                reg_we = 1'b1;
                index_inc = 1'b1;
                if (mem_full) next_state = S_LOAD_DELAY;
            end

            S_LOAD_DELAY: begin
                delay_load = 1'b1;
                ptr_reset = 1'b1;
                next_state = S_ROUND_START;
            end

            S_ROUND_START: begin
                ptr_reset = 1'b1;
                next_state = S_SHOW_SEQ;
            end

            S_SHOW_SEQ: begin
                seg_mode = 2'b01; // Show numbers
                delay_en = 1'b1;  // Start timer
                if (delay_finish) next_state = S_SEQ_DONE;
            end

            S_SEQ_DONE: begin
                // delay_en defaults to 0 here, resetting the timer
                seg_mode = 2'b01; // Keep number on screen for this 1 cycle
                if (round_done) begin
                    ptr_reset = 1'b1;
                    next_state = S_WAIT_INPUT;
                end else begin
                    next_state = S_SHOW_GAP;
                end
            end

            S_SHOW_GAP: begin
                seg_mode = 2'b00; // Blank screen
                delay_en = 1'b1;  // Start timer again
                if (delay_finish) next_state = S_GAP_DONE;
            end

            S_GAP_DONE: begin
                // delay_en defaults to 0 here, resetting the timer
                seg_mode = 2'b00;
                index_inc = 1'b1; // Move to the next digit
                next_state = S_SHOW_SEQ;
            end

            S_WAIT_INPUT: begin
                seg_mode = 2'b00; // Blank screen while waiting
                if (submit_pulse) next_state = S_CHECK_INPUT;
            end

            S_CHECK_INPUT: begin
                if (!match) begin
                    next_state = S_LOSE;
                end else begin
                    if (round_done) begin
                        if (mem_full) begin
                            next_state = S_WIN;
                        end else begin
                            round_inc = 1'b1;
                            next_state = S_ROUND_START;
                        end
                    end else begin
                        index_inc = 1'b1;
                        next_state = S_WAIT_INPUT;
                    end
                end
            end

            S_WIN: begin
                seg_mode = 2'b10; // Show 'C'
                // Stays here until start_btn is flipped low, triggering the global reset
            end

            S_LOSE: begin
                seg_mode = 2'b11; // Show 'F'
                // Stays here until start_btn is flipped low, triggering the global reset
            end

            default: next_state = S_RST;
        endcase
    end

endmodule
