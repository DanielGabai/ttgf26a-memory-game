`timescale 1ns / 1ps

module decoder_testbench;

    // Parameters
    localparam CLK_PERIOD = 10;  // 10ns period

    // DUT Signals
    logic       clk;
    logic       rst_n;
    
    // Decoder Specific Signals
    logic [2:0] counter;
    logic [6:0] segments;

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Device Under Test (DUT)
    decoder uut (
        .counter  (counter),
        .segments (segments)
    );

    // Clock Generation (used for pacing the simulation)
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---

    // Reset the DUT (Synchronous style for the flow)
    task reset_dut();
        begin
            @(posedge clk);
            rst_n = 0;
            counter = 3'h0;
            repeat (3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
            $display("[%0t] Reset complete", $time);
        end
    endtask

    // Check expected vs actual value
    task check_value(
        input string signal_name,
        input logic [6:0] expected,
        input logic [6:0] actual
    );
        begin
            test_count++;
            if (actual === expected) begin
                pass_count++;
                $display("  PASS: %s = %7b (expected %7b)", signal_name, actual, expected);
            end else begin
                fail_count++;
                $display("  FAIL: %s = %7b (expected %7b)", signal_name, actual, expected);
            end
        end
    endtask

    // Wait N clock cycles
    task wait_cycles(input integer n);
        repeat (n) @(posedge clk);
    endtask

    // --- Main Test Sequence ---
    initial begin
        // Setup waveform dumping
        $dumpfile("logs/decoder_testbench.vcd");
        $dumpvars(0, decoder_testbench);

        // Initialize variables
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize signals
        rst_n = 1;
        counter = 3'h0;

        $display("");
        $display("========================================");
        $display("  7-Segment Decoder Testbench");
        $display("========================================");
        $display("");

        // TEST 1: Reset/Initial State
        $display("[TEST 1] Initial State (Input 0)");
        reset_dut();
        check_value("segments(0)", 7'b0111111, segments);
        $display("");

        // TEST 2: Basic Functionality (0-9)
        $display("[TEST 2] Basic Functionality (0-9)");
        
        // Manual checks for specific digits
        counter = 3'd1; #1; check_value("segments(1)", 7'b0000110, segments);
        counter = 3'd2; #1; check_value("segments(2)", 7'b1011011, segments);
        counter = 3'd3; #1; check_value("segments(3)", 7'b1001111, segments);
        counter = 3'd4; #1; check_value("segments(4)", 7'b1100110, segments);
        counter = 3'd5; #1; check_value("segments(5)", 7'b1101101, segments);
        counter = 3'd6; #1; check_value("segments(6)", 7'b1111100, segments);
        counter = 3'd7; #1; check_value("segments(7)", 7'b0000111, segments);
        
        $display("");

        // TEST 3: Wraparound (counter is 3-bit, all values 0-7 are explicitly handled)
        $display("[TEST 3] All inputs covered (no invalid cases for 3-bit input)");
        counter = 3'd0; #1; check_value("segments(0) revisit", 7'b0111111, segments);
        $display("");

        // --- Final Summary ---
        $display("");
        $display("========================================");
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

        $display("========================================");
        $display("");

        $finish;
    end

    // Timeout Watchdog
    initial begin
        #1000000;
        $display(" ERROR: Simulation timeout!");
        $finish;
    end

endmodule