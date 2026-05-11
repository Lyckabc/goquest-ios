# Self-hosted macOS Woodpecker agent

The iOS pipeline (`.woodpecker.yml` at the repo root) needs a macOS box with
Xcode to run `xcodebuild`. The cluster's existing Woodpecker agents are Linux
pods, so we run a dedicated **self-hosted agent** on a Mac via `launchd`.

Single-machine setup, intended for the maintainer's own Mac. Multi-runner
fleet management is out of scope.

## Prerequisites

- macOS (Apple Silicon — `arm64`) with Xcode installed
- `kubectl` + the team's `kubeconfig-tunnel` (cluster admin access)
- The `ubuntu@10.200.0.1` SSH key checked in at
  `neunexus/secret/lymphhub_neunexus`
- `xcodegen` available on PATH (`brew install xcodegen`)
- WireGuard up so `10.200.0.1` is reachable (existing `wg-home.conf`)

## What gets installed

| Path | Purpose |
|------|---------|
| `~/.local/bin/woodpecker-agent` | Agent binary (v3.13.0 darwin arm64) |
| `~/.local/bin/woodpecker-portforward.sh` | SSH local-forward wrapper |
| `~/Library/LaunchAgents/home.toji.woodpecker-portforward.plist` | launchd: SSH tunnel `127.0.0.1:9000 → cluster gRPC` |
| `~/Library/LaunchAgents/home.toji.woodpecker-agent.plist` | launchd: agent itself |
| `~/Library/Application Support/Woodpecker/agent.conf` | Persisted agent ID |
| `~/Library/Logs/Woodpecker/*.log` | Stdout + stderr per agent |

## One-time install

```bash
# 1. Download the agent
curl -sL https://github.com/woodpecker-ci/woodpecker/releases/download/v3.13.0/woodpecker-agent_darwin_arm64.tar.gz \
  | tar -xz -C /tmp
mkdir -p ~/.local/bin
install -m 755 /tmp/woodpecker-agent ~/.local/bin/woodpecker-agent

# 2. Drop the SSH-tunnel wrapper (copy from this repo)
install -m 755 docs/launchd/woodpecker-portforward.sh ~/.local/bin/

# 3. Copy the launchd plists into place
cp docs/launchd/home.toji.woodpecker-portforward.plist ~/Library/LaunchAgents/
cp docs/launchd/home.toji.woodpecker-agent.plist ~/Library/LaunchAgents/

# 4. Provision the agent's data + log directories
mkdir -p ~/Library/Logs/Woodpecker \
         ~/Library/Application\ Support/Woodpecker \
         ~/Library/Caches/Woodpecker

# 5. Load both jobs
launchctl load -w ~/Library/LaunchAgents/home.toji.woodpecker-portforward.plist
launchctl load -w ~/Library/LaunchAgents/home.toji.woodpecker-agent.plist
```

## Verifying

```bash
# Tunnel up?
nc -zv 127.0.0.1 9000

# Agent up and registered?
tail -f ~/Library/Logs/Woodpecker/agent.err.log
# look for: "starting Woodpecker agent ... using platform 'darwin/arm64'
# running up to 2 pipelines in parallel"
```

In the Woodpecker UI, open `Admin → Agents` — a `mac-toji-arm64` entry with
the label `platform=darwin/arm64` should appear within ~10 seconds of the
launchd job starting.

Push a PR to `goquest-ios` and confirm Woodpecker fires the iOS pipeline
against this agent.

## Stopping

```bash
launchctl unload ~/Library/LaunchAgents/home.toji.woodpecker-agent.plist
launchctl unload ~/Library/LaunchAgents/home.toji.woodpecker-portforward.plist
```

## Why SSH and not `kubectl port-forward`?

`kubectl port-forward` hung on an early `open()` syscall when invoked from
the `launchd` background context — likely a TTY / Privacy & Security
quirk specific to launchd. The same command worked fine from a logged-in
shell. SSH local-forward to the master's WireGuard IP has no such issue,
and reuses the credential already used by the kube-API tunnel.

## Pipeline label routing

The agent advertises `platform=darwin/arm64`. The iOS `.woodpecker.yml`
matches that label so other Linux-only pipelines never get scheduled on
this agent. If you ever need to suspend iOS CI without uninstalling,
remove the label from `.woodpecker.yml` rather than killing the agent.
