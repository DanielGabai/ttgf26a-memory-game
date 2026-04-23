# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_memory_game(dut):
    """
    Test the memory game top module.
    dut is the top_testbench module, which contains the DUT internally.
    """
    dut._log.info("Starting Memory Game Test")

    # The testbench has its own clock generation in Verilog,
    # but we can still monitor it from cocotb
    
    # Wait for simulation to complete
    # The Verilog testbench runs its own test sequence
    await ClockCycles(dut.clk, 1000)
    
    dut._log.info("Test completed")

    # You can add assertions here to check results from the Verilog testbench
    # For example, if the testbench sets a signal indicating pass/fail:
    # assert dut.test_passed.value == 1
