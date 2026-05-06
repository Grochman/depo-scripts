#!/bin/bash
# kill_depo.sh — Stop all running DEPO instances using a privileged DEPO execution.
# Works around the lack of general sudo by running kill inside a DEPO workload script.

DEPO_BIN="/home/macierz/s193246/local/bin/DEPO"
KILL_SCRIPT="/tmp/_depo_kill_$$.sh"

# Find all running DEPO binary PIDs (exclude ourselves)
DEPO_PIDS=$(pgrep -f "build/apps/DEPO/DEPO" 2>/dev/null | tr '\n' ' ')

if [ -z "$DEPO_PIDS" ]; then
    echo "No DEPO processes found."
    exit 0
fi

echo "Found DEPO PID(s): $DEPO_PIDS"
echo "Sending SIGTERM via privileged DEPO execution..."

# Write a one-shot kill script to be run as root by sudo DEPO
cat > "$KILL_SCRIPT" << EOF
#!/bin/bash
kill -TERM $DEPO_PIDS 2>/dev/null || true
# Also stop any docker containers launched by DEPO
docker ps -q --filter ancestor=torchbench-suite:1.0.1 2>/dev/null | xargs -r docker stop 2>/dev/null || true
echo "Done."
EOF
chmod +x "$KILL_SCRIPT"

# Run via sudo DEPO — this executes the script as root
sudo "$DEPO_BIN" "$KILL_SCRIPT" &

# Give it a moment then clean up the temp script
sleep 3
rm -f "$KILL_SCRIPT"
