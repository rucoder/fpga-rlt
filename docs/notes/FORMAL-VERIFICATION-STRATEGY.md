Yes, you can reuse work — but not in the “the tool automatically trusts the submodule because it was proven once” way unless you deliberately set things up for it.

Here’s how it works in practice.

1) Default reality: formal always re-proves the whole flattened design

When you run sby on a top, Yosys+SMTBMC reasons about the RTL under that top. Even if sync_2ff was proven yesterday, the solver doesn’t “import a certificate” and skip it. It just sees more logic.

So: proofs don’t automatically compose.

2) What does reuse look like?

Reuse is mostly about reusing property modules + assumptions + harness patterns, not “proof caching”.

You can reuse in three useful ways:

A) Reuse properties by binding them inside larger tops

Example: you already have sync_2ff_props. In the next design (say i2c_od_pads_formal_top), you can bind the same sync_2ff_props to the synchronizer instances. Then you’re reusing your verification intent as a regression.

This doesn’t reduce solver work, but it scales correctness.

B) Assume–Guarantee (true compositional verification)

This is the “real” modular reuse pattern:

You proved Module A:
If environment satisfies assumptions A_assume, then A guarantees A_guarantee.

In Module B that instantiates A, you:

assume A_guarantee as an abstraction of A (i.e. treat A like a spec),

prove B’s properties using that assumption,

separately prove that the real A implementation meets A_guarantee under A_assume.

That gives you compositional reasoning. But tooling won’t do it magically — you have to encode the abstraction.

C) Replace the submodule with a “spec model” for top-level proofs

Instead of instantiating the real sync_2ff, you instantiate a simplified model that only captures what you need, e.g.:

sync_out equals $past(async_in,2) (in RTL terms), or even weaker: “sync_out is some stable sampled version”.

That can dramatically speed up proofs of large systems, because you remove internal detail.

You then keep a separate proof that the real sync_2ff refines that spec.

This is basically (B) but implemented as a drop-in replacement.

3) What about “flattening” vs “keeping hierarchy”?

If you prep -flatten, the solver still reasons about the same behavior, just with hierarchy removed. It doesn’t change the “reuse” story.

Keeping hierarchy can make debugging nicer, but proofs are still whole-design.

4) For your current bricks (tick_div, sync_2ff, i2c_od_pads), what should you do?

Best pragmatic workflow:

Prove each leaf brick (you did for tick_div, and will for sync_2ff).

For composed blocks:

use simulation for the inout/z glue (i2c_od_pads)

and start serious formal again at the bit/byte engine level, where properties are meaningful (SDA changes only when SCL low, START/STOP behavior, ACK sampling, etc.)

When the I²C engine gets bigger and proofs slow down:

replace sync_2ff with a small spec stub in formal runs (Option C), and keep sync_2ff proven separately.

5) TL;DR

No, proofs aren’t automatically reused/cached across modules.

Yes, you reuse work via:

reusable bind property modules (regression)

assume–guarantee + spec stubs (true compositional reuse + speed)


TODO
------
formal/i2c_bit_prim/i2c_bit_prim_formal_top.sv
  What we intentionally didn’t prove yet
  We didn’t prove “operation always finishes”, because that’s liveness and depends on the environment eventually letting scl_sync go high. We can add a bounded liveness check later using:
  an assumption like “if want_scl_high stays 1, scl_sync becomes 1 within N ticks”
  then prove “done within M ticks”
  That’s a great next step once you like the current safety proof.
