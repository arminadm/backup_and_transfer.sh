#!/bin/bash


# Load environment variables from .env file
ENV_FILE="./envs/receiver/.env"

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo ".env file not found at $ENV_FILE"
    exit 1
fi

# Function to send a Telegram notification with retries
send_telegram_notification() {
    local message=$1
    local max_retries=10
    local retry_count=0
    local success=false

    if [ "$SEND_NOTIFICATION" = "true" ]; then
        while [ $retry_count -lt $max_retries ]; do
            response=$(curl --write-out "%{http_code}" --silent --output /dev/null \
                --get \
                --data-urlencode "chat_id=$TELEGRAM_CHAT_GROUP_ID" \
                --data-urlencode "message_thread_id=$TELEGRAM_THREAD_ID" \
                --data-urlencode "text=$message" \
                "$TELEGRAM_BYPASS_URL/bot$TELEGRAM_BOT_API_TOKEN/sendMessage")

            if [ "$response" -eq 200 ]; then
                success=true
                break
            else
                echo "Failed to send Telegram notification. Attempt $((retry_count+1)) of $max_retries. HTTP status code: $response"
                retry_count=$((retry_count+1))
                sleep 2  # Wait for 2 seconds before retrying
            fi
        done

        if [ "$success" = false ]; then
            echo "Failed to send Telegram notification after $max_retries attempts."
            exit 1  # Exit or handle the error appropriately
        fi
    fi
}

# Function to manage backups
manage_backups() {
    # Get the list of backup files, sorted by modification time (oldest first)
    backup_files=($(ls -1t "$BACKUP_DIR" | sort -n))

    # Initialize variables for the notification message
    deleted_files=""
    total_files=${#backup_files[@]}

    # If there are more than 5 backups, delete the oldest one(s)
    if [ $total_files -gt 5 ]; then
        files_to_delete=("${backup_files[@]:5}")
        for file in "${files_to_delete[@]}"; do
            rm -f "$BACKUP_DIR/$file"
            deleted_files+="$file\n"
        done
    fi

    # Prepare the notification message
    message="Backup Management Run Completed:
- Total backups before cleanup: $total_files
- Total backups after cleanup: ${#backup_files[@]:0:5}
- Deleted files:
$deleted_files"

    # Send the notification
    send_telegram_notification "$message"
}

# Run the backup management
manage_backups

