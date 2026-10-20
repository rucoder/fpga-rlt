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
from cocotb.triggers import FallingEdge, ReadWrite, RisingEdge

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


async def _drive(sig, value, label: str = ""):
    """Write and VERIFY: read back after the write settles; retry if lost.

    Occasional VPI writes have been observed not to reach the design in this
    simulator flow (wall-clock dependent). A drive that verifies itself turns
    a silent loss into a loud, self-healing retry.
    """
    from cocotb.triggers import ReadWrite
    for attempt in range(4):
        sig.value = value
        await ReadWrite()
        if int(sig.value) == int(value):
            if attempt:
                print(f"DRIVE-RETRY {label}: needed {attempt + 1} attempts", flush=True)
            return
    raise AssertionError(f"DRIVE-FAILED {label}: wrote {value}, reads {int(sig.value)}")


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
    """Pulse start for 1 clk cycle, aligned to the falling edge.

    Posedge-aligned one-edge pulses can lose the scheduler's delta race:
    the write may land after the edge's sampling region, so the DUT never
    sees start=1 and the op never starts (symptom: busy-never / timeouts).
    Two rules keep it safe:
      1. Align to the falling edge (half a cycle of settle margin).
      2. Hold the pulse across TWO posedges: VPI writes reach the design's
         combinational logic with roughly one evaluation-boundary of
         deferral in this simulator flow, so a pulse spanning a single
         posedge can fall entirely inside the deferral window and never
         be sampled (observed and proven with per-edge DUT-state dumps,
         2026-10-19; identical under Verilator 5.042 and 5.052).
    The FSM latches the command on the first edge it sees, so a 2-edge
    pulse still starts exactly one operation.
    """
    await FallingEdge(dut.clk)
    await ReadWrite()
    dut.start.value = 1
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await ReadWrite()
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


async def wait_busy_low(dut, op: str, max_cycles=None):
    """Wait for busy to fall after done (FINISH_LOW takes one tick phase)."""
    if max_cycles is None:
        max_cycles = 4 * (1 + int(dut.prescale.value))
    for _ in range(max_cycles):
        if int(dut.busy.value) == 0:
            return
        await RisingEdge(dut.clk)
    raise AssertionError(f"busy did not return to 0 after done ({op})")


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

    await FallingEdge(dut.clk)
    await ReadWrite()
    await _drive(slave_scl_pull, 1, "scl_stretch_on")
    for _ in range(stretch_cycles):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await ReadWrite()
    await _drive(slave_scl_pull, 0, "scl_stretch_off")


async def set_slave_sda(dut, bit: int):
    """
    Slave drives SDA low for bit=0, releases for bit=1.
    Open-drain: driving '1' means release (Z).
    Negedge-aligned: the write must not race the posedge sampling (see
    kick_start).
    """
    await FallingEdge(dut.clk)
    await ReadWrite()
    await _drive(_sig(dut, "slave_sda_pull"), 1 if (bit == 0) else 0, "sda_pull")


async def clear_slave_pulls(dut):
    await FallingEdge(dut.clk)
    await ReadWrite()
    await _drive(_sig(dut, "slave_scl_pull"), 0, "scl_pull_clear")
    await _drive(_sig(dut, "slave_sda_pull"), 0, "sda_pull_clear")


async def settle_sync(dut, cycles=3):
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
    await clear_slave_pulls(dut)
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
    # done pulses at the SCL-high sample point; the FSM still walks
    # FINISH_LOW (one more tick phase) before returning to idle.
    await wait_busy_low(dut, "WRITE")
    await ensure_done_is_pulse(dut)

    # Kick a READ (slave drives 0)
    dut.op_read.value = 1
    await set_slave_sda(dut, 0)
    await settle_sync(dut, 2)
    await kick_start(dut)
    await wait_done_pulse(dut)

    assert int(dut.rx_bit.value) == 0, f"Expected rx_bit=0, got {int(dut.rx_bit.value)}"
    await wait_busy_low(dut, "READ")
    await ensure_done_is_pulse(dut)


@cocotb.test()
async def read_correctness_no_stretch(dut):
    """
    Directed correctness checks for READ with slave driving 0 and 1, without stretching.
    """
    await wait_for_reset_release(dut)

    await clear_slave_pulls(dut)
    dut.start.value = 0
    dut.prescale.value = 1
    dut.op_read.value = 1
    dut.tx_bit.value = 1  # don't care for READ

    # READ 0
    await set_slave_sda(dut, 0)
    await settle_sync(dut, 2)
    await kick_start(dut)
    await wait_done_pulse(dut)
    assert int(dut.rx_bit.value) == 0, f"READ0: rx_bit={int(dut.rx_bit.value)}"
    # let the DUT walk FINISH_LOW back to idle before the next kick -
    # start is ignored while busy (locked in by kick_while_busy)
    await wait_busy_low(dut, "READ0")

    # READ 1
    await set_slave_sda(dut, 1)
    await settle_sync(dut, 2)
    await kick_start(dut)
    await wait_done_pulse(dut)
    assert int(dut.rx_bit.value) == 1, f"READ1: rx_bit={int(dut.rx_bit.value)}"
    # leave the DUT idle: tests share one simulation, and the next test
    # changes prescale and kicks - a kick while FINISH_LOW runs is ignored
    await wait_busy_low(dut, "READ1")


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

    await clear_slave_pulls(dut)
    dut.start.value = 0
    dut.op_read.value = 1
    dut.tx_bit.value = 1  # don't care for READ

    for k in range(NTRIALS):
        # Keep prescale > 0 unless you intentionally support 0
        prescale = random.randint(1, 20)
        stretch = random.randint(0, 30)
        bit = random.randint(0, 1)

        dut.prescale.value = prescale
        await set_slave_sda(dut, bit)
        await settle_sync(dut, 2)
        _sig(dut, "slave_scl_pull").value = 0  # ensure released before start

        print(f"TRIAL {k}: prescale={prescale} stretch={stretch} bit={bit}", flush=True)
        # Start stretch task (may do nothing if stretch==0)
        stretcher = cocotb.start_soon(
            stretch_scl_for_cycles(dut, stretch_cycles=stretch)
        )

        await kick_start(dut)
        await wait_done_pulse(dut)

        # Ensure stretcher completes (it will if stretch>=0)
        await stretcher
        # DUT must be idle before the next kick (start ignored while busy)
        await wait_busy_low(dut, f"trial={k}")

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

    await clear_slave_pulls(dut)
    dut.start.value = 0
    dut.prescale.value = 1
    dut.op_read.value = 1
    dut.tx_bit.value = 1
    await set_slave_sda(dut, 1)
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

    await clear_slave_pulls(dut)
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
