---
title: "How fast are the peers stuck on old Freenet versions disappearing?"
date: 2026-10-10
description: "Freenet 0.2.120 and 0.2.121 shipped with a broken auto-updater. Two months of telemetry snapshots show the peers left on them shrinking by under 1% a day."
---

In early August 2026, Freenet releases 0.2.120 and 0.2.121 shipped with auto-update broken. A peer running either version cannot fetch a newer release by itself. Its operator has to notice and reinstall by hand. On 13 August, 864 of the roughly 1,800 peers reporting telemetry were on one of those two versions: 812 on 0.2.120 and 52 on 0.2.121.

This post looks at how quickly that group has shrunk, and what the rate implies for the coming months.

## The counts

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

## The rate

Fitting an exponential curve to the points from 14 August to the 10 October count taken before the release gives a decline of about 0.7% of the group per day. That is a half-life of about 96 days. If the rate holds, about 220 peers will still be on these versions on 1 January 2027 and about 115 at the end of March 2027.

Three choices in that fit need stating:

- **The 13 August point is left out.** The drop from 864 to 647 in one day is far larger than any later change, and the 13 August figure came from a different capture with a different way of counting peers, so the two are not directly comparable. Including it would make the fit describe that first day, not the following two months.
- **The October 340 is left out.** It was taken 1.5 hours after v0.2.143 changed how the network treats these peers (see below). One reading that soon after a release cannot separate a trend from the effect of the release.
- **Fitting only the August points gives the wrong answer.** The five points from 14 to 24 August alone give 1.6% per day, which predicts about 256 peers by 10 October. The measured count was 407, from a group that is, if anything, larger. Ten days of snapshots that each vary by about 30 peers are not enough to estimate a rate this slow.

A separate August estimate followed individual peers instead of comparing totals: of 540 peers on the stuck versions on 21 August, 14 (2.6%) were on a newer version 79 hours later. That is about 0.8% per day, a half-life of about 90 days. All of these agree on the conclusion: the group shrinks over months, not weeks.

A constant proportional rate also means the count never reaches zero. It keeps falling by the same fraction, so the last few dozen peers take as long to halve as the first several hundred did. On the fitted rate the group would drop below 50 peers in mid-2027.

The group is also partly replenished. Of the stuck peers seen on 24 August, 7.5% had not been seen three days earlier.

## Why so few of them upgrade

The clearest number is a comparison across a single release. When v0.2.129 shipped, 72% of the 916 peers on the then-current 0.2.128 moved to the new version within 9 hours. Over the same window, 0.4% of the 541 peers on 0.2.120 moved to any other version. Across the next release, v0.2.130, the figures over 42 hours were 74.6% and 2.1%. Both groups were counted the same way in the same windows, so the difference is a property of the peers, not of the measurement.

These machines do restart. In one 3.7-hour window, peers on 0.2.120 logged 111 startup events. They come back up on 0.2.120 each time.

The platform split explains why. Platform is only reported when a peer starts up, so it can only be measured for peers that restarted during a window. Among those, about 80% of the 0.2.120 peers ran Windows, against about 40% of peers on the current version at the time. Restart-observed samples over-represent machines that restart often, so the 80% is probably too high in absolute terms, but the comparison holds: Windows is about twice as common among the stuck peers.

On Linux, the systemd service runs `freenet update` after the node exits with an error, through an `ExecStopPost` hook. That hook is what moved some peers off the broken versions in the first weeks. Windows has no equivalent: nothing runs the updater after a failed exit ([#5228](https://github.com/freenet/freenet-core/issues/5228)). A Windows peer on 0.2.120 restarts on 0.2.120 indefinitely.

## What v0.2.143 changed

Release v0.2.143, cut on 10 October, raised the minimum version that peers accept in the connection handshake to 0.2.122 ([#5832](https://github.com/freenet/freenet-core/pull/5832)). Peers on 0.2.120 and 0.2.121 can no longer connect to current peers. This does not upgrade them. It separates them from the rest of the network, which makes the problem visible to their operators.

In the hours after the release, the gateways refused roughly 1,500 to 2,500 connection attempts per hour from these old peers. That is a negligible load for a gateway.

Before the release, the stuck peers did little harm to the rest of the network. In August they had normal memory use and normal traffic and produced no protocol errors. Transfers to 0.2.120 peers failed about 1.1 times as often as transfers to current peers. The 21 peers on 0.2.121 were worse, at about 2.4 times. The cost of leaving them connected was that they could not receive security fixes.

## Limits of this data

- Raw telemetry is kept for only about three days, so there is no continuous history. Each point is a separate snapshot taken when someone measured it, and the August points were counted with methods that improved over the month.
- A peer only appears if it is running and sends telemetry during the window. A peer that is switched off that day is not in the count, whatever version it has installed.
- The October points count a wider group than the August ones, as noted above.
- Six fitted points spread unevenly over two months support "months, and probably a long tail", not a precise date.

Fixing #5228, so that Windows installs also update themselves after a failed exit, would stop a future broken release from stranding peers the same way.
