#!/usr/bin/env bash
# Mirror the Velero bucket out of the cluster, then store an encrypted snapshot.
set -euo pipefail
umask 027
export KUBECONFIG=/etc/kubernetes/admin.conf
WORK=/var/lib/velero-offsite/mirror        # working copy, not pulled by the laptop
OUT=/var/backups/velero-offsite            # encrypted snapshots, pulled by the laptop
KEEP_DAYS=7
RECIPIENT=/etc/etcd-backup/recipient.txt
PROM_DIR=/var/lib/node_exporter/textfile_collector
TS=$(date +%Y%m%d-%H%M%S)
NAME=velero-minio-$(hostname -s)-$TS

mkdir -p "$WORK" "$OUT" "$PROM_DIR"

export RCLONE_CONFIG_LAB_TYPE=s3
export RCLONE_CONFIG_LAB_PROVIDER=Minio
export RCLONE_CONFIG_LAB_ENDPOINT="http://$(kubectl -n minio get svc minio -o jsonpath='{.spec.clusterIP}'):9000"
RCLONE_CONFIG_LAB_ACCESS_KEY_ID=$(kubectl -n minio get secret minio-credentials -o jsonpath='{.data.rootUser}' | base64 -d)
RCLONE_CONFIG_LAB_SECRET_ACCESS_KEY=$(kubectl -n minio get secret minio-credentials -o jsonpath='{.data.rootPassword}' | base64 -d)
export RCLONE_CONFIG_LAB_ACCESS_KEY_ID RCLONE_CONFIG_LAB_SECRET_ACCESS_KEY

echo "1/3 mirror bucket"
rclone sync lab:velero-backups "$WORK" --stats-one-line --stats=0
unset RCLONE_CONFIG_LAB_ACCESS_KEY_ID RCLONE_CONFIG_LAB_SECRET_ACCESS_KEY

echo "2/3 encrypted snapshot"
tar -C "$WORK" -czf - . | age -R "$RECIPIENT" -o "$OUT/$NAME.tar.gz.age"
( cd "$OUT" && sha256sum "$NAME.tar.gz.age" > "$NAME.tar.gz.age.sha256" )
chgrp etcdbackup "$OUT" "$OUT/$NAME.tar.gz.age" "$OUT/$NAME.tar.gz.age.sha256"
chmod 750 "$OUT"; chmod 640 "$OUT/$NAME.tar.gz.age" "$OUT/$NAME.tar.gz.age.sha256"

echo "3/3 retention + metrics"
find "$OUT" -name 'velero-minio-*' -mtime +"$KEEP_DAYS" -print -delete
printf 'velero_offsite_last_success_timestamp_seconds %s\nvelero_offsite_last_size_bytes %s\n' \
  "$(date +%s)" "$(stat -c %s "$OUT/$NAME.tar.gz.age")" > "$PROM_DIR/velero_offsite.prom.tmp"
chmod 644 "$PROM_DIR/velero_offsite.prom.tmp"
mv "$PROM_DIR/velero_offsite.prom.tmp" "$PROM_DIR/velero_offsite.prom"
echo "OK: $OUT/$NAME.tar.gz.age ($(du -h "$OUT/$NAME.tar.gz.age" | cut -f1))"
