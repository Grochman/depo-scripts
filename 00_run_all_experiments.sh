#!/bin/bash

# Verify required files exist
WORKLOADS_FILE="workloads_list.txt"
CONFIG_FILE="config.env"

if [ ! -f "$WORKLOADS_FILE" ]; then
    echo "ERROR: Workloads list file not found. Run 02_generate_workloads.sh first."
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Calibration configuration file not found. Run 01_calibrate.sh first."
    exit 1
fi

# Define test parameters
WINDOWS=(100 200 400 800 1600 3200 6400)
INTERVALS=(10 20 40 80)

TOTAL_ESTIMATED_RUNS=$(( ${#WINDOWS[@]} * ${#INTERVALS[@]} * 27 ))
echo "Starting test execution."
echo "Total estimating single workload runs: $TOTAL_ESTIMATED_RUNS"
echo "Estimated completion time: ~50 hours."

echo "Starting in 5 seconds..."
sleep 5

# Nested iteration: Windows -> Intervals -> Workload List
for WINDOW in "${WINDOWS[@]}"; do
    for INTERVAL in "${INTERVALS[@]}"; do
        
        echo "## STARTING BATCH: Window=${WINDOW}ms, Interval=${INTERVAL}s"
        
        # Read workloads file line by line
        while IFS="," read -r W_ID MODEL1 MODEL2 MODEL3; do
            # Execute workload runner script with parameters
            bash ./03_run_single_workload.sh "$WINDOW" "$INTERVAL" "$W_ID" "$MODEL1" "$MODEL2" "$MODEL3"
            
            # Cooldown delay between workloads to allow Docker and system bounds to reset.
            sleep 5
        done < "$WORKLOADS_FILE"
        
    done
done

echo "=========================================================="
echo "All tests have been completed successfully."
echo "=========================================================="
