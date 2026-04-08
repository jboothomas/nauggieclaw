# NauggieClaw Debug Checklist

## Quick Status Check

```bash
# 1. Is the service running?
launchctl list | grep nauggieclaw
# Expected: PID  0  com.nauggieclaw (PID = running, "-" = not running)

# 2. Any running containers?
docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep nauggieclaw

# 3. Recent errors in service log?
grep -E 'ERROR|WARN' logs/nauggieclaw.log | tail -20

# 4. Are channels connected?
grep -E 'Connected|Connection closed|channel.*ready' logs/nauggieclaw.log | tail -5

# 5. Are groups loaded?
grep 'groupCount' logs/nauggieclaw.log | tail -3
```

## Known Issues

### 1. Kubernetes image GC deletes nauggieclaw-agent image

**Symptoms**: `Container exited with code 125: pull access denied for nauggieclaw-agent` — the image disappears overnight.

**Cause**: Rancher Desktop enables Kubernetes by default. The kubelet GCs images when disk usage exceeds 85%. Ephemeral containers (run-and-exit) are never protected.

**Fix**: Disable Kubernetes if you don't need it:
```bash
rdctl set --kubernetes-enabled=false
./container/build.sh
```

**Diagnosis**:
```bash
grep -i "nauggieclaw" ~/Library/Logs/rancher-desktop/k3s.log
grep -E "image found|image NOT found|image missing" logs/nauggieclaw.log
```

### 2. IDLE_TIMEOUT == CONTAINER_TIMEOUT (both 30 min)

Both timers fire at the same time, so containers always exit via SIGKILL (code 137) instead of graceful shutdown. Set `IDLE_TIMEOUT` shorter than `CONTAINER_TIMEOUT` in `.env`.

## Auggie Auth Issues

```bash
# Check if AUGMENT_SESSION_AUTH is set
grep AUGMENT_SESSION_AUTH .env 2>/dev/null || echo "not in .env"
echo "${AUGMENT_SESSION_AUTH:+set}" || echo "not in env"

# Verify auggie is logged in on the host
auggie token print 2>&1 | head -3

# Re-authenticate
auggie login

# Check that token injection worked (look for auth in container log)
grep -E 'AUGMENT_SESSION_AUTH|resolveAugmentSessionAuth|token' logs/nauggieclaw.log | tail -5
```

## Session Issues

```bash
# List session files for a group
ls -la data/sessions/<group>/.augment/sessions/

# Inspect a session file (replace <sessionId>)
cat data/sessions/<group>/.augment/sessions/<sessionId>.json | python3 -m json.tool | head -30

# Clear a stale session (host will start fresh on next message)
sqlite3 store/messages.db "DELETE FROM sessions WHERE group_folder = '<group>';"

# Check if session was auto-cleared after error
grep -E 'Stale session|Clearing session|session.*error' logs/nauggieclaw.log | tail -10
```

## Container Timeout Investigation

```bash
# Check for recent timeouts
grep -E 'Container timeout|timed out' logs/nauggieclaw.log | tail -10

# Read the most recent container log
ls -lt groups/*/logs/container-*.log | head -5
cat groups/<group>/logs/container-<timestamp>.log

# Check if retries were scheduled
grep -E 'Scheduling retry|retry|Max retries' logs/nauggieclaw.log | tail -10
```

## Agent Not Responding

```bash
# Check if messages are being received from channels
grep 'New messages' logs/nauggieclaw.log | tail -10

# Check if container was spawned
grep -E 'Processing messages|Spawning container|Starting container' logs/nauggieclaw.log | tail -10

# Check lastAgentTimestamp vs latest message timestamp
sqlite3 store/messages.db "SELECT chat_jid, MAX(timestamp) as latest FROM messages GROUP BY chat_jid ORDER BY latest DESC LIMIT 5;"
```

## Container Mount Issues

```bash
# Check mount validation logs
grep -E 'Mount validated|Mount.*REJECTED' logs/nauggieclaw.log | tail -10

# Verify the mount allowlist
cat ~/.config/nauggieclaw/mount-allowlist.json

# Check group's container_config
sqlite3 store/messages.db "SELECT name, container_config FROM registered_groups;"

# Test mounts directly
docker run -i --rm --entrypoint ls nauggieclaw-agent:latest /workspace/extra/
```

## Channel Auth Issues

```bash
# Check if QR code was requested (auth expired)
grep 'QR\|authentication required' logs/nauggieclaw.log | tail -5

# Check auth files
ls -la store/auth/

# Re-authenticate
npm run auth
```

## Service Management

```bash
# Restart (macOS)
launchctl kickstart -k gui/$(id -u)/com.nauggieclaw

# View live logs
tail -f logs/nauggieclaw.log

# Stop
launchctl bootout gui/$(id -u)/com.nauggieclaw

# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nauggieclaw.plist

# Rebuild after code changes
npm run build && launchctl kickstart -k gui/$(id -u)/com.nauggieclaw
```
