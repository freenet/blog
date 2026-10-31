---
title: "Freenet 0.2.152 crashes on CPUs without AVX2"
date: 2026-10-31
description: "A change to our build machine put AVX2 instructions into the 0.2.152 Linux x86_64 release, so it crashes on older and low-power CPUs. Here is what happened, how to recover, and what we are changing."
---

The Linux x86_64 build of Freenet 0.2.152, released on 30 October 2026, crashes at startup on any CPU without AVX2. We caused this by accident: the machine that builds our releases changed, and nothing checked the result. A user with two Dell Wyse 5070 nodes reported it the next morning.

A fix is in review as [#6061](https://github.com/freenet/freenet-core/pull/6061) and has not been released yet.

> **If your node stopped after updating to 0.2.152,** run `grep -c avx2 /proc/cpuinfo`. A result of 0 means your CPU, or the CPU your virtual machine is allowed to see, does not have AVX2, and this bug affects you. See [How to recover](#how-to-recover).

## What you would see

The node dies with an illegal instruction error (SIGILL, exit code 132). It dies before it creates a log file, so there is often nothing to read. `freenet --version` still works, which makes the binary look healthy. `freenet update` crashes in the same way, so 0.2.152 cannot update itself on these machines.

## Which machines are affected

The Linux x86_64 binaries of `freenet` and `fdev` are affected. We ran the shipped `freenet` binaries in `network` mode under `qemu-x86_64` user-mode emulation, using these CPU models:

| Emulated CPU | Has AVX2 | 0.2.151 | 0.2.152 |
|---|---|---|---|
| Nehalem | no | starts | crashes |
| Denverton (Atom server) | no | starts | crashes |
| SandyBridge (has AVX, no AVX2) | no | starts | crashes |
| Westmere | no | not run | crashes |
| Snowridge (Atom server) | no | not run | crashes |
| Haswell | yes | not run | starts |

These results come from emulation. We have not run it on physical affected hardware, other than the report that started this. The first report blamed AVX, and the SandyBridge row shows the requirement is actually AVX2.

The machines most likely to be affected are Celeron, Pentium and Atom mini PCs, thin clients and NAS boxes, older Xeon servers, and virtual machines configured with a generic CPU type, even on a modern host. The ARM Linux, Windows and macOS builds are made on different build machines with different compilers, so this cause does not apply to them, but we did not run those binaries in this test.

## How to recover

**If your node auto-updated and runs as the Freenet service,** it may have recovered without your help. After three crashes in a row following an update, the supervisor restores the previous binary and refuses to install the bad version again. Check with `freenet --version`. We tested this logic under emulation by running the post-crash step by hand, and it restored 0.2.151 on the third crash. We have not tested it under a real systemd service on affected hardware.

**If your node is still on 0.2.152,** install 0.2.151 by hand from the [0.2.151 release](https://github.com/freenet/freenet-core/releases/tag/v0.2.151), then stop it from updating back to 0.2.152:

```bash
mkdir -p ~/.local/state/freenet
echo 0.2.152 > ~/.local/state/freenet/known_bad_version
```

Run this as the user that runs the node. This is the file the automatic rollback writes. The pin applies only to 0.2.152, so a later release will still install.

**If you run a virtual machine on a host that has AVX2,** you can instead expose the host's CPU features to the VM. In Proxmox, set the VM's CPU type to `host`. Containers already see the host's CPU, so this does not apply to them.

**New installs on these CPUs** will crash on first start for as long as 0.2.152 is the latest release.

## What went wrong

Freenet includes some C code through its dependencies, including the `ring` cryptography library and `zstd`. The Rust compiler's target settings do not control how that C code is compiled. The C compiler does, using the defaults of whichever one the build machine has installed.

Here is the sequence:

1. Our Linux x86_64 build ran on GitHub's `ubuntu-latest` runner. Between 0.2.150 and 0.2.151, that label moved from Ubuntu 24.04 to Ubuntu 26.04. On the new image, the packages we install come from Ubuntu's `amd64v3` variant, which targets CPUs with AVX2. We did not choose this and were not notified by anything in our build.
2. 0.2.151 was built on the new image and was still fine. Our build cache matched exactly, so it reused C code compiled earlier by GCC 13.3.
3. 0.2.152 updated two dependencies. The cache no longer matched exactly, so the C code was rebuilt, this time by GCC 15.2. The result contains AVX2 and BMI2 instructions.
4. The first thing to crash is `OPENSSL_cpuid_setup`, the function in `ring` that checks which instructions the CPU supports. `ring` is careful to use advanced instructions only after that check, but here the check itself had been compiled with AVX. It runs during the first encrypted connection, which on a normal node happens during startup.

We inferred the compiler's default from the instructions in the binary and the package names in the build log. We did not query that compiler directly.

## Why our release checks missed it

We run several checks before and after a release, including a 30-minute soak on a real home network and canary tests of the updater. They all passed, because they all ran on CPUs with AVX2. They test whether the software works on the machines we have, and every one of those machines can run these instructions.

Three other things made it harder to see:

- **Nothing stated our minimum CPU.** Our documentation never said which CPUs Freenet supports, so no check could have been written against it.
- **The cache hid the cause.** The runner changed before 0.2.151, and the damage appeared only in the next release that changed a dependency.
- **The crash is invisible to our telemetry.** A node that dies before telemetry starts sends nothing, and a rollback does not report itself. A user told us before our monitoring did.

## How many peers were affected

We do not have an exact number. Our telemetry does not record CPU features, so we can only estimate from which peers appear and disappear. These figures come from sampled 10-minute windows and an hourly presence archive, covering about 21 hours after the release. Peers with telemetry turned off are not counted.

- **The network did not visibly shrink.** Hourly peer counts after the release were 0.989 of the same hours a week earlier. After 0.2.151 that ratio was 0.991. About 1,000 peers were visible in each 10-minute sample.
- **Departures were close to the usual range for a release.** Of 1,137 peers present in the hour before the release, 95 (8.36%) were not seen between 4 and 20 hours after it. For 0.2.151 that figure was 106 of 1,191 (8.90%). It was somewhat higher than the 5.95% to 7.36% seen for 0.2.145 to 0.2.150, which leaves room for about 20 lost peers. One wider measure does stand out: of peers seen at any point in the previous 24 hours, 24.25% had gone, against 15.24% to 20.05% for earlier releases. Short-lived peers drive that figure and it was already rising before the release, so we cannot say how much of it is this bug.
- **Some peers stayed on 0.2.151.** 21 hours after the release, 53 of 978 sampled peers were still on 0.2.151. A node that rolled back would look like this, because it never gets far enough on 0.2.152 to report that version. For comparison, 5 of 911 peers were on the version before 0.2.151 at about 31 hours after that release. The times differ and slow updaters explain some of the 53, so this is suggestive only.

Adding those two groups gives an upper estimate of about 70 peers, or 7% of the network. The real number could be much lower. This is an estimate and should be read as one.

## What we are changing

We looked for changes that make this class of mistake fail automatically, without adding manual steps to a release.

- **Fixing the build** ([#6061](https://github.com/freenet/freenet-core/pull/6061), in review). The build job now names Ubuntu 24.04 explicitly, sets the C compiler's target to baseline x86-64, and discards the old cache.
- **Failing the build on a repeat.** The same change adds a check that disassembles a sample of C functions from `ring` and `zstd` in the finished binaries, and fails if they contain AVX or BMI instructions. It fails on the shipped 0.2.152 binaries and passes on 0.2.151. It samples specific functions, so it detects a wrong C compiler setting and would not detect every possible cause.

We also plan the following. None of these has been done yet:

- Name exact versions for the other build machines, so that a change of image arrives as a visible code change.
- Run our existing pre-release canary under an emulated older CPU, if its time limits allow for the slowdown. This would test real startup on a CPU without AVX2.
- Report rollbacks in telemetry, along with whether a node's CPU has AVX2, so that the next question of this kind can be answered directly.
- State the minimum supported CPU in our documentation.

We are sorry for the disruption, and thanks to the user who reported it.
