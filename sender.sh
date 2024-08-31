#!/bin/bash

# Path to your .env file
ENV_FILE="./envs/sender/.env"

# Check if .env file exists
if [ -f "$ENV_FILE" ]; then
    # Export variables from .env file
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

# Variables
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M")
ZIP_FILE="backup_$TIMESTAMP.zip"
DUMP_FILE="$BACKUP_DIR/dump_$TIMESTAMP.sql"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Send telegram notification on progress start point
send_telegram_notification "Backup Progress started on sender machince
time: $TIMESTAMP"

# Dump PostgreSQL database using Docker
sudo docker exec -t "$DOCKER_CONTAINER_NAME" pg_dumpall -c -U "$DB_USER" > "$DUMP_FILE"

# Check if dump command failed
if [ $? -ne 0 ]; then
	send_telegram_notification "Backup creation Failed (db dump) on sender server at time: $TIMESTAMP"
	exit 1
fi

# Create a ZIP file containing the database dump and media files
zip -r "$BACKUP_DIR/$ZIP_FILE" "$DUMP_FILE" "$MEDIA_DIR" "$MIGRATION_DIR"

# Check if zip command failed
if [ $? -ne 0 ]; then
	send_telegram_notification "Backup creation Failed (zip) on sender server at time: $TIMESTAMP"
    exit 1
fi

# Send telegram notification that backup was created successfully
send_telegram_notification "Transfer backup progress started from sender server at time: $TIMESTAMP"

# Transfer the backup to the remote server using scp with SSH key and skip host key checking
scp -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" "$BACKUP_DIR/$ZIP_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR"

# Check if scp command failed
if [ $? -ne 0 ]; then
	send_telegram_notification "Backup transfer failed (scp) on sender server at time: $TIMESTAMP"
    exit 1
else
	# Get details of the transferred files
    	FILE_DETAILS=$(ls -lh "$BACKUP_DIR/$ZIP_FILE")

    	# Send a success notification with file details
    	send_telegram_notification "Backup transfer completed successfully at time: $TIMESTAMP. Transferred files:
	$FILE_DETAILS"
fi
