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
RUN_METRIC="$TEXTFILE_DIR/etcd_defrag_run.prom"

# Every run reports its outcome, in a file of its own.
#
# etcd_defrag.prom holds the last SUCCESS and feeds the 14-day staleness alert,
# so a failed run must never touch it. On 2026-09-27 10:45 this script ran while
# etcd was dead, read empty db sizes, fell through to the "skip" branch because
# empty strings arithmetic-evaluate to 0, and wrote a FRESH success timestamp.
# It did not just emit an unparseable file - it defeated its own alert by
# reporting success. Hence a second file that says what actually happened.
write_run_status() {
  mkdir -p "$TEXTFILE_DIR"
  {
    echo '# HELP etcd_defrag_last_run_status 1 if the last run succeeded, 0 if it failed.'
    echo '# TYPE etcd_defrag_last_run_status gauge'
    echo "etcd_defrag_last_run_status $1"
    echo '# HELP etcd_defrag_last_run_timestamp_seconds Unix time the last run ended, success or failure.'
    echo '# TYPE etcd_defrag_last_run_timestamp_seconds gauge'
    echo "etcd_defrag_last_run_timestamp_seconds $(date +%s)"
  } > "$RUN_METRIC.tmp"
  chmod 644 "$RUN_METRIC.tmp"
  mv "$RUN_METRIC.tmp" "$RUN_METRIC"
}
finish_ok() { trap - EXIT; write_run_status 1; }
trap 'write_run_status 0' EXIT

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
  local json
  json=$(mktemp)
  ec endpoint status -w json > "$json"
  STATUS_JSON="$json" python3 -c '
import json, os
d = json.load(open(os.environ["STATUS_JSON"]))[0]["Status"]
print(d["dbSize"], d["dbSizeInUse"])'
  rm -f "$json"
}

# NOT `read ... <<< "$(read_sizes)"`. set -e does not fire on a failing command
# substitution there: the enclosing command is `read`, which happily succeeds on
# an empty line. SIZE and INUSE then become empty, $(( SIZE - INUSE )) evaluates
# them as 0, and the run reports a skip - and a success - having never reached
# etcd at all. That is the 2026-09-27 failure exactly.
if ! SIZES=$(read_sizes); then
  echo "ERROR: could not read etcd endpoint status - is etcd running?" >&2
  exit 1
fi
read -r SIZE INUSE <<< "$SIZES"
case "$SIZE$INUSE" in
  *[!0-9]*|"") echo "ERROR: non-numeric db sizes from etcd: '$SIZE' '$INUSE'" >&2; exit 1 ;;
esac
RECLAIM=$(( SIZE - INUSE ))
PCT=$(( SIZE > 0 ? RECLAIM * 100 / SIZE : 0 ))

echo "db size ${SIZE}B, in use ${INUSE}B, reclaimable ${RECLAIM}B (${PCT}%)"

if [ "$PCT" -lt "$THRESHOLD_PCT" ] || [ "$SIZE" -lt "$MIN_SIZE_BYTES" ]; then
  echo "below threshold (${THRESHOLD_PCT}% / ${MIN_SIZE_BYTES}B) - skipping, no outage taken"
  write_metrics skip "$SIZE" "$INUSE" 0
  finish_ok
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
finish_ok
