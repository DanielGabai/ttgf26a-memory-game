`timescale 1ns / 1ps

module game_fsm_testbench;

    // Parameters
    localparam CLK_PERIOD = 10;

    // DUT Signals
    logic       clk;
    logic       rst_n;
    
    logic       start_btn;
    logic       submit_pulse;
    logic       delay_finish;
    logic       match;
    logic       round_done;
    logic       mem_full;

    logic       lfsr_en;
    logic       lfsr_load;
    logic       reg_we;
    logic       delay_en;
    logic       delay_load;
    logic       ptr_reset;
    logic       index_inc;
    logic       round_inc;
    logic [1:0] seg_mode;

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Device Under Test (DUT)
    game_fsm uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_btn    (start_btn),
        .submit_pulse (submit_pulse),
        .delay_finish (delay_finish),
        .match        (match),
        .round_done   (round_done),
        .mem_full     (mem_full),
        .lfsr_en      (lfsr_en),
        .lfsr_load    (lfsr_load),
        .reg_we       (reg_we),
        .delay_en     (delay_en),
        .delay_load   (delay_load),
        .ptr_reset    (ptr_reset),
        .index_inc    (index_inc),
        .round_inc    (round_inc),
        .seg_mode     (seg_mode)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---
    task reset_dut();
        begin
            @(posedge clk);
            start_btn    <= 0;
            submit_pulse <= 0;
            delay_finish <= 0;
            match        <= 0;
            round_done   <= 0;
            mem_full     <= 0;
            rst_n        <= 0;
            repeat (3) @(posedge clk);
            rst_n        <= 1;
            @(posedge clk);
            $display("[%0t] Reset complete", $time);
        end
    endtask

    task check_value(
        input string signal_name,
        input logic [31:0] expected,
        input logic [31:0] actual
    );
        begin
            test_count++;
            if (actual === expected) begin
                pass_count++;
                $display("  PASS: %s = %0d", signal_name, actual);
            end else begin
                fail_count++;
                $display("  FAIL: %s = %0d (expected %0d)", signal_name, actual, expected);
            end
        end
    endtask

    task wait_cycles(input integer n);
        repeat (n) @(posedge clk);
        #1; // Wait for non-blocking assignments to commit before sampling outputs
    endtask

    // --- Main Test Sequence ---
    initial begin
        $dumpfile("logs/game_fsm_testbench.vcd");
        $dumpvars(0, game_fsm_testbench);

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("\n========================================");
        $display("  game_fsm Testbench");
        $display("========================================\n");

        // ---------------------------------------------------------
        $display("[TEST 1] Idle & Reset Behavior");
        // ---------------------------------------------------------
        reset_dut();
        check_value("ptr_reset (S_RST)", 1, ptr_reset);
        check_value("seg_mode (Blank)", 0, seg_mode);
        $display("");

        // ---------------------------------------------------------
        $display("[TEST 2] Initialization Sequence");
        // ---------------------------------------------------------
        start_btn <= 1; // Flip switch 7 HIGH
        wait_cycles(1); 
        // Now in S_LOAD_SEED
        check_value("lfsr_load", 1, lfsr_load);
        
        wait_cycles(1);
        // Now in S_FILL_MEM
        check_value("lfsr_en", 1, lfsr_en);
        check_value("reg_we", 1, reg_we);
        check_value("index_inc", 1, index_inc);
        
        wait_cycles(3); // Let it loop a few times
        mem_full <= 1;  // Top file signals memory is completely full
        wait_cycles(1); 
        // Now in S_LOAD_DELAY
        mem_full <= 0;
        check_value("delay_load", 1, delay_load);
        check_value("ptr_reset", 1, ptr_reset);
        $display("");

        // ---------------------------------------------------------
        $display("[TEST 3] Round 0 Gameplay (Display & Guess)");
        // ---------------------------------------------------------
        wait_cycles(1); 
        // Now in S_ROUND_START
        check_value("ptr_reset (Round Start)", 1, ptr_reset);
        
        wait_cycles(1);
        // Now in S_SHOW_SEQ
        check_value("seg_mode (Show Num)", 1, seg_mode);
        check_value("delay_en (Running)", 1, delay_en);
        
        delay_finish <= 1; // Timer ends
        wait_cycles(1);
        // Now in S_SEQ_DONE
        delay_finish <= 0;
        round_done <= 1;   // Datapath says we only show 1 digit this round
        #1; // Let round_done NBA commit before sampling ptr_reset
        check_value("delay_en (Dropped to reset timer)", 0, delay_en);
        check_value("ptr_reset (Prep for input)", 1, ptr_reset);
        
        wait_cycles(1);
        // Now in S_WAIT_INPUT
        check_value("seg_mode (Blank for input)", 0, seg_mode);
        
        // User guesses correctly
        match <= 1;
        submit_pulse <= 1;
        wait_cycles(1);
        // Now in S_CHECK_INPUT
        submit_pulse <= 0;
        check_value("round_inc (Round Beaten!)", 1, round_inc);
        $display("");

        // ---------------------------------------------------------
        $display("[TEST 4] Round 1 Gameplay (Visual Gap & Multi-digit)");
        // ---------------------------------------------------------
        wait_cycles(1);
        // Back to S_ROUND_START
        wait_cycles(1);
        // Now in S_SHOW_SEQ (Digit 1)
        delay_finish <= 1;
        wait_cycles(1);
        // Now in S_SEQ_DONE
        delay_finish <= 0;
        round_done <= 0; // NOT done yet, need to show 2 digits this round
        
        wait_cycles(1);
        // Now in S_SHOW_GAP
        check_value("seg_mode (Blank for gap)", 0, seg_mode);
        check_value("delay_en (Running gap timer)", 1, delay_en);
        
        delay_finish <= 1;
        wait_cycles(1);
        // Now in S_GAP_DONE
        delay_finish <= 0;
        check_value("index_inc (Move to digit 2)", 1, index_inc);
        
        wait_cycles(1);
        // Now in S_SHOW_SEQ (Digit 2)
        delay_finish <= 1;
        wait_cycles(1);
        // Now in S_SEQ_DONE
        delay_finish <= 0;
        round_done <= 1; // Now we are done showing
        wait_cycles(1);
        // Now in S_WAIT_INPUT
        
        // User guesses digit 1 correctly
        match <= 1;
        submit_pulse <= 1;
        round_done <= 0; // Datapath: ptr is 0, round is 1
        wait_cycles(1);
        // Now in S_CHECK_INPUT
        submit_pulse <= 0;
        check_value("index_inc (Next guess)", 1, index_inc);
        check_value("round_inc (Should be 0)", 0, round_inc);
        $display("");

        // ---------------------------------------------------------
        $display("[TEST 5] Lose Condition Lockout");
        // ---------------------------------------------------------
        wait_cycles(1);
        // Back in S_WAIT_INPUT for digit 2
        match <= 0; // USER GUESSES WRONG
        submit_pulse <= 1;
        wait_cycles(1);
        // Now in S_CHECK_INPUT
        submit_pulse <= 0;
        
        wait_cycles(1);
        // Now in S_LOSE
        check_value("seg_mode (Show F)", 3, seg_mode); // 2'b11 = 3
        
        // Ensure it stays locked
        wait_cycles(5);
        check_value("seg_mode (Still F)", 3, seg_mode);
        $display("");

        // ---------------------------------------------------------
        $display("[TEST 6] Global Reset (Switch 7 flipped low)");
        // ---------------------------------------------------------
        start_btn <= 0; // User flips switch down
        wait_cycles(2);
        check_value("seg_mode (Blank - Reset)", 0, seg_mode);
        check_value("ptr_reset (Held in reset)", 1, ptr_reset);
        $display("");

        // ---------------------------------------------------------
        $display("[TEST 7] Win Condition Lockout");
        // ---------------------------------------------------------
        // Fast forward to input check
        start_btn <= 1;
        wait_cycles(1); // LOAD_SEED
        wait_cycles(1); // FILL_MEM
        mem_full <= 1;
        wait_cycles(1); // LOAD_DELAY
        mem_full <= 0;
        wait_cycles(1); // ROUND_START
        wait_cycles(1); // SHOW_SEQ
        delay_finish <= 1;
        wait_cycles(1); // SEQ_DONE
        delay_finish <= 0;
        round_done <= 1;
        wait_cycles(1); // WAIT_INPUT
        
        // Emulate beating round 15
        match <= 1;
        round_done <= 1;
        mem_full <= 1; 
        submit_pulse <= 1;
        wait_cycles(1);
        // CHECK_INPUT
        submit_pulse <= 0;
        
        wait_cycles(1);
        // Now in S_WIN
        check_value("seg_mode (Show C)", 2, seg_mode); // 2'b10 = 2
        
        wait_cycles(5);
        check_value("seg_mode (Still C)", 2, seg_mode);
        $display("");


        // --- Final Summary ---
        $display("\n========================================");
        $display("  Test Summary");
        $display("----------------------------------------");
        $display("  Total Tests: %3d", test_count);
        $display("  Passed:      %3d", pass_count);
        $display("  Failed:      %3d", fail_count);
        $display("----------------------------------------");

        if (fail_count == 0) begin
            $display("  Result:  ALL TESTS PASSED");
        end else begin
            $display("  Result:  SOME TESTS FAILED");
        end
        $display("========================================\n");

        $finish;
    end

    // Timeout Watchdog
    initial begin
        #100000;
        $display(" ERROR: Simulation timeout!");
        $finish;
    end

endmodule