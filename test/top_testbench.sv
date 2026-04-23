`default_nettype none
`timescale 1ns / 1ps

module top_testbench;

    // Parameters
    localparam CLK_PERIOD  = 10;
    localparam logic [5:0] SEED       = 6'h2B; // Test seed (non-zero)
    localparam logic [4:0] DELAY_BITS = 5'd2;  // adj_delay=2 → counter[2] fires after 4 en-cycles
    // Cycles spent in S_SHOW_SEQ or S_SHOW_GAP before delay fires: 5 (counter latency + 1 FSM cycle)
    localparam DELAY_PHASE = 5 + 1; // show or gap = 5 cycles in state + 1 SEQ_DONE/GAP_DONE cycle

    // Debounce & synchronizer latency
    // DEBOUNCE_CYCLES=1 means "accept after 1 stable cycle" (minimum).
    // Total latency from ui_in change to sync_out change:
    //   2 (sync FFs) + 1 (debounce acceptance) = 3 cycles
    localparam TB_DEBOUNCE = 1;
    localparam SYNC_LATENCY = 3; // 2 sync + TB_DEBOUNCE

    // 7-seg constants (from top.sv)
    localparam logic [6:0] SEG_C   = 7'b0111001;
    localparam logic [6:0] SEG_F   = 7'b1110001;
    localparam logic [6:0] SEG_OFF = 7'b0000000;

    // DUT Signals
    logic        clk;
    logic        rst_n;
    logic [7:0]  ui_in;
    logic [7:0]  uo_out;
    logic [7:0]  uio_in;
    logic [7:0]  uio_out;
    logic [7:0]  uio_oe;
    logic        ena;

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Precomputed LFSR sequence for seed SEED
    logic [2:0] tb_exp [0:15];

    // DUT
    tt_um_memory_game_top #(.DEBOUNCE_CYCLES(TB_DEBOUNCE)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .ui_in   (ui_in),
`ifdef GL_TEST
        ,.VPWR   (VPWR)
        ,.VGND   (VGND)
`endif
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------------------

    // Mirror the LFSR output logic: r_out = {r[5], r[2], r[0]}
    function automatic [2:0] lfsr_out(input logic [5:0] r);
        return {r[5], r[2], r[0]};
    endfunction

    // Mirror the LFSR shift: left-shift with feedback on bit[5]^bit[4]
    function automatic [5:0] lfsr_shift(input logic [5:0] r);
        return {r[4:0], r[5] ^ r[4]};
    endfunction

    // Decoder: 3-bit digit → 7-segment (matches decoder.sv)
    function automatic [6:0] seg_decode(input logic [2:0] val);
        case (val)
            3'd0: return 7'b0111111;
            3'd1: return 7'b0000110;
            3'd2: return 7'b1011011;
            3'd3: return 7'b1001111;
            3'd4: return 7'b1100110;
            3'd5: return 7'b1101101;
            3'd6: return 7'b1111100;
            3'd7: return 7'b0000111;
            default: return 7'b0000000;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------

    task reset_dut();
        @(posedge clk);
        ui_in  <= 8'b0;
        ena    <= 1;
        uio_in <= 8'b0;
        rst_n  <= 0;
        repeat (3) @(posedge clk);
        rst_n  <= 1;
        @(posedge clk);
        $display("[%0t] Reset complete", $time);
    endtask

    task check_value(
        input string       signal_name,
        input logic [31:0] expected,
        input logic [31:0] actual
    );
        test_count++;
        if (actual === expected) begin
            pass_count++;
            $display("  PASS: %s = %0d", signal_name, actual);
        end else begin
            fail_count++;
            $display("  FAIL: %s = %0d (expected %0d)", signal_name, actual, expected);
        end
    endtask

    task wait_cycles(input integer n);
        repeat (n) @(posedge clk);
    endtask

    // Simulate a falling-edge press on the submit button (ui_in[6]).
    // Signal path: ui_in[6] → sync+debounce (SYNC_LATENCY) → edge_detector (2 FFs) → pulse
    // After this task, FSM has latched S_CHECK_INPUT.
    task press_submit();
        @(posedge clk); ui_in[6] <= 1;           // raise submit switch
        wait_cycles(SYNC_LATENCY);                // wait for high to reach submit_btn
        @(posedge clk); ui_in[6] <= 0;            // lower submit switch
        @(posedge clk);                           // edge_detector: current=1, prior=0 (no pulse yet)
        wait_cycles(SYNC_LATENCY - 1);            // wait for low to reach submit_btn
        @(posedge clk);                           // edge_detector: current=0, prior=1 → pulse=1
        @(posedge clk);                           // FSM latches next_state
        @(posedge clk);                           // FSM now in S_CHECK_INPUT
    endtask

    // Run the startup sequence: reset → seed load → fill mem → load delay → S_SHOW_SEQ
    // After this task, the FSM is in S_ROUND_START, about to enter S_SHOW_SEQ.
    task startup();
        reset_dut();
        // Set seed on ui_in[5:0] and assert start_btn
        ui_in <= {1'b1, 1'b0, SEED};     // [7]=start, [6]=submit=0, [5:0]=seed
        wait_cycles(SYNC_LATENCY);         // Wait for sync+debounce propagation
        @(posedge clk);                    // S_RST sees start_btn=1 → next: S_LOAD_SEED
        @(posedge clk);                    // S_LOAD_SEED: lfsr_load latches SEED
        // Now in S_FILL_MEM. Switch delay bits (ui_in[4:0]) before S_LOAD_DELAY latches them.
        // SEED[4:0] = 5'b01011 = 11 which would be far too slow, so override:
        ui_in[4:0] <= DELAY_BITS;          // adj_delay=2 for fast simulation
        wait_cycles(16);                   // 16 S_FILL_MEM cycles (index 0..15 written)
        // Need extra cycles for delay bits to propagate through sync before S_LOAD_DELAY latches
        wait_cycles(SYNC_LATENCY);
        @(posedge clk);                    // S_LOAD_DELAY: latches adj_delay, ptr_reset
        @(posedge clk);                    // S_ROUND_START: ptr_reset
        // FSM now enters S_SHOW_SEQ on the next posedge — delay timer starts there
    endtask

    // Wait through the display phase of one round (show sequence + gaps), ending in S_WAIT_INPUT.
    // round is 0-indexed (round 0 = 1 digit, round 1 = 2 digits, etc.)
    task wait_show_seq(input int round);
        // Display phase:
        //   S_ROUND_START: 1 cycle (already done after startup or CHECK_INPUT→ROUND_START)
        //   For each digit 0..round-1: SHOW_SEQ(5) + SEQ_DONE(1) + SHOW_GAP(5) + GAP_DONE(1) = 12
        //   Last digit: SHOW_SEQ(5) + SEQ_DONE(1) = 6
        //   Total from entering S_SHOW_SEQ (which startup does): 6 + round*12 cycles + 2 margin
        wait_cycles(6 + round * 12 + 2);
    endtask

    // Enter one guess and submit. Sets ui_in[2:0] = val before pressing submit.
    task submit_guess(input logic [2:0] val);
        ui_in[2:0] <= val;
        press_submit();
    endtask

    // Play a full round (show seq + all correct guesses). round is 0-indexed.
    // After this task, FSM has reached S_ROUND_START for round+1 (or S_WIN if last round).
    task play_round_correct(input int round);
        // Display phase
        wait_show_seq(round);
        // Input phase: enter round+1 correct guesses
        for (int i = 0; i <= round; i++) begin
            submit_guess(tb_exp[i]);
            @(posedge clk);  // FSM executes S_CHECK_INPUT → WAIT_INPUT or ROUND_START/WIN
        end
    endtask

    // -------------------------------------------------------------------------
    // Precompute LFSR Sequence
    // -------------------------------------------------------------------------
    // Mirrors what S_FILL_MEM does:
    //   - At each posedge in S_FILL_MEM: reg[i] = current r_out, then r_store shifts.
    //   - r_store is loaded from SEED at S_LOAD_SEED.
    initial begin
        logic [5:0] r;
        r = SEED; // seed=0 would be replaced by 1 in lfsr.sv, but SEED=0x2B ≠ 0
        for (int i = 0; i < 16; i++) begin
            tb_exp[i] = lfsr_out(r);
            r = lfsr_shift(r);
        end
        $display("[TB] Precomputed sequence: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
            tb_exp[0],  tb_exp[1],  tb_exp[2],  tb_exp[3],
            tb_exp[4],  tb_exp[5],  tb_exp[6],  tb_exp[7],
            tb_exp[8],  tb_exp[9],  tb_exp[10], tb_exp[11],
            tb_exp[12], tb_exp[13], tb_exp[14], tb_exp[15]);
    end

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("../logs/top_testbench.vcd");
        $dumpvars(0, top_testbench);

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("\n========================================");
        $display("  tt_um_memory_game_top Testbench");
        $display("========================================\n");

        // -----------------------------------------------------------------
        $display("[TEST 1] Reset and Idle State");
        // -----------------------------------------------------------------
        reset_dut();
        // After reset, start_btn=0 → FSM in S_RST → seg_mode=0 → uo_out=0
        check_value("uo_out after reset (blank)", 0, uo_out);
        // Raise rst_n with start_btn still low → stays in S_RST
        wait_cycles(2);
        check_value("uo_out idle (no start, still blank)", 0, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 2] Startup Sequence (LOAD_SEED → FILL_MEM → LOAD_DELAY)");
        // -----------------------------------------------------------------
        startup();
        // After startup(), FSM enters S_SHOW_SEQ on the next posedge.
        // In S_SHOW_SEQ, seg_mode=01, so uo_out = {1'b0, decoder(tb_exp[0])}.
        wait_cycles(1); // enter S_SHOW_SEQ
        check_value("uo_out shows digit 0 (seg_mode=01)",
                    {1'b0, seg_decode(tb_exp[0])},
                    uo_out);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 3] Round 0 — Correct Guess");
        // -----------------------------------------------------------------
        // Already in S_SHOW_SEQ after Test 2. Wait for sequence display to complete.
        wait_show_seq(0);
        // Should now be in S_WAIT_INPUT (blank screen)
        check_value("uo_out blank during S_WAIT_INPUT", 0, uo_out[6:0]);
        // Submit correct answer
        submit_guess(tb_exp[0]);
        @(posedge clk);  // S_CHECK_INPUT executes: match=1, round_done=1 → round_inc, S_ROUND_START
        // Should now be in S_ROUND_START (blank) heading to Round 1
        check_value("uo_out after correct guess (blank S_ROUND_START)", 0, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 4] Round 1 — Gap Between Digits Visible");
        // -----------------------------------------------------------------
        // Coming from S_ROUND_START (Round 1, round_ptr=1).
        wait_cycles(1); // S_ROUND_START → S_SHOW_SEQ
        // In S_SHOW_SEQ showing digit 0
        check_value("uo_out shows digit 0 in round 1",
                    {1'b0, seg_decode(tb_exp[0])},
                    uo_out);
        // Wait for SHOW_SEQ to finish and GAP to appear
        wait_cycles(DELAY_PHASE); // past delay_finish → S_SEQ_DONE
        @(posedge clk);           // S_SHOW_GAP: blank
        check_value("uo_out blank during S_SHOW_GAP", 0, uo_out[6:0]);
        // Wait through gap, then digit 1 appears
        wait_cycles(DELAY_PHASE);
        @(posedge clk); // S_GAP_DONE → S_SHOW_SEQ
        @(posedge clk); // now in S_SHOW_SEQ showing digit 1
        check_value("uo_out shows digit 1 in round 1",
                    {1'b0, seg_decode(tb_exp[1])},
                    uo_out);
        // Wait for round 1 display to fully complete → S_WAIT_INPUT
        wait_show_seq(1);
        check_value("uo_out blank during S_WAIT_INPUT round 1", 0, uo_out[6:0]);
        // Enter both correct guesses
        submit_guess(tb_exp[0]);
        @(posedge clk);  // S_CHECK_INPUT: match=1, round_done=0 → index_inc, S_WAIT_INPUT
        submit_guess(tb_exp[1]);
        @(posedge clk);  // S_CHECK_INPUT: match=1, round_done=1 → round_inc, S_ROUND_START
        check_value("uo_out after round 1 complete (blank)", 0, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 5] Wrong Guess → LOSE ('F' display)");
        // -----------------------------------------------------------------
        // Currently heading into Round 2 display. Wait for it then give wrong answer on last digit.
        wait_cycles(1);          // S_ROUND_START → S_SHOW_SEQ
        wait_show_seq(2);        // wait through 3-digit display
        // In S_WAIT_INPUT for round 2 (3 digits needed: index 0, 1, 2)
        submit_guess(tb_exp[0]); // correct
        @(posedge clk);          // CHECK → WAIT (index_inc)
        submit_guess(tb_exp[1]); // correct
        @(posedge clk);          // CHECK → WAIT (index_inc)
        // Deliberate wrong answer on digit 2
        begin
            logic [2:0] wrong;
            wrong = (tb_exp[2] == 3'd7) ? 3'd0 : (tb_exp[2] + 3'd1);
            submit_guess(wrong);
        end
        @(posedge clk);          // CHECK_INPUT: match=0 → S_LOSE
        check_value("uo_out[6:0] shows 'F' on lose", SEG_F, uo_out[6:0]);
        // Verify display stays locked
        wait_cycles(5);
        check_value("uo_out[6:0] still 'F' (locked)", SEG_F, uo_out[6:0]);
        // Submit has no effect in LOSE state
        press_submit();
        check_value("uo_out[6:0] 'F' after spurious submit", SEG_F, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 6] Global Reset from LOSE State");
        // -----------------------------------------------------------------
        ui_in[7] <= 0;  // pull start_btn low → global reset
        wait_cycles(SYNC_LATENCY);        // sync+debounce propagation
        @(posedge clk);                   // FSM sees !start_btn → S_RST
        @(posedge clk);                   // outputs settle
        check_value("uo_out blank after global reset", 0, uo_out[6:0]);
        // Confirm it stays blank without start_btn
        wait_cycles(3);
        check_value("uo_out still blank (S_RST, no start)", 0, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 7] seg_mode Routing — WIN ('C' display)");
        // -----------------------------------------------------------------
        // Re-run startup and play all 16 rounds correctly to reach S_WIN.
        startup();
        for (int r = 0; r < 16; r++) begin
            wait_cycles(1);  // S_ROUND_START → S_SHOW_SEQ
            wait_show_seq(r);
            for (int i = 0; i <= r; i++) begin
                submit_guess(tb_exp[i]);
                @(posedge clk);
            end
        end
        // After round 15 correct: mem_full=1, round_done=1, match=1 → S_WIN
        check_value("uo_out[6:0] shows 'C' on win", SEG_C, uo_out[6:0]);
        wait_cycles(5);
        check_value("uo_out[6:0] still 'C' (locked)", SEG_C, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 8] Global Reset from WIN State");
        // -----------------------------------------------------------------
        ui_in[7] <= 0;
        wait_cycles(SYNC_LATENCY);        // sync+debounce propagation
        @(posedge clk);                   // FSM → S_RST
        @(posedge clk);                   // outputs settle
        check_value("uo_out blank after reset from WIN", 0, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 9] Global Reset Mid-Sequence (S_SHOW_SEQ)");
        // -----------------------------------------------------------------
        startup();
        wait_cycles(2); // into S_SHOW_SEQ showing digit 0
        check_value("uo_out shows digit before reset",
                    {1'b0, seg_decode(tb_exp[0])},
                    uo_out);
        // Pull start_btn low mid-display
        ui_in[7] <= 0;
        wait_cycles(SYNC_LATENCY);        // sync+debounce propagation
        @(posedge clk);                   // FSM → S_RST
        @(posedge clk);                   // outputs settle
        check_value("uo_out blank immediately after mid-game reset", 0, uo_out[6:0]);
        $display("");

        // -----------------------------------------------------------------
        $display("[TEST 10] Correct Re-entry After Reset");
        // -----------------------------------------------------------------
        // Re-run full startup from the reset just done
        startup();
        wait_cycles(2); // into S_SHOW_SEQ
        check_value("uo_out shows digit 0 after re-entry",
                    {1'b0, seg_decode(tb_exp[0])},
                    uo_out);
        wait_show_seq(0);
        submit_guess(tb_exp[0]);
        @(posedge clk);
        check_value("uo_out blank after correct re-entry guess", 0, uo_out[6:0]);
        $display("");

        // --- Final Summary ---
        $display("\n========================================");
        $display("  Test Summary");
        $display("----------------------------------------");
        $display("  Total Tests: %3d", test_count);
        $display("  Passed:      %3d", pass_count);
        $display("  Failed:      %3d", fail_count);
        $display("----------------------------------------");
        if (fail_count == 0)
            $display("  Result:  ALL TESTS PASSED");
        else
            $display("  Result:  SOME TESTS FAILED");
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog — increase if running full WIN test (TEST 7) is slow
    initial begin
        #50_000_000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule