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

# Every run reports its outcome, in a file of its own.
#
# velero_offsite.prom holds the last SUCCESS and is what the staleness alert
# reads, so a failure must never touch it. This second file says whether the
# most recent run worked, which makes a failure visible in minutes instead of
# being inferred from a timestamp that quietly stops moving. On 2026-09-27 and
# 2026-09-28 this job failed into a dead apiserver and the only signal was
# VeleroOffsiteCopyTooOld, which needs 36 hours to fire.
RUN_PROM="$PROM_DIR/velero_offsite_run.prom"
write_run_status() {
  tmp="$RUN_PROM.tmp"
  {
    echo '# HELP velero_offsite_last_run_status 1 if the last run succeeded, 0 if it failed.'
    echo '# TYPE velero_offsite_last_run_status gauge'
    echo "velero_offsite_last_run_status $1"
    echo '# HELP velero_offsite_last_run_timestamp_seconds Unix time the last run ended, success or failure.'
    echo '# TYPE velero_offsite_last_run_timestamp_seconds gauge'
    echo "velero_offsite_last_run_timestamp_seconds $(date +%s)"
  } > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$RUN_PROM"
}
trap 'write_run_status 0' EXIT

# Wait for the control plane before doing anything.
#
# The timer has Persistent=true and OnCalendar=03:15, so on a host that boots at
# that minute systemd runs the missed job immediately - before kube-apiserver is
# serving. Without this the run fails and the next attempt is a day away, which
# is how the offsite copy ended up two days stale.
echo "0/3 wait for apiserver"
for i in $(seq 1 60); do
  if kubectl --request-timeout=10s get --raw=/readyz >/dev/null 2>&1; then break; fi
  if [ "$i" -eq 60 ]; then echo "apiserver not ready after 10 minutes" >&2; exit 1; fi
  sleep 10
done

# And for MinIO to be serving. rclone talks to the Service ClusterIP, so a MinIO
# that exists but is not Ready gives a confusing rclone timeout instead of a
# clear message about what is actually wrong.
for i in $(seq 1 30); do
  avail=$(kubectl -n minio get deploy minio -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
  if [ "${avail:-0}" -ge 1 ]; then break; fi
  if [ "$i" -eq 30 ]; then echo "minio has no available replica after 5 minutes" >&2; exit 1; fi
  sleep 10
done

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

trap - EXIT
write_run_status 1
echo "OK: $OUT/$NAME.tar.gz.age ($(du -h "$OUT/$NAME.tar.gz.age" | cut -f1))"
