#!/bin/bash

# Set default cron schedule if not provided
CRON="${CRON:-0 */6 * * *}"

if [ "$1" = "run" ]; then
    # Get enabled tasks from environment variable
    ENABLED_TASKS=${ENABLED_TASKS:-"gist"}

    # Convert comma-separated string to array
    IFS=',' read -ra TASK_ARRAY <<< "$ENABLED_TASKS"

    # Execute each enabled task
    for task in "${TASK_ARRAY[@]}"; do
        # 首先检查是否存在自定义 task
        if [ -f "/app/tasks/custom/${task}.sh" ]; then
            echo "[$(date)] Executing custom task: $task"
            bash "/app/tasks/custom/${task}.sh"
        # 如果没有自定义 task，则执行默认 task
        elif [ -f "/app/tasks/${task}.sh" ]; then
            echo "[$(date)] Executing default task: $task"
            bash "/app/tasks/${task}.sh"
        else
            echo "[$(date)] Warning: Task script not found: $task"
        fi
    done
else
    # Only create cron entry when starting crond
    CRON_FILE="/etc/crontabs/root"
    CRON_ENTRY="$CRON /usr/bin/flock -n /tmp/tasks.lock /usr/local/bin/entrypoint.sh run > /proc/1/fd/1 2>/proc/1/fd/2"
    
    # Check if crontab needs to be updated
    if [ ! -f "$CRON_FILE" ] || ! grep -Fxq "$CRON_ENTRY" "$CRON_FILE"; then
        echo "$CRON_ENTRY" > "$CRON_FILE"
        echo "[$(date)] Updated crontab configuration"
    fi

    # Start crond in foreground
    exec crond -f -d 8
fi
