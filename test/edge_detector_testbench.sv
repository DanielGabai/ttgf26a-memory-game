`timescale 1ns / 1ps

module edge_detector_testbench;

    // Parameters
    localparam CLK_PERIOD = 10;  // 100MHz clock (10ns period)

    // DUT Signals
    logic clk;
    logic rst_n;
    logic btn_in;
    logic pulse_out;

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Device Under Test (DUT)
    edge_detector uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .btn_in   (btn_in),
        .pulse_out(pulse_out)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---

    // Reset the DUT (synchronous reset)
    task reset_dut();
        begin
            @(posedge clk);
            rst_n = 0;
            btn_in = 0; // Ensure input is 0 during reset
            repeat (3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
            $display("[%0t] Reset complete", $time);
        end
    endtask

    // Check expected vs actual value
    task check_value(
        input string signal_name,
        input logic [31:0] expected,
        input logic [31:0] actual
    );
        begin
            test_count++;
            if (actual === expected) begin
                pass_count++;
                $display("  PASS: %s = %0d (expected %0d)", signal_name, actual, expected);
            end else begin
                fail_count++;
                $display("  FAIL: %s = %0d (expected %0d)", signal_name, actual, expected);
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
        $dumpfile("logs/edge_detector_testbench.vcd");
        $dumpvars(0, edge_detector_testbench);

        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Initialize signals
        rst_n = 1;
        btn_in = 0;

        $display("");
        $display("========================================");
        $display("  edge_detector Testbench");
        $display("========================================");
        $display("");

        // TEST 1: Reset Verification
        $display("[TEST 1] Reset Verification");
        reset_dut();
        check_value("pulse_out after reset", 0, pulse_out);
        $display("");

        // TEST 2: Basic Functionality
        $display("[TEST 2] Basic Functionality");
        reset_dut();
        
        // Emulate flipping switch high
        btn_in = 1;
        wait_cycles(2);
        check_value("pulse_out on rising edge", 0, pulse_out); // Should be 0, we want falling edge
        
        // Emulate flipping switch low (submit)
        btn_in = 0;
        wait_cycles(1); 
        check_value("pulse_out before active", 0, pulse_out);
        wait_cycles(1); // Takes 2 clocks total to propagate through both flip flops
        check_value("pulse_out active high", 1, pulse_out);
        wait_cycles(1);
        check_value("pulse_out cleared", 0, pulse_out); // Should only last exactly 1 clock cycle
        
        $display("");

        // TEST 3: Edge Cases
        $display("[TEST 3] Edge Cases");
        reset_dut();
        
        // Holding the button high shouldn't cause continuous pulses
        btn_in = 1;
        wait_cycles(5);
        check_value("pulse_out while held high", 0, pulse_out);
        
        // Releasing it triggers one final pulse
        btn_in = 0;
        wait_cycles(2); // Wait for propagation
        check_value("pulse_out on release", 1, pulse_out);
        wait_cycles(5);
        check_value("pulse_out while held low", 0, pulse_out);
        
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
        #10000; // 10us timeout is plenty for this
        $display(" ERROR: Simulation timeout!");
        $finish;
    end

endmodule