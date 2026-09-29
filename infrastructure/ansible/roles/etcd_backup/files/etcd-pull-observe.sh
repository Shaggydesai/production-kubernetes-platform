#!/usr/bin/env bash
# Observe, from this host, whether the laptop is still pulling backups.
#
# The chain is: etcd-backup.timer writes /var/backups/etcd, then an hourly
# scheduled task on the laptop fetches it over read-only SFTP. The last link is
# the one that makes a backup survive the loss of this VM, and until now it was
# the only link with no monitoring at all: it failed ten times overnight on
# 2026-09-27/28 and nothing noticed, because the script logs to a file on the
# laptop and exports no metric.
#
# Prometheus cannot scrape the laptop, and the laptop must not be able to write
# into the cluster - the pull key is deliberately read-only SFTP. So the copy is
# observed from the only place that can see it without weakening anything:
# sshd's own log on this host. The source proves the copy happened.
set -euo pipefail
umask 022

PROM_DIR=/var/lib/node_exporter/textfile_collector
OUT="$PROM_DIR/etcd_pull.prom"
mkdir -p "$PROM_DIR"

# 0 when no pull has been seen in the window, which is a real condition worth
# alerting on rather than a missing metric to be explained away.
last=0
if lines=$(journalctl -u ssh --since '-7 days' -o short-unix --no-pager 2>/dev/null \
           | grep -F 'Accepted publickey for etcdpull'); then
  candidate=$(printf '%s\n' "$lines" | tail -1 | cut -d. -f1)
  case "$candidate" in
    ''|*[!0-9]*) last=0 ;;
    *)           last=$candidate ;;
  esac
fi

{
  echo '# HELP etcd_pull_last_seen_timestamp_seconds Unix time of the most recent etcdpull SFTP login seen in sshd logs on this host. 0 if none within 7 days.'
  echo '# TYPE etcd_pull_last_seen_timestamp_seconds gauge'
  echo "etcd_pull_last_seen_timestamp_seconds $last"
} > "$OUT.tmp"
chmod 644 "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "last etcdpull login: $last"
