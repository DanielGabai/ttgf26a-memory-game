`timescale 1ns / 1ps
// Do not use special symbols in testing
module synchronizer_testbench;

    // Parameters
    localparam CLK_PERIOD = 10;  // 100MHz clock (10ns period)
    localparam WIDTH = 8;

    // DUT Signals
    logic             clk;
    logic             rst_n;
    logic [WIDTH-1:0] async_in;
    logic [WIDTH-1:0] sync_out;

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Device Under Test (DUT)
    synchronizer #(.WIDTH(WIDTH), .DEBOUNCE_CYCLES(1)) uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .async_in (async_in),
        .sync_out (sync_out)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---

    // Reset the DUT
    task reset_dut();
        begin
            @(posedge clk);
            rst_n    = 0;
            async_in = '0;
            repeat (3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
            @(negedge clk);  // Settle past NBA region before returning
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
                $display("  PASS: %s = 0x%0h (expected 0x%0h)", signal_name, actual, expected);
            end else begin
                fail_count++;
                $display("  FAIL: %s = 0x%0h (expected 0x%0h)", signal_name, actual, expected);
            end
        end
    endtask

    // Wait N clock cycles
    task wait_cycles(input integer n);
        repeat (n) @(posedge clk);
        @(negedge clk);  // Settle past NBA region before caller reads outputs
    endtask

    // --- Main Test Sequence ---
    initial begin
        // Setup waveform dumping
        $dumpfile("logs/synchronizer_testbench.vcd");
        $dumpvars(0, synchronizer_testbench);

        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        rst_n    = 1;
        async_in = '0;

        $display("");
        $display("========================================");
        $display("  Synchronizer Testbench");
        $display("========================================");
        $display("");

        // TEST 1: Reset Verification
        // Both pipeline stages should clear to 0 on reset
        $display("[TEST 1] Reset Verification");
        async_in = 8'hFF;          // Drive non-zero before reset
        reset_dut();
        check_value("sync_out after reset", 32'd0, 32'(sync_out));
        $display("");

        // TEST 2: Three-cycle propagation delay
        // A new value must pass through 2 sync FFs + 1 debounce cycle
        $display("[TEST 2] Three-cycle propagation delay");
        reset_dut();
        async_in = 8'hA5;
        @(posedge clk); @(negedge clk);  // Cycle 1: async_in -> stage1
        check_value("sync_out after 1 cycle (should still be 0)", 32'd0, 32'(sync_out));
        @(posedge clk); @(negedge clk);  // Cycle 2: stage1 -> stage2
        check_value("sync_out after 2 cycles (should still be 0)", 32'd0, 32'(sync_out));
        @(posedge clk); @(negedge clk);  // Cycle 3: debounce accepts → sync_out
        check_value("sync_out after 3 cycles", 32'h000000A5, 32'(sync_out));
        $display("");

        // TEST 3: Input change propagates after three cycles
        $display("[TEST 3] Input change propagates correctly");
        reset_dut();
        async_in = 8'hFF;
        wait_cycles(3);
        check_value("sync_out stable at 0xFF", 32'h000000FF, 32'(sync_out));

        async_in = 8'h00;          // Change input back to 0
        @(posedge clk); @(negedge clk);
        check_value("sync_out still 0xFF after 1 cycle", 32'h000000FF, 32'(sync_out));
        @(posedge clk); @(negedge clk);
        check_value("sync_out still 0xFF after 2 cycles", 32'h000000FF, 32'(sync_out));
        @(posedge clk); @(negedge clk);
        check_value("sync_out now 0x00 after 3 cycles", 32'd0, 32'(sync_out));
        $display("");

        // TEST 4: Active-low reset overrides input mid-stream
        $display("[TEST 4] Reset mid-stream clears output");
        reset_dut();
        async_in = 8'hC3;
        wait_cycles(3);
        check_value("sync_out stable at 0xC3", 32'h000000C3, 32'(sync_out));

        rst_n = 0;                 // Assert reset while data is flowing
        @(posedge clk); @(negedge clk);
        check_value("sync_out cleared by reset", 32'd0, 32'(sync_out));
        rst_n = 1;
        $display("");

        // TEST 5: All-ones and all-zeros pass through correctly
        $display("[TEST 5] All-ones and all-zeros");
        reset_dut();

        async_in = 8'hFF;
        wait_cycles(3);
        check_value("sync_out all-ones", 32'h000000FF, 32'(sync_out));

        async_in = 8'h00;
        wait_cycles(3);
        check_value("sync_out all-zeros", 32'd0, 32'(sync_out));
        $display("");

        // TEST 6: Rapid toggle settles correctly
        // Simulates a bouncing switch; only the value held at capture time matters
        $display("[TEST 6] Rapid toggle settles correctly");
        reset_dut();
        async_in = 8'hAA;
        #1; async_in = 8'h55;     // Toggle before first clock edge
        #1; async_in = 8'hAA;
        #1; async_in = 8'h7F;     // Settle on this value before posedge
        wait_cycles(3);
        check_value("sync_out settles to 0x7F", 32'h0000007F, 32'(sync_out));
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
        #1000000;  // 1ms timeout
        $display(" ERROR: Simulation timeout!");
        $finish;
    end

endmodule