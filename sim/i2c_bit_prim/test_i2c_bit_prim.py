# sim/i2c_bit_prim/test_i2c_bit_prim.py
#
# cocotb v2.0+ compatible tests for i2c_bit_prim
#
# Focus:
#  - handshake invariants (busy/done)
#  - read bit correctness with/without clock stretching
#  - randomized stress across prescale and stretch lengths
#
# Notes:
#  - Your SV TB must NOT run its own stimulus under COCOTB_SIM.
#  - We drive dut.start/op_read/tx_bit/prescale and TB slave pulls.
#
import random

import cocotb
from cocotb.triggers import RisingEdge

# ----------------------------
# Tunables / expectations
# ----------------------------

# How many randomized trials to run
NTRIALS = 50

# Timeout in clk cycles for any transaction to complete
DONE_TIMEOUT_CYCLES = 20_000

# Default behavior expectation:
# If start is pulsed while busy=1, do you expect it to be ignored?
EXPECT_SECOND_KICK_IGNORED = True


# ----------------------------
# Helpers
# ----------------------------


def _sig(dut, name: str):
    """Get a handle or raise a clear error."""
    if not hasattr(dut, name):
        raise AssertionError(
            f"Missing signal '{name}' in VPI. "
            f"If it's a TB-local, add '(* keep *)' or expose it."
        )
    return getattr(dut, name)


async def wait_for_reset_release(dut, max_cycles=1000):
    """Wait until rst_n==1 (TB drives reset)."""
    if hasattr(dut, "rst_n"):
        for _ in range(max_cycles):
            if int(dut.rst_n.value) == 1:
                return
            await RisingEdge(dut.clk)
        raise AssertionError("Timeout waiting for rst_n==1")
    else:
        # No reset in design; just wait a few cycles
        for _ in range(10):
            await RisingEdge(dut.clk)


async def kick_start(dut):
    """Pulse start for 1 clk cycle."""
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


async def wait_done_pulse(dut, timeout_cycles=DONE_TIMEOUT_CYCLES):
    """
    Wait for a done pulse (done==1 at some clk edge).
    Returns the cycle count waited.
    """
    for i in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            return i + 1
    raise AssertionError(f"Timeout waiting for done (>{timeout_cycles} cycles)")


async def count_done_pulses(dut, cycles: int) -> int:
    """Count how many cycles have done==1 over a window (sampled at clk edges)."""
    cnt = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            cnt += 1
    return cnt


async def ensure_done_is_pulse(dut, post_window_cycles=50):
    """
    After seeing done once, ensure it doesn't stay stuck high and doesn't pulse again
    (unless you later start another op).
    """
    # Immediately after done, it should drop back low quickly.
    # Allow 1 cycle grace.
    await RisingEdge(dut.clk)
    if int(dut.done.value) == 1:
        # One more grace cycle
        await RisingEdge(dut.clk)
        assert int(dut.done.value) == 0, "done appears stuck high (not a pulse)"

    # Over the next window, expect no additional done pulses (for a single kick).
    extra = await count_done_pulses(dut, post_window_cycles)
    assert extra == 0, f"Unexpected extra done pulses after completion: {extra}"


async def stretch_scl_for_cycles(dut, stretch_cycles: int, arm_delay_cycles: int = 2):
    """
    Apply clock stretching by pulling SCL low for stretch_cycles.
    arm_delay_cycles delays the stretch after kick, to catch the SCL raise phase.
    """
    slave_scl_pull = _sig(dut, "slave_scl_pull")
    if stretch_cycles <= 0:
        return

    # Wait a couple of cycles so the primitive is in its "raise SCL" phase.
    for _ in range(arm_delay_cycles):
        await RisingEdge(dut.clk)

    slave_scl_pull.value = 1
    for _ in range(stretch_cycles):
        await RisingEdge(dut.clk)
    slave_scl_pull.value = 0


def set_slave_sda(dut, bit: int):
    """
    Slave drives SDA low for bit=0, releases for bit=1.
    Open-drain: driving '1' means release (Z).
    """
    slave_sda_pull = _sig(dut, "slave_sda_pull")
    slave_sda_pull.value = 1 if (bit == 0) else 0


def clear_slave_pulls(dut):
    _sig(dut, "slave_scl_pull").value = 0
    _sig(dut, "slave_sda_pull").value = 0


async def settle_sync(dut, cycles=2):
    for _ in range(cycles):
        await RisingEdge(dut.clk)


# ----------------------------
# Test cases
# ----------------------------


@cocotb.test()
async def handshake_invariants(dut):
    """
    Check basic liveness + pulse properties for WRITE and READ operations.
    - busy should assert after kick
    - done should happen within timeout
    - done should be a pulse
    """
    await wait_for_reset_release(dut)

    # Sanity: initial values
    clear_slave_pulls(dut)
    dut.start.value = 0
    dut.prescale.value = 1  # fast
    dut.op_read.value = 0
    dut.tx_bit.value = 0

    # Kick a WRITE
    await kick_start(dut)

    # busy should go high soon
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(dut.busy.value) == 1:
            break
    else:
        raise AssertionError("busy did not assert after kick (WRITE)")

    await wait_done_pulse(dut)
    assert int(dut.busy.value) == 0, "busy should be 0 at/after done (WRITE)"
    await ensure_done_is_pulse(dut)

    # Kick a READ (slave drives 0)
    dut.op_read.value = 1
    set_slave_sda(dut, 0)
    await settle_sync(dut, 2)
    await kick_start(dut)
    await wait_done_pulse(dut)

    assert int(dut.rx_bit.value) == 0, f"Expected rx_bit=0, got {int(dut.rx_bit.value)}"
    assert int(dut.busy.value) == 0, "busy should be 0 at/after done (READ)"
    await ensure_done_is_pulse(dut)


@cocotb.test()
async def read_correctness_no_stretch(dut):
    """
    Directed correctness checks for READ with slave driving 0 and 1, without stretching.
    """
    await wait_for_reset_release(dut)

    clear_slave_pulls(dut)
    dut.start.value = 0
    dut.prescale.value = 1
    dut.op_read.value = 1
    dut.tx_bit.value = 1  # don't care for READ

    # READ 0
    set_slave_sda(dut, 0)
    await settle_sync(dut, 2)
    await kick_start(dut)
    await wait_done_pulse(dut)
    assert int(dut.rx_bit.value) == 0, f"READ0: rx_bit={int(dut.rx_bit.value)}"

    # READ 1
    set_slave_sda(dut, 1)
    await settle_sync(dut, 2)
    await kick_start(dut)
    await wait_done_pulse(dut)
    assert int(dut.rx_bit.value) == 1, f"READ1: rx_bit={int(dut.rx_bit.value)}"


@cocotb.test()
async def randomized_read_with_stretch(dut):
    """
    Random stress test:
      - random prescale
      - random stretch length
      - random slave bit
    Asserts rx_bit matches and operation completes.
    """
    await wait_for_reset_release(dut)

    clear_slave_pulls(dut)
    dut.start.value = 0
    dut.op_read.value = 1
    dut.tx_bit.value = 1  # don't care for READ

    for k in range(NTRIALS):
        # Keep prescale > 0 unless you intentionally support 0
        prescale = random.randint(1, 20)
        stretch = random.randint(0, 30)
        bit = random.randint(0, 1)

        dut.prescale.value = prescale
        set_slave_sda(dut, bit)
        await settle_sync(dut, 2)
        _sig(dut, "slave_scl_pull").value = 0  # ensure released before start

        # Start stretch task (may do nothing if stretch==0)
        stretcher = cocotb.start_soon(
            stretch_scl_for_cycles(dut, stretch_cycles=stretch)
        )

        await kick_start(dut)
        await wait_done_pulse(dut)

        # Ensure stretcher completes (it will if stretch>=0)
        await stretcher

        got = int(dut.rx_bit.value)
        assert got == bit, (
            f"trial={k} prescale={prescale} stretch={stretch} "
            f"expected rx_bit={bit}, got {got}"
        )

        # Small gap between transactions
        await RisingEdge(dut.clk)


@cocotb.test()
async def kick_while_busy(dut):
    """
    Define and lock in behavior for 'start while busy'.

    Default expectation (configurable):
      - second kick while busy is ignored (no extra done pulse)
    Minimum requirement:
      - must not deadlock
      - must return to idle (busy=0)
    """
    await wait_for_reset_release(dut)

    clear_slave_pulls(dut)
    dut.start.value = 0
    dut.prescale.value = 1
    dut.op_read.value = 1
    dut.tx_bit.value = 1
    set_slave_sda(dut, 1)
    await settle_sync(dut, 2)

    # First kick
    await kick_start(dut)

    # Wait until busy asserts
    for _ in range(500):
        await RisingEdge(dut.clk)
        if int(dut.busy.value) == 1:
            break
    else:
        raise AssertionError("busy never asserted after first kick")

    # Second kick while busy
    await kick_start(dut)

    # Wait for completion of at least one op
    await wait_done_pulse(dut)

    # Count additional done pulses for a while
    extra_done = await count_done_pulses(dut, cycles=200)

    # Must not stay busy forever
    for _ in range(5000):
        await RisingEdge(dut.clk)
        if int(dut.busy.value) == 0:
            break
    else:
        raise AssertionError(
            "busy did not return to 0 after kicks (potential deadlock)"
        )

    if EXPECT_SECOND_KICK_IGNORED:
        assert extra_done == 0, (
            f"Expected second kick ignored, but saw extra done pulses: {extra_done}"
        )
    else:
        # If you later decide it should queue, you can flip this expectation.
        assert extra_done >= 0  # keep test meaningful (no constraint)


@cocotb.test()
async def write_operation_smoke(dut):
    """
    Quick smoke for WRITE operation (op_read=0):
      - tx_bit=0 should pull SDA low at some point (optional)
      - tx_bit=1 should release SDA (optional)
    This test currently only checks handshake (since exact pad timing may vary).
    """
    await wait_for_reset_release(dut)

    clear_slave_pulls(dut)
    dut.start.value = 0
    dut.prescale.value = 1
    dut.op_read.value = 0

    # WRITE 0
    dut.tx_bit.value = 0
    await kick_start(dut)
    await wait_done_pulse(dut)
    await ensure_done_is_pulse(dut)

    # WRITE 1
    dut.tx_bit.value = 1
    await kick_start(dut)
    await wait_done_pulse(dut)
    await ensure_done_is_pulse(dut)
