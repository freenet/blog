---
title: "Freenet now disconnects peers stuck on old versions"
date: 2026-10-10
description: "From v0.2.143, updated peers refuse connections from peers older than 0.2.122. About 400 peers stuck on 0.2.120 and 0.2.121 are being cut off. Here is why, and what to do if yours is one of them."
---

Freenet v0.2.143, released on 10 October 2026, refuses connections to and from peers running any version older than 0.2.122. About 400 peers are still on such versions, almost all of them on 0.2.120 or 0.2.121, two releases that cannot update themselves. As the rest of the network updates, those peers lose their connections.

> **If you run Freenet and your node cannot connect,** check its version with `freenet --version`. If it is older than 0.2.122, run `freenet update`, or download and reinstall Freenet from [freenet.org](https://freenet.org).

## What changed

Every Freenet connection starts with a handshake in which each side states its version and the oldest version it will talk to. Release v0.2.143 raised that minimum to 0.2.122 ([#5832](https://github.com/freenet/freenet-core/pull/5832)). A node running 0.2.143 now refuses any connection with a peer older than 0.2.122, whichever side starts it.

Releases before 0.2.143 do not enforce the new minimum, so the cut-off spreads as the network updates. Four hours after the release, about two thirds of the peers seen were already on 0.2.143. The gateways run 0.2.143, so they already refuse the old peers: about 1,400 to 1,700 refused connection attempts per hour on nova's gateways. That is a negligible load.

## Why we did it

Releases 0.2.120 and 0.2.121 shipped with broken update detection: the node read the release tag (for example `v0.2.121`) as a version number, failed to parse it, and silently ignored every new release ([#5221](https://github.com/freenet/freenet-core/issues/5221)). A peer on either version never notices that a newer release exists. Its operator has to update it by hand.

That left a large group of peers that could not receive fixes, including security fixes. They did little harm to the rest of the network: in August they had normal memory use and normal traffic and produced no protocol errors. Transfers to 0.2.120 peers failed about 1.1 times as often as transfers to current peers, and the 21 peers on 0.2.121 were worse, at about 2.4 times. The problem was that they could not be updated, and, as the measurements below show, their number was falling only slowly.

## What happens to a stuck peer

Once nothing will connect to it, a stuck peer is isolated from the network.

The broken versions still contain a second, older update trigger that does not depend on the broken check. When a 0.2.120 or 0.2.121 node meets a peer whose minimum version is above its own, it records that it needs an update. If it then has no connections at all for six hours, it exits with a special "update needed" exit code and leaves the update to whatever started it:

- **Linux, installed as a service:** systemd runs `freenet update` when the node exits with that code, then restarts it.
- **Windows, installed normally:** Freenet starts at login through a small supervisor process (`freenet service run-wrapper`, which also shows the tray icon). It also runs `freenet update` on that exit code.
- **Run by hand** (for example `freenet network` in a terminal): nothing runs the update. The node stays cut off until its operator updates it.

So service installs on both Linux and Windows should update themselves within roughly six hours of losing their last connection. This is what the code says should happen. We have not yet seen it happen at scale, and telemetry over the next days will show how many of the 400 actually recover. Anyone whose node is still not connecting should update by hand as described above.

This also explains why the stuck group was mostly Windows. In August, about 80% of the stuck peers that restarted were on Windows. On Linux, systemd runs `freenet update` after any failed exit, so a crash or an error also triggered an update, and that moved some Linux peers off the broken versions. The Windows supervisor runs the update only for the "update needed" exit code, which a stuck node never produced while it still had connections. Cutting the stuck peers off is what makes them produce it.

## The trade-off

About 400 peers lose the network. They were not receiving fixes anyway, and their operators now get a visible symptom (no connections) where before nothing looked wrong. Their retries cost the gateways almost nothing.

## How fast the stuck group was shrinking

Before v0.2.143, the stuck group was shrinking by itself, but slowly. This section is the evidence for that.

### The counts

Each number below is the count of distinct peers reporting one of the stuck versions during a telemetry window on that day.

| Date | Peers | Versions counted |
|---|---:|---|
| 13 August | 864 | 0.2.120 (812) + 0.2.121 (52) |
| 14 August | 647 | 0.2.120 + 0.2.121 |
| 15 August | 622 | 0.2.120 + 0.2.121 |
| 16 August | 587 | 0.2.120 + 0.2.121 |
| 21 August | 540 | 0.2.120 + 0.2.121 |
| 24 August | 554 | 0.2.120 + 0.2.121 |
| 10 October, before the v0.2.143 release | 407 | every version below 0.2.122 |
| 10 October, 1.5 hours after the release | 340 | every version below 0.2.122 |

The two October counts measure a slightly larger group than the August ones. They include every peer older than 0.2.122, not only 0.2.120 and 0.2.121. On 12 August about 4% of the network, roughly 70 peers, had never reached 0.2.120, so the October points overstate the stuck group a little.

{{< include "chart.html" >}}

### The rate

Fitting an exponential curve to the points from 14 August to the 10 October count taken before the release gives a decline of about 0.7% of the group per day. That is a half-life of about 96 days. If the rate holds, about 220 peers will still be on these versions on 1 January 2027 and about 115 at the end of March 2027.

Three choices in that fit need stating:

- **The 13 August point is left out.** The drop from 864 to 647 in one day is far larger than any later change, and the 13 August figure came from a different capture with a different way of counting peers, so the two are not directly comparable. Including it would make the fit describe that first day, not the following two months.
- **The October 340 is left out.** It was taken 1.5 hours after v0.2.143 was released. One reading that soon after a release cannot separate a trend from the effect of the release.
- **Fitting only the August points gives the wrong answer.** The five points from 14 to 24 August alone give 1.6% per day, which predicts about 256 peers by 10 October. The measured count was 407, from a group that is, if anything, larger. Ten days of snapshots that each vary by about 30 peers are not enough to estimate a rate this slow.

A separate August estimate followed individual peers instead of comparing totals: of 540 peers on the stuck versions on 21 August, 14 (2.6%) were on a newer version 79 hours later. That is about 0.8% per day, a half-life of about 90 days. All of these agree on the conclusion: the group shrinks over months, not weeks.

A constant proportional rate also means the count never reaches zero. It keeps falling by the same fraction, so the last few dozen peers take as long to halve as the first several hundred did. On the fitted rate the group would drop below 50 peers in mid-2027.

The group is also partly replenished. Of the stuck peers seen on 24 August, 7.5% had not been seen three days earlier.

### Why so few of them upgrade

The clearest number is a comparison across a single release. When v0.2.129 shipped, 72% of the 916 peers on the then-current 0.2.128 moved to the new version within 9 hours. Over the same window, 0.4% of the 541 peers on 0.2.120 moved to any other version. Across the next release, v0.2.130, the figures over 42 hours were 74.6% and 2.1%. Both groups were counted the same way in the same windows, so the difference is a property of the peers, not of the measurement.

These machines do restart. In one 3.7-hour window, peers on 0.2.120 logged 111 startup events. They come back up on 0.2.120 each time.

The platform split is the main reason, as described above. Platform is only reported when a peer starts up, so it can only be measured for peers that restarted during a window. Among those, about 80% of the 0.2.120 peers ran Windows, against about 40% of peers on the current version at the time. Restart-observed samples over-represent machines that restart often, so the 80% is probably too high in absolute terms, but the comparison holds: Windows is about twice as common among the stuck peers.

### Limits of this data

- Raw telemetry is kept for only about three days, so there is no continuous history. Each point is a separate snapshot taken when someone measured it, and the August points were counted with methods that improved over the month.
- A peer only appears if it is running and sends telemetry during the window. A peer that is switched off that day is not in the count, whatever version it has installed.
- The October points count a wider group than the August ones, as noted above.
- Six fitted points spread unevenly over two months support "months, and probably a long tail", not a precise date.

The projection describes what would have happened without the cut-off. From 10 October the stuck group should shrink much faster, as isolated service installs update themselves, but a group of hand-run nodes will remain until their operators notice.
