> Note (2026-10-19): written against the pre-ea2b3ae RTL, where `done` was a level during FINISH_LOW. The current design pulses `done` for one cycle at the SCL-high sample point (RAISE_HIGH→FINISH_LOW); the invariants below otherwise still apply.

It’s one I²C bit transaction, not a full byte.

It enforces the key I²C rule:

Change SDA only while SCL is low

Sample SDA while SCL is high

If a slave stretches SCL, we wait.

And it does this with only 4 states.

The 4 states in plain English

IDLE
Bus released. Wait for start.

SETUP_LOW
Pull SCL low. While SCL is low:

for write: set SDA to 0 (pull) or 1 (release)

for read: release SDA (slave may drive it)

RAISE_HIGH
Release SCL and wait until the line actually becomes high (scl_high_ok).
Then, on a tick boundary, sample SDA into rx_bit.

FINISH_LOW
Pull SCL low again for one tick, assert done, go back to IDLE.

That’s it. No quarter-bit yet.
----
What we proved (conceptually), and why it matters

Formal here is not “prove I²C works end-to-end”. It’s “prove we didn’t screw up the disciplines”.

Think of the proof as invariants and transition rules.

A) Invariants (always true when not in reset)

Examples:

busy is true iff we are not in IDLE
→ proves no weird “busy glitches”

done only happens in FINISH_LOW
→ proves done isn’t accidentally asserted elsewhere

scl_pull == ~want_scl_high
→ proves your polarity conventions are consistent

in READ mode, sda_pull is always 0 (released)
→ proves master never drives SDA during read

in WRITE mode, sda_pull equals (tx_bit==0)
→ proves master drives 0 correctly and releases for 1

These are structural correctness guarantees.

B) Transition rules (the FSM only moves in the intended way)

Examples:

SETUP_LOW can only go to RAISE_HIGH on tick

RAISE_HIGH can only go to FINISH_LOW when (scl_high_ok && tick)

etc.

This proves:

we never sample SDA while SCL is low

we never finish before SCL actually got high

we don’t “skip” phases

C) Sampling discipline for rx_bit

We proved: if rx_bit changes, it must have changed only at the sample point:

previous state was RAISE_HIGH

scl_high_ok was true (so SCL high observed)

tick was true (our chosen sample boundary)

This is the key I²C correctness idea for sampling.

Why formal is useful even if the brick feels “complex”

Because now you can refactor the implementation and know you didn’t break:

SDA driving policy

SCL stretching wait

state sequencing

sampling point

It’s like unit tests, but exhaustive.
