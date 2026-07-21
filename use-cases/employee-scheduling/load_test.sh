#!/bin/bash
#
# Load test for Employee Scheduling API (hits running dev server)
#
# Usage:
#   ./load_test.sh              # 20 iterations, 2s delay
#   ./load_test.sh -n 50        # 50 iterations
#   ./load_test.sh -d 5         # 5 second delay between requests
#   ./load_test.sh -w           # Wait for solve to complete before next
#   ./load_test.sh -c           # Cleanup jobs after each solve
#

API_URL="${API_URL:-http://localhost:8080}"
ITERATIONS=20
DELAY=2
WAIT_FOR_SOLVE=false
CLEANUP_AFTER_EACH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--iterations) ITERATIONS="$2"; shift 2 ;;
        -d|--delay) DELAY="$2"; shift 2 ;;
        -w|--wait) WAIT_FOR_SOLVE=true; shift ;;
        -c|--cleanup) CLEANUP_AFTER_EACH=true; shift ;;
        -u|--url) API_URL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [-n ITERATIONS] [-d DELAY] [-w] [-c]"
            echo "  -n  Number of iterations (default: 20)"
            echo "  -d  Delay between requests in seconds (default: 2)"
            echo "  -w  Wait for each solve to complete before next"
            echo "  -c  Cleanup (DELETE) job after each solve"
            echo "  -u  API URL (default: http://localhost:8080)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Sample payload matching Java domain model
PAYLOAD='{
  "employees": [
    {
      "name": "John Carlo Miel",
      "skills": ["Practice Manager", "Office Assistant", "Dispenser"],
      "unavailableDates": [],
      "undesiredDates": [],
      "desiredDates": []
    },
    {
      "name": "Tommy Shelby",
      "skills": ["Practice Manager", "Office Assistant", "Dispenser"],
      "unavailableDates": [],
      "undesiredDates": [],
      "desiredDates": []
    },
    {
      "name": "Tom Holland",
      "skills": ["Practice Manager", "Office Assistant", "Dispenser"],
      "unavailableDates": [],
      "undesiredDates": [],
      "desiredDates": []
    }
  ],
  "shifts": [
    {"id": "shift-0", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-1", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-2", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-3", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-4", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-5", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-6", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-7", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-8", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-9", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-10", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-11", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-12", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"},
    {"id": "shift-13", "start": "2026-07-16T08:30:00", "end": "2026-07-16T17:30:00", "location": "Main Office", "requiredSkill": "Practice Manager"}
  ]
}'

echo ""
echo "========================================"
echo "Load Test - Employee Scheduling API"
echo "========================================"
echo "URL: $API_URL"
echo "Iterations: $ITERATIONS"
echo "Delay: ${DELAY}s"
echo "Wait for solve: $WAIT_FOR_SOLVE"
echo "Cleanup after each: $CLEANUP_AFTER_EACH"
echo ""

# Check if server is running
if ! curl -s "$API_URL/schedules" > /dev/null 2>&1; then
    echo "ERROR: Server not responding at $API_URL"
    echo "Start with: mvn quarkus:dev"
    exit 1
fi

echo "Server is running. Starting load test..."
echo ""

printf "%-6s %-40s %-10s\n" "Iter" "Job ID" "Status"
echo "------------------------------------------------------------"

JOB_IDS=()

for i in $(seq 1 $ITERATIONS); do
    # Submit problem
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/schedules" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    JOB_ID=$(echo "$RESPONSE" | head -1)

    if [[ "$HTTP_CODE" == "200" ]]; then
        STATUS="submitted"
        JOB_IDS+=("$JOB_ID")
    else
        STATUS="ERROR ($HTTP_CODE)"
    fi

    printf "%-6s %-40s %-10s\n" "$i" "$JOB_ID" "$STATUS"

    # Wait for solve to complete if requested
    if $WAIT_FOR_SOLVE && [[ "$HTTP_CODE" == "200" ]]; then
        while true; do
            SOLVER_STATUS=$(curl -s "$API_URL/schedules/$JOB_ID/status" | grep -o '"solverStatus":"[^"]*"' | cut -d'"' -f4)
            if [[ "$SOLVER_STATUS" == "NOT_SOLVING" ]]; then
                break
            fi
            sleep 0.5
        done
        echo "       (solve completed)"
    fi

    # Cleanup if requested
    if $CLEANUP_AFTER_EACH && [[ "$HTTP_CODE" == "200" ]]; then
        curl -s -X DELETE "$API_URL/schedules/$JOB_ID" > /dev/null
        echo "       (cleaned up)"
    fi

    sleep "$DELAY"
done

echo "------------------------------------------------------------"
echo ""
echo "Load test complete. Created ${#JOB_IDS[@]} jobs."

# Ask about cleanup
if [[ ${#JOB_IDS[@]} -gt 0 ]] && ! $CLEANUP_AFTER_EACH; then
    echo ""
    read -p "Delete all jobs now? [y/N]: " CLEANUP
    if [[ "$CLEANUP" == "y" || "$CLEANUP" == "Y" ]]; then
        echo "Cleaning up..."
        for JOB_ID in "${JOB_IDS[@]}"; do
            curl -s -X DELETE "$API_URL/schedules/$JOB_ID" > /dev/null
            echo "  Deleted $JOB_ID"
        done
        echo "Done."
    else
        echo "Jobs left running. Clean up manually or restart server."
    fi
fi
