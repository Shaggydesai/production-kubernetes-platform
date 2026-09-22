#!/usr/bin/env bash
# Encrypted etcd + control-plane backup for kubeadm. Run by etcd-backup.timer.
set -euo pipefail
umask 027

ETCDCTL=/usr/local/bin/etcdctl
ETCDUTL=/usr/local/bin/etcdutl
BACKUP_DIR=/var/backups/etcd
KEEP_DAYS=7
RECIPIENT=/etc/etcd-backup/recipient.txt
PROM_DIR=/var/lib/node_exporter/textfile_collector

TS=$(date +%Y%m%d-%H%M%S)
NAME=etcd-$(hostname -s)-$TS
WORK=$(mktemp -d /var/tmp/etcd-backup.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$BACKUP_DIR" "$PROM_DIR" "$WORK/$NAME"

echo "1/5 snapshot"
$ETCDCTL --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save "$WORK/$NAME/etcd.db" >/dev/null

echo "2/5 verify"
$ETCDUTL snapshot status "$WORK/$NAME/etcd.db" -w table | tee "$WORK/$NAME/status.txt"

echo "3/5 add PKI, kubeconfigs, manifests"
cp -a /etc/kubernetes/pki /etc/kubernetes/manifests "$WORK/$NAME/"
cp -a /etc/kubernetes/*.conf "$WORK/$NAME/"
{ $ETCDCTL version; hostname; date -Is; } > "$WORK/$NAME/info.txt"

echo "4/5 compress + encrypt"
OUT="$BACKUP_DIR/$NAME.tar.gz.age"
tar -C "$WORK" -czf - "$NAME" | age -R "$RECIPIENT" -o "$BACKUP_DIR/.$NAME.partial"
mv "$BACKUP_DIR/.$NAME.partial" "$OUT"
( cd "$BACKUP_DIR" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
chgrp etcdbackup "$BACKUP_DIR" "$OUT" "$OUT.sha256"; chmod 750 "$BACKUP_DIR"; chmod 640 "$OUT" "$OUT.sha256"

echo "5/5 retention + metrics"
find "$BACKUP_DIR" -name 'etcd-*.tar.gz.age*' -mtime +"$KEEP_DAYS" -print -delete
printf 'etcd_backup_last_success_timestamp_seconds %s\netcd_backup_last_size_bytes %s\n' \
  "$(date +%s)" "$(stat -c %s "$OUT")" > "$PROM_DIR/etcd_backup.prom.tmp"
chmod 755 /var/lib/node_exporter "$PROM_DIR"; chmod 644 "$PROM_DIR/etcd_backup.prom.tmp"
mv "$PROM_DIR/etcd_backup.prom.tmp" "$PROM_DIR/etcd_backup.prom"

echo "OK: $OUT ($(du -h "$OUT" | cut -f1))"
