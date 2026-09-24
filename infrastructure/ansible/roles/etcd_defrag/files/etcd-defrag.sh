#!/usr/bin/env bash
# Defragment etcd's bbolt file when fragmentation is worth the outage.
# Single-member cluster: defrag blocks etcd, so the API is briefly unavailable.
set -euo pipefail

PKI=/etc/kubernetes/pki/etcd
ENDPOINT=https://127.0.0.1:2379
THRESHOLD_PCT=${THRESHOLD_PCT:-50}      # only defrag above this % reclaimable
MIN_SIZE_BYTES=${MIN_SIZE_BYTES:-104857600}   # ...and above 100MB absolute
TEXTFILE_DIR=/var/lib/node_exporter/textfile_collector
METRIC="$TEXTFILE_DIR/etcd_defrag.prom"

ec() {
  etcdctl --endpoints="$ENDPOINT" --cacert="$PKI/ca.crt" \
          --cert="$PKI/server.crt" --key="$PKI/server.key" "$@"
}

write_metrics() {   # action size inuse duration
  local action=$1 size=$2 inuse=$3 dur=$4 now
  now=$(date +%s)
  mkdir -p "$TEXTFILE_DIR"
  cat > "$METRIC.tmp" <<METRICS
# HELP etcd_defrag_last_success_timestamp_seconds Unix time the defrag job last completed without error.
# TYPE etcd_defrag_last_success_timestamp_seconds gauge
etcd_defrag_last_success_timestamp_seconds $now
# HELP etcd_defrag_last_duration_seconds Wall-clock duration of the last defrag (0 when skipped).
# TYPE etcd_defrag_last_duration_seconds gauge
etcd_defrag_last_duration_seconds $dur
# HELP etcd_defrag_last_action Whether the last run defragged (1) or skipped (0).
# TYPE etcd_defrag_last_action gauge
etcd_defrag_last_action{action="$action"} 1
# HELP etcd_defrag_db_size_bytes Physical db size observed at the last run.
# TYPE etcd_defrag_db_size_bytes gauge
etcd_defrag_db_size_bytes $size
# HELP etcd_defrag_db_size_in_use_bytes Logical db size observed at the last run.
# TYPE etcd_defrag_db_size_in_use_bytes gauge
etcd_defrag_db_size_in_use_bytes $inuse
METRICS
  chmod 644 "$METRIC.tmp"
  mv "$METRIC.tmp" "$METRIC"        # atomic: node-exporter never reads a half-written file
}

read_sizes() {
  ec endpoint status -w json > /tmp/etcd-defrag-status.json
  python3 - <<'PY'
import json
d = json.load(open('/tmp/etcd-defrag-status.json'))[0]['Status']
print(d['dbSize'], d['dbSizeInUse'])
PY
}

read -r SIZE INUSE <<< "$(read_sizes)"
RECLAIM=$(( SIZE - INUSE ))
PCT=$(( SIZE > 0 ? RECLAIM * 100 / SIZE : 0 ))

echo "db size ${SIZE}B, in use ${INUSE}B, reclaimable ${RECLAIM}B (${PCT}%)"

if [ "$PCT" -lt "$THRESHOLD_PCT" ] || [ "$SIZE" -lt "$MIN_SIZE_BYTES" ]; then
  echo "below threshold (${THRESHOLD_PCT}% / ${MIN_SIZE_BYTES}B) - skipping, no outage taken"
  write_metrics skip "$SIZE" "$INUSE" 0
  exit 0
fi

echo "defragmenting - etcd will block and the API will be briefly unavailable"
START=$(date +%s)
ec --command-timeout=15m defrag --cluster
END=$(date +%s)
DUR=$(( END - START ))

read -r NEWSIZE NEWINUSE <<< "$(read_sizes)"
echo "done in ${DUR}s: ${SIZE}B -> ${NEWSIZE}B"

# a defrag that leaves an alarm armed is a failure, not a success
if ec alarm list | grep -q .; then
  echo "ERROR: alarm armed after defrag" >&2
  ec alarm list >&2
  exit 1
fi

write_metrics defrag "$NEWSIZE" "$NEWINUSE" "$DUR"
