#!/bin/bash

set -o pipefail
set -o errexit
set -o errtrace
set -o nounset
# set -o xtrace

BACKUP_DIR=${BACKUP_DIR:-/tmp}
GCS_BUCKET=${GCS_BUCKET:-}
GCS_KEY_FILE_PATH=${GCS_KEY_FILE_PATH:-}
MONGODB_URI=${MONGODB_URI:-}
MONGODB_HOST=${MONGODB_HOST:-localhost}
MONGODB_PORT=${MONGODB_PORT:-27017}
MONGODB_DB=${MONGODB_DB:-}
MONGODB_USER=${MONGODB_USER:-}
MONGODB_PASSWORD=${MONGODB_PASSWORD:-}
MONGODB_OPLOG=${MONGODB_OPLOG:-}
SLACK_ALERTS=${SLACK_ALERTS:-}
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
SLACK_CHANNEL=${SLACK_CHANNEL:-}
SLACK_USERNAME=${SLACK_USERNAME:-}
SLACK_ICON=${SLACK_ICON:-}

export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=$GCS_KEY_FILE_PATH

backup() {
  mkdir -p "$BACKUP_DIR"
  date=$(date "+%Y-%m-%dT%H:%M:%SZ")
  archive_name="backup-$date.tar.gz"

  cmd_auth_part=""
  if [[ -n $MONGODB_USER ]] && [[ -n $MONGODB_PASSWORD ]]
  then
    cmd_auth_part="--username=\"$MONGODB_USER\" --password=\"$MONGODB_PASSWORD\""
  fi

  cmd_db_part=""
  if [[ -n $MONGODB_DB ]]
  then
    cmd_db_part="--db=\"$MONGODB_DB\""
  fi

  cmd_oplog_part=""
  if [[ $MONGODB_OPLOG = "true" ]]
  then
    cmd_oplog_part="--oplog"
  fi

  if [ -n "${MONGODB_URI:-}" ]; then
    cmd="mongodump --uri=\"$MONGODB_URI\" $cmd_db_part $cmd_oplog_part --gzip --archive=$BACKUP_DIR/$archive_name"
  else
    cmd="mongodump --host=\"$MONGODB_HOST\" --port=\"$MONGODB_PORT\" $cmd_auth_part $cmd_db_part $cmd_oplog_part --gzip --archive=$BACKUP_DIR/$archive_name"
  fi

  echo "starting to backup MongoDB host=$MONGODB_HOST port=$MONGODB_PORT"
  eval "$cmd"
}

upload_to_gcs() {
  echo "uploading backup archive to GCS bucket=$GCS_BUCKET"
  gcloud storage cp "$BACKUP_DIR/$archive_name" "$GCS_BUCKET"
}

send_slack_message() {
  local color=${1}
  local title=${2}
  local message=${3}

  echo "Sending to '${SLACK_CHANNEL}'..."
  curl --silent --data-urlencode \
    "$(printf 'payload={"channel": "%s", "username": "%s", "link_names": "true", "icon_emoji": "%s", "attachments": [{"author_name": "mongodb-gcs-backup", "title": "%s", "text": "%s", "color": "%s"}]}' \
        "${SLACK_CHANNEL}" \
        "${SLACK_USERNAME}" \
        "${SLACK_ICON}" \
        "${title}" \
        "${message}" \
        "${color}" \
    )" \
    "${SLACK_WEBHOOK_URL}" || true
  echo
}

err() {
  err_msg="Something went wrong on line $(caller)"
  echo "$err_msg" >&2
  if [[ $SLACK_ALERTS == "true" ]]
  then
    send_slack_message "danger" "Error while performing mongodb backup" "$err_msg"
  fi
}

cleanup() {
  rm "$BACKUP_DIR/$archive_name"
}

trap err ERR
backup
upload_to_gcs
cleanup
echo "backup done!"
