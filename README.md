![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Number Memory Game

- [Read the documentation for project](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Project Description

This project implements a Number Memory Game in SystemVerilog, designed for Tiny Tapeout. The game generates a sequence of random digits (0–7) and flashes them one at a time on a seven-segment display. After watching the sequence, the player must reproduce it from memory using input switches. Each round the sequence grows by one digit, up to a maximum of 16.

### Architecture

| Module | Role |
|---|---|
| `game_fsm` | Central FSM — controls all game states and datapath signals |
| `lfsr` | 6-bit Linear Feedback Shift Register — generates the pseudo-random sequence |
| `reg_file` | 16 × 3-bit register file — stores the generated sequence |
| `delay` | Configurable timer — controls how long each digit and gap is displayed |
| `synchronizer` | 2-FF metastability synchronizer + debounce filter for all 8 switch inputs |
| `edge_detector` | Detects the falling edge of the submit switch to produce a single-cycle pulse |
| `decoder` | Converts a 3-bit digit (0–7) to seven-segment encoding |

### Switch Map

The 8 input switches serve different roles depending on the current game phase:

| Switch | Seed phase | Delay phase | Gameplay phase |
|---|---|---|---|
| sw[0] | Seed bit 0 (LSB) | Delay bit 0 (LSB) | Guess bit 0 (LSB) |
| sw[1] | Seed bit 1 | Delay bit 1 | Guess bit 1 |
| sw[2] | Seed bit 2 | Delay bit 2 | Guess bit 2 (MSB) |
| sw[3] | Seed bit 3 | Delay bit 3 | — (ignored) |
| sw[4] | Seed bit 4 | Delay bit 4 (MSB) | — (ignored) |
| sw[5] | Seed bit 5 (MSB) | — (ignored) | — (ignored) |
| sw[6] | Submit (pulse) | Submit (pulse) | Submit (pulse) |
| sw[7] | Start / reset | Start / reset | Start / reset |

### Seven-Segment Output

| Display | Meaning |
|---|---|
| Digit 0–7 | Current number in the sequence |
| Blank | Waiting for input, or gap between digits |
| `C` | Game won — all 16 rounds completed correctly |
| `F` | Game over — wrong digit entered |

---

## How to Play

### Before you start: choose your delay value

The delay setting controls how long each digit is shown and the blank gap between digits. It is set as a 5-bit value on sw[4:0] during the setup phase.

**The timing is exponential: display time = 2^N clock cycles at 50 MHz.**

A small-looking number like 5 or 10 will display digits for less than a millisecond — completely invisible to the human eye. You need a value around 25–26 for a comfortable playing speed.

| sw[4:0] value | Binary | Time per digit |
|---|---|---|
| 0 | `00000` | < 1 ms — invisible |
| 20 | `10100` | ~21 ms — too fast |
| 24 | `11000` | ~336 ms — fast |
| **25** | **`11001`** | **~671 ms — recommended** |
| **26** | **`11010`** | **~1.34 s — recommended** |
| 27 | `11011` | ~2.7 s — slow |
| 28 | `11100` | ~5.4 s — very slow |
| 31 | `11111` | ~43 s — maximum |

The same timer value is used for both the digit display and the blank gap between digits. **Decide on your value before starting — a good first choice is `11001` (25) or `11010` (26).**

---

### Step-by-step game flow

#### 1. Reset / idle

Make sure all 8 switches are low, then apply power (or assert `rst_n`). The display will be blank. The game is waiting.

#### 2. Start the game

Flip **sw[7] high**. Hold it high for the rest of the game — pulling it low at any point immediately resets everything.

#### 3. Enter a seed

Set **sw[5:0]** to any 6-bit value. This seeds the random number generator. Different seeds produce different sequences, so you can replay with a new sequence by resetting and choosing a different seed. Seed `000000` is handled safely (the hardware substitutes `000001` internally).

When your seed switches are set, **flip sw[6] high then bring it back low.** The submit registers when sw[6] goes *back down*, not when it goes up — so the full high-then-low action is required every time you submit. The display stays blank during this phase.

#### 4. Enter a delay

Without changing sw[7], now set **sw[4:0]** to your chosen delay value from the table above. sw[5] is ignored during this phase, so you do not need to clear it.

When your delay switches are set, **flip sw[6] high then back low** to submit.

#### 5. Watch the sequence

The game will immediately fill its memory with 16 random digits, then begin displaying them. You do not need to do anything during this step.

Each digit appears on the seven-segment display for the duration you configured, then the display goes blank for the same duration, then the next digit appears. **Round 0 shows 1 digit. Round 1 shows 2 digits. Each round adds one more.**

Watch carefully and memorise the sequence.

#### 6. Enter your guesses

After the last digit of the round, the display goes blank and the game waits for your input.

For each digit in the sequence (starting from the first):

1. Set **sw[2:0]** to the 3-bit value you remember (0–7 in binary).
2. **Flip sw[6] high then back low** to submit.

The game compares your input against its stored sequence immediately when sw[6] goes low.

- If correct and there are more digits to enter, the display stays blank and waits for your next guess.
- If correct and you have entered all digits for this round, the game advances to the next round and replays the sequence with one more digit.
- If wrong, the display shows **`F`** and the game locks. Pull sw[7] low to reset and try again.

#### 7. Winning

If you successfully complete all 16 rounds (entering a 16-digit sequence correctly), the display shows **`C`**. Pull sw[7] low to reset and start a new game.

---

### Quick reference card

```
SETUP
  sw[7] → HIGH (hold for entire game)
  sw[5:0] = seed, then sw[6] HIGH → LOW
  sw[4:0] = delay (use 11001 for ~0.7s), then sw[6] HIGH → LOW

WATCH
  Digits flash on display — memorise the sequence

GUESS (repeat for each digit)
  sw[2:0] = your guess
  sw[6] HIGH → LOW to submit

RESULT
  C = you won    F = wrong guess    sw[7] LOW to reset
```

---

### Common mistakes

**"The digits flash too fast to see"** — your delay value is too low. Reset and choose a higher value. Binary `11001` (25) or `11010` (26) are good starting points.

**"Nothing happened when I flipped sw[6]"** — the submit only registers on the falling edge, meaning sw[6] must go from high *back to low*. Make sure you complete the full flip. Also confirm sw[7] is still high.

**"The game reset by itself"** — sw[7] went low, either intentionally or from an accidental bump. Any time sw[7] goes low the game immediately returns to idle.

**"I entered the right number but got F"** — the guess is compared to the stored sequence starting from digit 0. Make sure you are entering digits in the order they were displayed, not the order you remember them.

**"The display is blank and I don't know what phase I'm in"** — the display is blank during seed entry, delay entry, and the input phase. The distinction is context: if you have just powered on and raised sw[7], you are entering the seed. After submitting the seed, you are entering the delay. After the sequence has played, you are guessing.

---

## How to Test

### Simulation

Navigate to the `test/` directory and run the testbenches:

```
make -B             # RTL simulation
make -B GATES=yes   # Gate-level simulation (after hardening)
make -B FST=        # Generate VCD instead of FST
```

View waveforms:

```
gtkwave tb.fst tb.gtkw
```

### Hardware

1. Ensure all switches are low before powering on.
2. Follow the step-by-step guide above.
3. Observe the seven-segment display on `uo_out[7:0]`. The MSB (`uo_out[7]`) is always 0 (no decimal point used).
4. If the game behaves unexpectedly at any point, pull sw[7] low to reset cleanly.

---

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)
