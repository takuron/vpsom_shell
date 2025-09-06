#!/bin/sh
# /my-vaultwarden/backup/backup.sh

set -e

# --- 配置 ---
RCLONE_REMOTE_NAME="webdav-remote"
SOURCE_DIR="/data"
TMP_DIR="/tmp"
FILENAME_PREFIX="vaultwarden-backup"

# --- 备份函数 ---
do_backup() {
    echo "[\$$(date +'%Y-%m-%d %H:%M:%S')] Starting Vaultwarden backup..."

    # 1. 生成带时间戳的文件名
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    BACKUP_FILE="${TMP_DIR}/${FILENAME_PREFIX}-${TIMESTAMP}.tar.gz"

    # 2. 打包压缩
    echo "Creating archive: ${BACKUP_FILE}"
    tar -czf "${BACKUP_FILE}" -C "${SOURCE_DIR}" .

    # 3. 上传
    echo "Uploading ${BACKUP_FILE} to ${RCLONE_REMOTE_NAME}..."
    rclone copyto "${BACKUP_FILE}" "${RCLONE_REMOTE_NAME}:/${FILENAME_PREFIX}-${TIMESTAMP}.tar.gz" --progress --no-traverse

    # 4. 清理本地文件
    echo "Cleaning up local archive..."
    rm "${BACKUP_FILE}"

    echo "[\$$(date +'%Y-%m-%d %H:%M:%S')] Backup finished successfully."

    # 5. 清理远程旧备份
    echo "Cleaning up old remote backups (keeping last 7)..."
    rclone delete --min-age 7d "${RCLONE_REMOTE_NAME}:"
    echo "Remote cleanup complete."
}

# --- 主循环 ---
while true; do
    do_backup
    # 使用环境变量 BACKUP_INTERVAL，如果未设置，则默认使用 86400 秒 (24小时)
    # 容器内的 shell 可以直接读取到环境变量，没有转义问题
    SLEEP_TIME=${BACKUP_INTERVAL:-86400}
    echo "Next backup will start in ${SLEEP_TIME} seconds."
    sleep "${SLEEP_TIME}"
done
