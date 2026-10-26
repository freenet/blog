---
title: "Making signature checks faster in Freenet contracts"
date: 2026-10-26
description: "A contract that checks many signatures can run out of time inside WebAssembly. One build setting made ed25519 verification about 1.4 times faster for River's next room contract. Two other ideas made it slower."
---

Freenet contracts run as WebAssembly (WASM) on every node that hosts them, and each call into a contract has a 5 second limit. While designing the next version of River's room state, we found that signature checks were most of the cost of validating a room, and that a large room would not fit in that limit. This post describes what we measured, the build setting that helped, two ideas that made things worse, and what is still needed.

## Why signatures dominate

River's next room state is built so that the network's merge rules hold by construction: every record (a member's link into the room, a ban, a message, a direct message) carries its own signature, and a node can check any state it receives without trusting whoever sent it. A room needs roughly 4 to 9 signatures per member.

A node does more than one call per update. When it receives a full room state, it validates the incoming state, merges it with the state it holds, and validates the result. Each of those is a separate contract call, so each one has to fit in 5 seconds on its own, on the slowest machine that hosts the room.

At the first draft's limits, a 2,000-member room needed about 30,000 signature checks per validation and took over 10 seconds on our test machine.

## Is the WASM interpreted?

No. freenet-core runs contracts with [wasmtime](https://wasmtime.dev/), which compiles each contract to native machine code with the Cranelift compiler before running it. freenet-core turns Cranelift's optimisations off (`OptLevel::None`) to keep the compiler simple for untrusted code. Turning them on (`Speed` or `SpeedAndSize`) saved only 5 to 15 percent in our room-state measurements, so the compiler setting was not the main cost.

## What we measured

We wrote a small contract-like WASM module that verifies one fixed ed25519 signature 2,000 times with `ed25519-dalek` 2.2's `verify_strict`, the check River uses, and ran it in a wasmtime 47 host configured the way freenet-core configures its engine: Cranelift `OptLevel::None`, a 256 MiB memory reservation, epoch interruption on, fuel metering off. Each figure is the median of 5 runs on an Intel i9-9900K that was also running other work (load average 3 to 9). The same loop compiled natively gives the baseline.

| How the contract is built | Time per signature |
|---|---|
| Native code, for comparison | 42 to 46 µs |
| WASM, crypto crates at `opt-level = "z"` (River's current setting) | 327 µs |
| WASM, crypto crates at `opt-level = 3` | 227 µs |
| WASM, forced 64-bit curve arithmetic | 741 µs |
| WASM, `ed25519-compact` instead of `ed25519-dalek` | 720 µs or more |

Two more columns from the same runs, for the default build at `opt-level = "z"`:

- With Cranelift optimisation on (`Speed`): 294 µs.
- With a 4 GiB memory reservation instead of 256 MiB: 236 µs. With the full reservation, wasmtime can rely on guard pages and skip the bounds check on each memory access.

## What helped: building the crypto crates for speed

Freenet contracts are usually built with `opt-level = "z"`, which asks the Rust compiler for the smallest code. Building only the signature and hash crates (`curve25519-dalek`, `ed25519-dalek`, `sha2`, `blake3`) at `opt-level = 3`, and leaving the rest of the contract at `"z"`, made each signature check about 1.4 times faster: 327 µs to 227 µs. The cost is a larger file: the test module grew from 38 KB to 60 KB, and River's next room contract from 799 KB to 811 KB.

In River's own measurement of the next room contract, which uses a different test harness and records, a signature check went from 0.38 ms to 0.25 ms. The largest valid room at the planned limits, made mostly of records migrated from today's format, now merges in about 2.0 seconds instead of 2.4. A room made of new-format records stays under 2.5 seconds per call up to about 800 members. These timings come from the same loaded test machine, so a slower or busier host will take longer.

## What made it slower

**Forcing 64-bit arithmetic.** On a native 64-bit machine, `curve25519-dalek` does its field arithmetic with 64-bit numbers and 128-bit products. On `wasm32` it uses a 32-bit version by default. We expected the 64-bit version to be faster, because WASM has 64-bit integers. It was about 2.3 times slower: WASM has no instruction that multiplies two 64-bit numbers into a 128-bit result, so every such product is built from several smaller multiplications. The default was already the right choice.

**A different library.** `ed25519-compact`, which River already lists as an option for WASM builds, was about 2.2 times slower than `ed25519-dalek` in this test.

## What we did not change

Removing the per-access bounds checks would save about a quarter of the time, but it needs a 4 GiB address reservation for every contract instance. freenet-core reduced that reservation to 256 MiB because the larger one made contract calls fail on small machines such as a 4 GB Raspberry Pi ([#3986](https://github.com/freenet/freenet-core/issues/3986)). We are keeping the smaller reservation.

## What is still needed

With the faster build, a signature check in WASM still costs about 5 times as much as in native code (227 µs against 42 to 46 µs). Fitting a 2,000-member room comfortably would take checks about 10 times cheaper than today's in-contract cost, which only native verification provides. [freenet-core#6000](https://github.com/freenet/freenet-core/issues/6000) proposes letting contracts call a small set of native, deterministic crypto functions (strict ed25519 verification and two hash functions). That needs care: every node must give exactly the same answer for every input, and a bug in such a function would sit outside the WASM sandbox, so the issue lists the safeguards it requires. Until it exists, River's next room state will ship with limits that fit today's cost.

## If you build a contract

The `dapp-builder` guide in [freenet-agent-skills](https://github.com/freenet/freenet-agent-skills) now covers this in `references/build-system.md`: the profile settings, the measurements above, and how to time your largest valid state in WASM. One warning applies to every deployed contract: changing a build profile changes the contract's WASM, and with it the contract's key. Apply it to a new contract, or as part of a planned upgrade that migrates existing state, never as a quiet rebuild.
