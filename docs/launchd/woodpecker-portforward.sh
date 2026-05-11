#!/bin/bash
# Persistent SSH local-forward of the Woodpecker gRPC port (cluster
# 10.106.114.134:9000) onto 127.0.0.1:9000, so the local woodpecker-agent
# can dial the server. launchd restarts this script if SSH dies; we use
# foreground ssh (no -f) so launchd sees the actual lifetime.
#
# Why SSH and not `kubectl port-forward`? kubectl under launchd was hanging
# on an early `open()` syscall before reaching the network — likely a TTY /
# Privacy & Security oddity. SSH has no such interaction with launchd.
set -u

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
export HOME="/Users/dong-hoshin"

echo "[$(date '+%F %T')] starting ssh tunnel (PID $$)"

# Match the existing k8s-API tunnel's settings (lymphhub_neunexus key,
# StrictHostKeyChecking disabled, ubuntu@10.200.0.1 over the WireGuard mesh).
# ExitOnForwardFailure makes launchd restart us if the port is already taken.
# ServerAlive options keep the tunnel from silently going stale.
exec /usr/bin/ssh \
    -i /Users/dong-hoshin/Documents/dev/neunexus/secret/lymphhub_neunexus \
    -o StrictHostKeyChecking=no \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -N \
    -L 127.0.0.1:9000:10.106.114.134:9000 \
    ubuntu@10.200.0.1 -p 22 </dev/null
