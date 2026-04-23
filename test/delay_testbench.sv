`timescale 1ns / 1ps

module delay_testbench;

    // Parameters
    localparam CLK_PERIOD = 10;  // 100MHz clock (10ns period)

    // DUT Signals
    logic       clk;
    logic       rst_n;
    logic       en;
    logic [7:0] ui_in;
    logic       load_delay;
    logic       finish;

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Device Under Test (DUT)
    delay uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (en),
        .ui_in      (ui_in),
        .load_delay (load_delay),
        .finish     (finish)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---

    // Reset the DUT (synchronous reset)
    task reset_dut();
        begin
            @(posedge clk);
            en <= 0;
            load_delay <= 0;
            ui_in <= 8'b0;
            rst_n <= 0;
            repeat (3) @(posedge clk);
            rst_n <= 1;
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

    // Load a delay value (sets adj_delay via ui_in[4:0])
    task load_delay_value(input logic [4:0] val);
        begin
            @(posedge clk); // Align to clock edge first
            en <= 0;
            ui_in <= {3'b0, val};
            load_delay <= 1;
            @(posedge clk);
            load_delay <= 0;
            @(posedge clk);
            $display("[%0t] Loaded delay bit index = %0d", $time, val);
        end
    endtask

    // --- Main Test Sequence ---
    initial begin
        // Setup waveform dumping
        $dumpfile("logs/delay_testbench.vcd");
        $dumpvars(0, delay_testbench);

        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Initialize signals
        rst_n = 1;
        en = 0;
        ui_in = 8'b0;
        load_delay = 0;

        $display("");
        $display("========================================");
        $display("  delay Testbench");
        $display("========================================");
        $display("");

        // TEST 1: Reset Verification
        $display("[TEST 1] Reset Verification");
        reset_dut();
        check_value("finish", 0, finish);
        check_value("counter", 0, uut.counter);
        $display("");

        // TEST 2: Load Delay Value
        $display("[TEST 2] Load Delay Value");
        reset_dut();
        load_delay_value(5'd3);  
        check_value("adj_delay", 3, uut.adj_delay);
        check_value("finish (before counting)", 0, finish);
        $display("");

        // TEST 3: Counter counts while enabled
        $display("[TEST 3] Counter counts while enabled");
        reset_dut();
        load_delay_value(5'd3);
        en <= 1;
        wait_cycles(4);
        check_value("finish (after 4 cycles)", 0, finish);
        $display("  counter = %0d", uut.counter);
        $display("");

        // TEST 4: Finish asserts when watched bit is set
        $display("[TEST 4] Finish asserts when watched bit is set");
        reset_dut();
        load_delay_value(5'd3);
        en <= 1;
        wait_cycles(9); // Adjusted for propagation
        check_value("finish (after 9 cycles)", 1, finish);
        $display("  counter = %0d", uut.counter);
        $display("");

        // TEST 5: Counter stops when finish is high
        $display("[TEST 5] Counter stops when finish is high");
        reset_dut();
        load_delay_value(5'd3);
        en <= 1;
        wait_cycles(9);  // Adjusted to reach finish state
        begin
            logic [31:0] saved_counter;
            saved_counter = uut.counter;
            wait_cycles(5);
            check_value("finish (still high)", 1, finish);
            check_value("counter (unchanged)", saved_counter, uut.counter);
        end
        $display("");

        // TEST 6: Reset clears counter mid-count
        $display("[TEST 6] Hard Reset clears counter mid-count");
        reset_dut();
        load_delay_value(5'd4);
        en <= 1;
        wait_cycles(5);  
        reset_dut();
        check_value("counter (after reset)", 0, uut.counter);
        check_value("finish (after reset)", 0, finish);
        $display("");

        // TEST 7: Different delay value (bit 1 -> finish at 2)
        $display("[TEST 7] Different delay value (bit 1)");
        reset_dut();
        load_delay_value(5'd1);  
        en <= 1;
        wait_cycles(2); // Adjusted for propagation
        check_value("finish (after 2 cycles)", 0, finish);
        wait_cycles(1);
        check_value("finish (after 3 cycles)", 1, finish);
        $display("");

        // TEST 8: Counter does not count when disabled
        $display("[TEST 8] Counter does not count when disabled");
        reset_dut();
        load_delay_value(5'd4);
        en <= 0; 
        begin
            logic [31:0] saved_counter;
            saved_counter = uut.counter;
            wait_cycles(10);
            check_value("counter (en=0, unchanged)", saved_counter, uut.counter);
            check_value("finish (en=0)", 0, finish);
        end
        $display("");

        // TEST 9: Auto-Reset (Dropping 'en' clears counter)
        $display("[TEST 9] Auto-Reset clears counter when 'en' drops");
        reset_dut();
        load_delay_value(5'd4);
        en <= 1;
        wait_cycles(5); 
        $display("  counter before drop = %0d", uut.counter);
        en <= 0; // Drop enable
        wait_cycles(2); // Wait for DUT to sample the drop
        check_value("counter (after en dropped)", 0, uut.counter);
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