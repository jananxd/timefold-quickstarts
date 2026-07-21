#!/bin/bash
#
# Heap Monitor for Java/Quarkus applications
#
# Usage:
#   ./heap_monitor.sh           # Auto-detect PID, monitor every 5s
#   ./heap_monitor.sh -p 12345  # Specify PID
#   ./heap_monitor.sh -i 2      # Monitor every 2 seconds
#   ./heap_monitor.sh -g        # Trigger GC before each measurement
#   ./heap_monitor.sh -once     # Single measurement
#

set -e

INTERVAL=5
TRIGGER_GC=false
ONCE=false
PID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pid) PID="$2"; shift 2 ;;
        -i|--interval) INTERVAL="$2"; shift 2 ;;
        -g|--gc) TRIGGER_GC=true; shift ;;
        -once|--once) ONCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [-p PID] [-i INTERVAL] [-g] [-once]"
            echo "  -p PID        Java process PID"
            echo "  -i INTERVAL   Seconds between measurements (default: 5)"
            echo "  -g            Trigger GC before each measurement"
            echo "  -once         Single measurement then exit"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$PID" ]]; then
    echo "Searching for Java/Quarkus process..."
    PID=$(jps -l 2>/dev/null | grep -iE "(quarkus|employee)" | head -1 | awk '{print $1}')
    if [[ -z "$PID" ]]; then
        echo "Could not find Java process. Available:"
        jps -l
        echo ""
        echo "Specify PID with: $0 -p <PID>"
        exit 1
    fi
    echo "Found PID: $PID"
fi

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Process $PID not found"
    exit 1
fi

get_heap_mb() {
    jstat -gc "$PID" 2>/dev/null | tail -1 | awk '{printf "%.0f", ($3 + $4 + $6 + $8) / 1024}'
}

trigger_gc() {
    jcmd "$PID" GC.run >/dev/null 2>&1 || true
    sleep 0.5
}

echo ""
echo "========================================"
echo "Heap Monitor - PID: $PID"
echo "========================================"
echo "Interval: ${INTERVAL}s | GC trigger: $TRIGGER_GC"
echo ""

if $TRIGGER_GC; then
    echo "Triggering initial GC..."
    trigger_gc
fi

BASELINE=$(get_heap_mb)
echo "Baseline: ${BASELINE} MB"
echo ""

if $ONCE; then
    exit 0
fi

printf "%-12s %-12s %-12s %-20s\n" "Time" "Heap (MB)" "Delta (MB)" "Status"
echo "------------------------------------------------------------"

PREV_HEAP=$BASELINE

while true; do
    if $TRIGGER_GC; then
        trigger_gc
    fi

    CURRENT=$(get_heap_mb)

    if [[ -z "$CURRENT" ]] || [[ "$CURRENT" == "0" ]]; then
        echo "Process ended or not accessible"
        exit 1
    fi

    DELTA=$((CURRENT - BASELINE))
    CHANGE=$((CURRENT - PREV_HEAP))

    if [[ $CURRENT -le $((BASELINE + BASELINE / 20)) ]]; then
        STATUS="BASELINE"
    elif [[ $CHANGE -lt -5 ]]; then
        STATUS="recovering ($CHANGE)"
    elif [[ $CHANGE -gt 5 ]]; then
        STATUS="growing (+$CHANGE)"
    else
        STATUS="stable"
    fi

    TIME=$(date '+%H:%M:%S')
    printf "%-12s %-12s %+-12s %-20s\n" "$TIME" "$CURRENT" "$DELTA" "$STATUS"

    PREV_HEAP=$CURRENT
    sleep "$INTERVAL"
done
