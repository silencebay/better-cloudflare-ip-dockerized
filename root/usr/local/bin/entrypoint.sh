#!/bin/bash

# Set default cron schedule if not provided
CRON="${CRON:-0 */6 * * *}"

# Create cron entry
echo "$CRON /usr/bin/flock -n /tmp/tasks.lock /app/entrypoint.sh run > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root

if [ "$1" = "run" ]; then
    # Get enabled tasks from environment variable
    ENABLED_TASKS=${ENABLED_TASKS:-"gist"}

    # Convert comma-separated string to array
    IFS=',' read -ra TASK_ARRAY <<< "$ENABLED_TASKS"

    # Execute each enabled task
    for task in "${TASK_ARRAY[@]}"; do
        task_script="/app/tasks/${task}.sh"
        if [ -f "$task_script" ]; then
            echo "[$(date)] Executing task: $task"
            bash "$task_script"
        else
            echo "[$(date)] Warning: Task script not found: $task_script"
        fi
    done
else
    # Start crond in foreground
    crond -f -d 8
fi
