# NetScope

NetScope is a local macOS network diagnosis utility. The first version is a CLI diagnostic engine that samples per-process network deltas and tells you whether one app is the likely source of current network pressure.

## Assumptions

- The first user is the person sitting at this Mac when the internet feels slow.
- The most valuable first answer is app-level attribution: "this app is using most upload/download right now."
- The app should report likelihood and evidence, not pretend to prove perfect causality.
- The first implementation can be a CLI because the diagnostic engine matters more than the menu bar shell.
- A future menu bar app should call the same `NetScopeCore` module rather than duplicating diagnosis logic.
- Avoiding Mac slowdown and battery drain is a hard product requirement.
- No backward compatibility is needed; this is a new hard-cutover project.

## Power Budget

NetScope uses two diagnostic paths:

- **Interactive observations** run when you open the popover. They sample per-app counters and read Wi-Fi link state.
- **Path checks** run only when you click refresh or use the status menu action. They reuse current app counters and run bounded gateway, public ping, and DNS probes.
- **Rolling app-counter samples** run at a conservative interval while the menu bar app is open. They sample per-app counters only.

NetScope does not run a daemon, launch agent, speed test loop, packet capture, or raw traffic logger. The menu bar app may store a bounded local baseline of aggregate per-app traffic rates so it can tell whether current app activity is unusual for this Mac.

Default power constraints live in `PowerBudget`:

- Background rolling samples are limited to app counters.
- Background active probes are disabled.
- `nettop` uses the minimum useful delta sample count.
- Ping uses at most two packets.
- Child commands are stopped if they exceed 10 seconds.
- Rolling app-counter samples run no more often than once per minute.
- Recent history is capped at 30 in-memory samples and 30 minutes.
- Learned baseline storage is capped at 80 app aggregates and 7 days.

Any feature that needs a tighter loop should be treated as a product decision, not a hidden implementation detail.

## Local Baseline Privacy

When the menu bar app is running, NetScope can learn a local baseline in `~/Library/Application Support/NetScope/traffic-baseline.json`.

The baseline stores only per-app aggregate counters:

- app display name
- sample count
- average incoming and outgoing bytes per second
- peak incoming and outgoing bytes per second
- first-seen and last-seen timestamps

It does not store packet contents, URLs, hostnames, remote IPs, browser tabs, DNS answers, or raw per-sample logs. The app includes a "Clear Learned Baseline" action that deletes the local baseline file.

## Current Diagnosis Inputs

- `/usr/bin/nettop` in per-process delta mode for current app traffic.
- `/sbin/ping` against `1.1.1.1` for latency and packet-loss context.
- `/sbin/route -n get default` during on-demand path checks to find the current gateway.
- `/usr/bin/dig +time=2 +tries=1 +short apple.com` during on-demand path checks for DNS timing.
- CoreWLAN Wi-Fi interface fields for RSSI, noise, link rate, and channel when macOS allows them.

## Run

```bash
swift run netScope
```

Run it while the connection feels slow. The output includes the current diagnosis, confidence level, evidence, and top network apps.

The command exits after one on-demand full-check snapshot.

## Menu Bar App

```bash
swift run NetScopeMenuBar
```

The menu bar app uses the same `NetScopeCore` diagnosis path. Opening the popover starts lightweight observation. Clicking refresh first captures a fresh app-counter + Wi-Fi observation, then runs a bounded path check: default gateway ping, public ping, and one DNS lookup. While the app is running, NetScope records rolling app-counter samples at the conservative interval in `PowerBudget.rollingAppCounterSampleSeconds`. Those rolling samples do not ping, run a speed test, inspect packets, or write raw logs.

Rolling app-counter samples also update the bounded local baseline. Path checks compare the current counters to that learned baseline but do not add duplicate app-counter samples.

The popover groups observed traffic into user apps, infrastructure, system services, and unknown background processes. It also shows a compact trend line from the bounded in-memory history.

To build a local `.app` bundle:

```bash
./scripts/package-app.sh
open .build/NetScope.app
```

## Product Scope

In scope for the first useful version:

- Identify the top network-using apps.
- Separate user apps from infrastructure, system services, and unknown background processes.
- Flag dominant upload pressure.
- Flag dominant download usage.
- Separate "one app stands out" from "network path looks slow."
- Localize on-demand path checks across gateway, public ping, and DNS.
- Show passive Wi-Fi signal/link health when macOS exposes it.
- Show a compact in-memory traffic trend.
- Keep confidence explicit.
- Keep diagnostics lightweight enough to run without noticeable Mac slowdown.
- Show a menu bar status state: normal, possible pressure, or likely issue.
- Keep a tiny in-memory rolling history during use so repeated app pressure can increase confidence.
- Raise displayed confidence when the same app repeatedly appears as the recent pressure source.
- Learn bounded local aggregate traffic baselines so current app traffic can be labeled as usual, newly active, or above usual.

Out of scope for now:

- Browser-tab-level attribution.
- Automatic killing or pausing apps.
- Deep packet inspection.
- App Store packaging.
- High-frequency passive monitoring.
- Packet-content or destination logging.
- Background ping/speed probes.
- Long `networkQuality` speed tests in the default diagnostic path.
- Persisted raw per-sample traffic logs.
