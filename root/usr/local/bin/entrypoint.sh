#!/bin/bash

# Set default cron schedule if not provided
CRON="${CRON:-0 */6 * * *}"

# Create cron entry
echo "$CRON /usr/bin/flock -n /tmp/tasks.lock /app/entrypoint.sh run > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root

if [ "$1" = "run" ]; then
    # Run the core task
    /app/tasks/test.sh

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
    # Start crond in foreground
    crond -f -d 8
fi
