#!/bin/bash

# Source logging functions
source /app/lib/logging.sh

# Set default cron schedule if not provided
CRON="${CRON:-0 */6 * * *}"

if [ "$1" = "run" ]; then
    # Get enabled tasks from environment variable
    ENABLED_TASKS=${ENABLED_TASKS:-"gist"}
    # Get retry count from environment variable, default to 3
    TASK_RETRY_COUNT=${TASK_RETRY_COUNT:-3}

    # Convert comma-separated string to array
    IFS=',' read -ra TASK_ARRAY <<< "$ENABLED_TASKS"

    # Execute each enabled task
    for task in "${TASK_ARRAY[@]}"; do
        task_script=""
        # 首先检查是否存在自定义 task
        if [ -f "/app/tasks/custom/${task}.sh" ]; then
            task_script="/app/tasks/custom/${task}.sh"
            info "Found custom task: $task"
        # 如果没有自定义 task，则执行默认 task
        elif [ -f "/app/tasks/${task}.sh" ]; then
            task_script="/app/tasks/${task}.sh"
            info "Found default task: $task"
        else
            warning "Task script not found: $task"
            continue # Skip to the next task if script not found
        fi

        attempt=1
        while [ $attempt -le $TASK_RETRY_COUNT ]; do
            info "Executing task: $task (Attempt $attempt/$TASK_RETRY_COUNT)"
            bash "$task_script"
            exit_code=$?

            if [ $exit_code -eq 0 ]; then
                info "Task $task completed successfully."
                break # Exit loop if successful
            else
                error "Task $task failed with exit code $exit_code."
                if [ $attempt -lt $TASK_RETRY_COUNT ]; then
                    info "Retrying task $task in 5 seconds..."
                    sleep 5
                else
                    error "Task $task failed after $TASK_RETRY_COUNT attempts."
                fi
            fi
            ((attempt++))
        done
    done
else
    # Only create cron entry when starting crond
    CRON_FILE="/etc/crontabs/root"
    CRON_ENTRY="$CRON /usr/bin/flock -n /tmp/tasks.lock /usr/local/bin/entrypoint.sh run > /proc/1/fd/1 2>/proc/1/fd/2"
    
    # Check if crontab needs to be updated
    if [ ! -f "$CRON_FILE" ] || ! grep -Fxq "$CRON_ENTRY" "$CRON_FILE"; then
        echo "$CRON_ENTRY" > "$CRON_FILE"
        info "Updated crontab configuration"
    fi

    # Start crond in foreground
    exec crond -f -d 8
fi
