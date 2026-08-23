#!/bin/bash
DB_HOST="10.10.20.31"
DB_NAME="labapp"
DB_USER="labuser"
BACKUP_DIR="/home/ariel/backups/database"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ariel/backups/backup.log"
RETENTION_DAYS=7

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Database backup started ==="

mkdir -p "$BACKUP_DIR"

if ! ssh -o ConnectTimeout=5 ariel@10.10.20.31 "true" 2>/dev/null; then
    log "ERROR: db-01 unreachable, backup aborted"
    exit 1
fi

DUMP_FILE="$BACKUP_DIR/labapp_$DATE.sql"
ssh ariel@10.10.20.31 "PGPASSWORD=ariel pg_dump -h localhost -U $DB_USER $DB_NAME" > "$DUMP_FILE" 2>>"$LOG_FILE"

if [ $? -ne 0 ] || [ ! -s "$DUMP_FILE" ]; then
    log "ERROR: pg_dump failed or produced empty file"
    rm -f "$DUMP_FILE"
    exit 1
fi

log "SUCCESS: Database dumped to $DUMP_FILE"

gzip "$DUMP_FILE"
if [ $? -eq 0 ]; then
    log "SUCCESS: Compressed to ${DUMP_FILE}.gz"
else
    log "ERROR: Compression failed"
    exit 1
fi

find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete
log "Rotation: old backups (>$RETENTION_DAYS days) cleaned up"

log "=== Database backup completed ==="
echo ""

exit 0
