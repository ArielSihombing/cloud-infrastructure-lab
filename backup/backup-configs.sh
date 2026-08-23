#!/bin/bash

# Backup script untuk configuration files
# Menarik config Nginx (web-01, web-02) dan HAProxy (lb-01) ke infra-01

BACKUP_DIR="/home/ariel/backups/configs"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ariel/backups/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Backup started ==="

mkdir -p "$BACKUP_DIR/$DATE"

# Backup Nginx config dari web-01
if ssh -o ConnectTimeout=5 ariel@10.10.20.11 "true" 2>/dev/null; then
    scp -q ariel@10.10.20.11:/etc/nginx/sites-available/default "$BACKUP_DIR/$DATE/web-01-nginx.conf"
    if [ $? -eq 0 ]; then
        log "SUCCESS: web-01 Nginx config backed up"
    else
        log "ERROR: Failed to backup web-01 Nginx config"
    fi
else
    log "SKIP: web-01 unreachable"
fi

# Backup Nginx config dari web-02
if ssh -o ConnectTimeout=5 ariel@10.10.20.12 "true" 2>/dev/null; then
    scp -q ariel@10.10.20.12:/etc/nginx/sites-available/default "$BACKUP_DIR/$DATE/web-02-nginx.conf"
    if [ $? -eq 0 ]; then
        log "SUCCESS: web-02 Nginx config backed up"
    else
        log "ERROR: Failed to backup web-02 Nginx config"
    fi
else
    log "SKIP: web-02 unreachable"
fi

# Backup HAProxy config dari lb-01
if ssh -o ConnectTimeout=5 ariel@10.10.10.10 "true" 2>/dev/null; then
    scp -q ariel@10.10.10.10:/etc/haproxy/haproxy.cfg "$BACKUP_DIR/$DATE/lb-01-haproxy.cfg"
    if [ $? -eq 0 ]; then
        log "SUCCESS: lb-01 HAProxy config backed up"
    else
        log "ERROR: Failed to backup lb-01 HAProxy config"
    fi
else
    log "SKIP: lb-01 unreachable"
fi

# Compress hasil backup hari ini
cd "$BACKUP_DIR"
tar -czf "$DATE.tar.gz" "$DATE"
rm -rf "$DATE"
log "Compressed to $DATE.tar.gz"

# Rotation: hapus backup lebih dari 7 hari
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
log "Rotation: old backups (>7 days) cleaned up"

log "=== Backup completed ==="
echo ""

exit 0
