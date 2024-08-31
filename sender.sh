#!/bin/bash

# Load environment variables from .env file
ENV_FILE="./envs/.env"

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo ".env file not found at $ENV_FILE"
    exit 1
fi

if [ ${WHO,,} != "sender" ]; then
	echo "sender script only works on sender machine: check WHO env"
	exit 1
fi

# Function to send a Telegram notification with retries
send_telegram_notification() {
    local message=$1
    local max_retries=10
    local retry_count=0

    if [ "$SEND_NOTIFICATION" = "true" ]; then
        while [ $retry_count -lt $max_retries ]; do
            response=$(curl --write-out "%{http_code}" --silent --output /dev/null \
                --get \
                --data-urlencode "chat_id=$TELEGRAM_CHAT_GROUP_ID" \
                --data-urlencode "message_thread_id=$TELEGRAM_THREAD_ID" \
                --data-urlencode "text=$message" \
                "$TELEGRAM_BYPASS_URL/bot$TELEGRAM_BOT_API_TOKEN/sendMessage")

            if [ "$response" -eq 200 ]; then
                return 0  # Success
            else
                echo "Failed to send Telegram notification. Attempt $((retry_count+1)) of $max_retries. HTTP status code: $response"
                retry_count=$((retry_count+1))
                sleep 2
            fi
        done

        echo "Failed to send Telegram notification after $max_retries attempts."
        return 1
    fi
}

# Function to handle errors and send notifications
handle_error() {
    local error_msg=$1
    local context=$2
    local message=$(cat <<EOF
Sender Server Speaking:

Failed during $context:
$error_msg

Backup file name: $ZIP_FILE

#backup
#sender
#bug
#error
EOF
)
    send_telegram_notification "$message"
    exit 1
}

# Variables
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M")
ZIP_FILE="backup_$TIMESTAMP.zip"
DUMP_FILE="$BACKUP_DIR/dump_$TIMESTAMP.sql"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Send telegram notification at progress start
available_files=""
backup_files=($(ls -1t "$BACKUP_DIR"))
for file in "${backup_files[@]}"; do
    if [ -f "$BACKUP_DIR/$file" ]; then
        file_size=$(du -sh "$BACKUP_DIR/$file" | cut -f1)
        available_files+="$file ($file_size)\n"
    fi
done

# Remove trailing newline from available_files
available_files=$(echo -e "$available_files" | sed 's/\n$//')

send_telegram_notification "$(cat <<EOF
Sender Server Speaking:

Backup Progress Started!
- Available Current Backups:
$available_files

Backup file name: $ZIP_FILE

#backup
#sender
EOF
)"

# Dump PostgreSQL database using Docker
error_msg=$(sudo docker exec -t "$DOCKER_CONTAINER_NAME" pg_dumpall -c -U "$DB_USER" > "$DUMP_FILE" 2>&1)
if [ $? -ne 0 ]; then
    handle_error "$error_msg" "database dump"
fi

# Create a ZIP file containing the database dump and media files
error_msg=$(zip -r "$BACKUP_DIR/$ZIP_FILE" "$DUMP_FILE" "$MEDIA_DIR" "$MIGRATION_DIR" 2>&1)
if [ $? -ne 0 ]; then
    handle_error "$error_msg" "creating zip folder"
fi

# Send telegram notification that backup was created successfully
send_telegram_notification "$(cat <<EOF
Sender Server Speaking:

Transfer backup progress started!
Backup file name: $ZIP_FILE

#backup
#sender
EOF
)"

# Transfer the backup to the remote server using scp with SSH key and skip host key checking
error_msg=$(scp -o StrictHostKeyChecking=no -i "$SSH_PRIVATE_KEY_PATH" "$BACKUP_DIR/$ZIP_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR" 2>&1)
if [ $? -ne 0 ]; then
    handle_error "$error_msg" "SCP transfer"
fi

# Get details of the transferred files
FILE_DETAILS=$(ls -lh "$BACKUP_DIR/$ZIP_FILE")

# Send a success notification with file details
send_telegram_notification "$(cat <<EOF
Sender Server Speaking:

Transfer Completed Successfully!
Backup file name: $ZIP_FILE
Details:
$FILE_DETAILS

#backup
#sender
EOF
)"
