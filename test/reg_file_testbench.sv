`timescale 1ns / 1ps

module reg_file_testbench;

    // Parameters
    localparam CLK_PERIOD = 10;  // 100MHz clock (10ns period)

    // DUT Signals
    logic       clk;
    logic       we;
    logic [2:0] in_reg;
    logic [3:0] in_sel;   // Updated to 4-bit for 16 registers
    logic [2:0] out_reg;
    logic [3:0] out_sel;  // Updated to 4-bit for 16 registers

    // Testbench Variables
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Device Under Test (DUT)
    reg_file uut (
        .clk     (clk),
        .we      (we),
        .in_reg  (in_reg),
        .in_sel  (in_sel),
        .out_reg (out_reg),
        .out_sel (out_sel)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- Helper Tasks ---

    // Check expected vs actual value
    task check_value(
        input string signal_name,
        input logic [2:0] expected,
        input logic [2:0] actual
    );
        begin
            test_count++;
            if (actual === expected) begin
                pass_count++;
                $display("  PASS: %s = 0x%01h (expected 0x%01h)", signal_name, actual, expected);
            end else begin
                fail_count++;
                $display("  FAIL: %s = 0x%01h (expected 0x%01h)", signal_name, actual, expected);
            end
        end
    endtask

    // Write a value to a register and wait one clock cycle
    task write_reg(input logic [3:0] sel, input logic [2:0] data);
        begin
            @(posedge clk);
            in_sel = sel;
            in_reg = data;
            we = 1'b1;
            @(posedge clk);  // data latched on this edge
            we = 1'b0;
        end
    endtask

    // Read a register (combinational)
    task read_reg(input logic [3:0] sel, output logic [2:0] data);
        begin
            out_sel = sel;
            #1;
            data = out_reg;
        end
    endtask

    // --- Main Test Sequence ---
    initial begin
        // Setup waveform dumping
        $dumpfile("logs/reg_file_testbench.vcd");
        $dumpvars(0, reg_file_testbench);

        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Initialize signals
        in_reg  = 3'd0;
        in_sel  = 4'd0;
        out_sel = 4'd0;
        we      = 1'b0;

        $display("\n============================================");
        $display("  reg_file Testbench (16 Registers)");
        $display("============================================\n");

        // -------------------------------------------------
        // TEST 1: Single Write and Read
        // -------------------------------------------------
        $display("[TEST 1] Single Write and Read");
        write_reg(4'd0, 3'h5);
        begin
            logic [2:0] rdata;
            read_reg(4'd0, rdata);
            check_value("reg[0] after write 0x5", 3'h5, rdata);
        end
        $display("");

        // -------------------------------------------------
        // TEST 2: Write and Read All 16 Registers
        // -------------------------------------------------
        $display("[TEST 2] Write and Read All 16 Registers");
        // Write a unique value to each register (0 to 15)
        for (int i = 0; i < 16; i++) begin
            // Using (i % 8) because data width in_reg is still 3 bits
            write_reg(i[3:0], i[2:0]); 
        end
        // Read back and verify each register
        for (int i = 0; i < 16; i++) begin
            logic [2:0] rdata;
            read_reg(i[3:0], rdata);
            check_value($sformatf("reg[%0d]", i), i[2:0], rdata);
        end
        $display("");

        // -------------------------------------------------
        // TEST 3: Overwrite a High-Address Register
        // -------------------------------------------------
        $display("[TEST 3] Overwrite a High-Address Register (reg[15])");
        write_reg(4'd15, 3'h6);
        begin
            logic [2:0] rdata;
            read_reg(4'd15, rdata);
            check_value("reg[15] first write 0x6", 3'h6, rdata);
        end
        write_reg(4'd15, 3'h3);
        begin
            logic [2:0] rdata;
            read_reg(4'd15, rdata);
            check_value("reg[15] overwrite 0x3", 3'h3, rdata);
        end
        $display("");

        // -------------------------------------------------
        // TEST 4: Boundary Register Addresses
        // -------------------------------------------------
        $display("[TEST 4] Boundary Register Addresses (0 and 15)");
        write_reg(4'd0, 3'h1);
        write_reg(4'd15, 3'h7);
        begin
            logic [2:0] rdata;
            read_reg(4'd0, rdata);
            check_value("reg[0] (first)", 3'h1, rdata);
            read_reg(4'd15, rdata);
            check_value("reg[15] (last)", 3'h7, rdata);
        end
        $display("");

        // -------------------------------------------------
        // TEST 5: Write Enable Deasserted
        // -------------------------------------------------
        $display("[TEST 5] Write Enable Deasserted");
        write_reg(4'd8, 3'h4);
        @(posedge clk);
        in_sel = 4'd8;
        in_reg = 3'h2;
        we = 1'b0;
        @(posedge clk);
        begin
            logic [2:0] rdata;
            read_reg(4'd8, rdata);
            check_value("reg[8] unchanged (we=0)", 3'h4, rdata);
        end
        $display("");

        // -------------------------------------------------
        // Final Summary
        // -------------------------------------------------
        $display("\n============================================");
        $display("  Test Summary");
        $display("--------------------------------------------");
        $display("  Total Tests: %3d", test_count);
        $display("  Passed:      %3d", pass_count);
        $display("  Failed:      %3d", fail_count);
        $display("--------------------------------------------");

        if (fail_count == 0) begin
            $display("  Result:  ALL TESTS PASSED");
        end else begin
            $display("  Result:  SOME TESTS FAILED");
        end
        $display("============================================\n");

        $finish;
    end

    // Timeout Watchdog
    initial begin
        #1000000;
        $display("\n ERROR: Simulation timeout!");
        $finish;
    end

endmodule