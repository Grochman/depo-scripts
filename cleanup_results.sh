#!/bin/bash

# ==============================================================================
# RESULT CLEANUP SCRIPT
# Lists all result folders and deletes selected ones via sudo DEPO.
# ==============================================================================

REPO_DIR="/home/macierz/s193246/repos/split"
DEPO_BIN="/home/macierz/s193246/local/bin/DEPO"
DELETE_SCRIPT="/home/macierz/s193246/depo-scripts/_delete_results.sh"

# Find all result, debug, and raw experiment folders
mapfile -t FOLDERS < <(ls -dt "$REPO_DIR"/{res_*,debug_*,gpu_experiment_*,cpu_experiment_*} 2>/dev/null)

if [ ${#FOLDERS[@]} -eq 0 ]; then
    echo "No result folders found in $REPO_DIR."
    exit 0
fi

# Print numbered list with sizes
echo "============================================"
echo " RESULT FOLDERS IN: $REPO_DIR"
echo "============================================"
for i in "${!FOLDERS[@]}"; do
    SIZE=$(du -sh "${FOLDERS[$i]}" 2>/dev/null | cut -f1)
    printf "  [%3d]  %-10s  %s\n" "$((i+1))" "$SIZE" "$(basename "${FOLDERS[$i]}")"
done
echo "============================================"
echo ""
echo "Enter numbers to DELETE (space-separated), or:"
echo "  'all'  to delete everything"
echo "  'q'    to quit"
echo ""
read -rp "Your choice: " INPUT

if [[ "$INPUT" == "q" ]]; then
    echo "Aborted."
    exit 0
fi

# Build the list of folders to delete
TO_DELETE=()
if [[ "$INPUT" == "all" ]]; then
    TO_DELETE=("${FOLDERS[@]}")
else
    for NUM in $INPUT; do
        IDX=$((NUM - 1))
        if [[ "$IDX" -ge 0 && "$IDX" -lt ${#FOLDERS[@]} ]]; then
            TO_DELETE+=("${FOLDERS[$IDX]}")
        else
            echo "WARNING: '$NUM' is out of range, skipping."
        fi
    done
fi

if [ ${#TO_DELETE[@]} -eq 0 ]; then
    echo "Nothing selected. Aborted."
    exit 0
fi

# Confirm before deleting
echo ""
echo "The following folders will be PERMANENTLY DELETED:"
for F in "${TO_DELETE[@]}"; do
    echo "  - $(basename "$F")"
done
echo ""
read -rp "Are you sure? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

# Generate the deletion script to be run via sudo DEPO
cat << EOF > "$DELETE_SCRIPT"
#!/bin/bash
$(for F in "${TO_DELETE[@]}"; do echo "rm -rf \"$F\""; done)
EOF
chmod +x "$DELETE_SCRIPT"

echo ""
echo "Running deletion via sudo DEPO..."
sudo "$DEPO_BIN" "$DELETE_SCRIPT"

echo "Done."
