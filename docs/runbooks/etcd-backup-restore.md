# Runbook: etcd backup and restore

**Applies to:** kubeadm cluster `k8s-cp01` (single control-plane), etcd 3.6.8, Kubernetes v1.36.3
**Related:** [postmortem of 18 Sep 2026](../incidents/2026-09-18-etcd-corruption.md)

---

## 1. How backups work

| | |
|---|---|
| **Runs** | systemd timer `etcd-backup.timer` on `k8s-cp01`, every 6 hours (00/06/12/18 UTC, up to 5 min jitter) |
| **Script** | `/usr/local/sbin/etcd-backup.sh` (in Git: `infrastructure/ansible/roles/etcd_backup/files/`) |
| **Contents** | etcd snapshot + `/etc/kubernetes/pki` + static pod manifests + all `*.conf` kubeconfigs + `info.txt` / `status.txt` |
| **Verified** | `etcdutl snapshot status` runs *before* the bundle is written. A failed check fails the whole run |
| **Encrypted** | `age`, public key at `/etc/etcd-backup/recipient.txt`. **Private key is NOT on the cluster**: it lives on the laptop (`C:\Backups\etcd-backup-key.txt`) and in the password manager |
| **On the node** | `/var/backups/etcd/etcd-k8s-cp01-<ts>.tar.gz.age` (+ `.sha256`), 7-day retention, readable by group `etcdbackup` |
| **Off the node** | Laptop scheduled task "Pull etcd backups", hourly, read-only SFTP as user `etcdpull` (restricted to the laptop's IP), into `C:\Backups\etcd`, 30-day retention, checksum-verified. Log: `C:\Backups\pull-etcd.log` |
| **Monitoring** | `etcd_backup_last_success_timestamp_seconds` via node-exporter's textfile collector → alerts `EtcdBackupTooOld` (>8h) and `EtcdBackupMetricMissing` → Alertmanager → Discord `#alerts` |

**Vault is separate.** Vault's data is in a Longhorn volume, not in etcd. Take its
own snapshot before risky work: `vault operator raft snapshot save`.

---

## 2. Routine checks

```bash
# timer alive and last run OK
systemctl list-timers etcd-backup.timer --no-pager
systemctl status etcd-backup.service --no-pager | head -5
journalctl -u etcd-backup --since "24 hours ago" | tail -20

# backups present and intact on the node
ls -lh /var/backups/etcd/
cd /var/backups/etcd && sha256sum -c *.sha256

# monitoring sees a fresh backup (seconds since last success)
kubectl -n monitoring exec prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=time()-etcd_backup_last_success_timestamp_seconds'
```

On the laptop: `Get-Content C:\Backups\pull-etcd.log -Tail 5`

### Verify a backup is actually restorable (do this monthly)

```bash
F=$(ls -t /var/backups/etcd/*.age | head -1); [ -n "$F" ] || { echo "no backup"; exit 1; }
mkdir -p /tmp/restore-test
age -d -i /path/to/etcd-backup-key.txt "$F" | tar -xzf - -C /tmp/restore-test
ls /tmp/restore-test/*/                       # etcd.db, pki, manifests, *.conf
etcdutl snapshot status /tmp/restore-test/*/etcd.db -w table
rm -rf /tmp/restore-test
```

**The private key is not on the cluster on purpose.** Copy it over temporarily for
the test, then remove it with `shred -u`.

---

## 3. Restore: same node, etcd data lost or corrupted

**Impact:** API server down for the duration (a few minutes). Workloads keep
running; no scheduling or reconciliation while it's down.

```bash
sudo -i
TS=$(date +%Y%m%d-%H%M%S); BK=/root/restore-$TS; mkdir -p $BK/manifests

# 1. stop the control plane (API server first, then etcd)
mv /etc/kubernetes/manifests/kube-apiserver.yaml $BK/manifests/
until [ -z "$(crictl ps --name '^kube-apiserver$' -q)" ]; do sleep 2; done
mv /etc/kubernetes/manifests/etcd.yaml $BK/manifests/
until [ -z "$(crictl ps --name '^etcd$' -q)" ]; do sleep 2; done

# 2. NEVER delete the old data — move it aside
mv /var/lib/etcd /var/lib/etcd.broken-$TS

# 3. unpack the newest backup (needs the private age key, temporarily)
mkdir -p $BK/unpacked
age -d -i /root/etcd-backup-key.txt "$(ls -t /var/backups/etcd/*.age | head -1)" | tar -xzf - -C $BK/unpacked
etcdutl snapshot status $BK/unpacked/*/etcd.db -w table      # must succeed

# 4. restore
etcdutl snapshot restore $BK/unpacked/*/etcd.db --skip-hash-check \
  --data-dir /var/lib/etcd --name k8s-cp01 \
  --initial-cluster k8s-cp01=https://192.168.75.136:2380 \
  --initial-advertise-peer-urls https://192.168.75.136:2380
chmod 700 /var/lib/etcd

# 5. start etcd, then the API server
mv $BK/manifests/etcd.yaml /etc/kubernetes/manifests/
until etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key endpoint health; do sleep 5; done
mv $BK/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/
until kubectl --kubeconfig /etc/kubernetes/admin.conf get --raw /readyz >/dev/null 2>&1; do sleep 5; done
echo "API back"
shred -u /root/etcd-backup-key.txt
```

`--skip-hash-check` is needed when the file came from a data-directory copy
rather than `etcdctl snapshot save`. It is safe as long as
`etcdutl snapshot status` passed in step 3.

Then go to section 6, "After any restore".

**Rollback:** if etcd won't start, move both manifests out again,
`mv /var/lib/etcd /var/lib/etcd.failed-$TS && mv /var/lib/etcd.broken-$TS /var/lib/etcd`,
put the manifests back.

---

## 4. Restore: control-plane node rebuilt from scratch

Use when `k8s-cp01` is gone. Keep the **same hostname and IP** (`k8s-cp01`,
`192.168.75.136`) so the certificates and the workers' kubelet configuration
still match.

1. Install Ubuntu, containerd, and kubelet/kubeadm/kubectl **v1.36.3** (matching
   versions matter). Don't run `kubeadm init`.
2. Unpack the backup bundle on the new node (as in section 3, step 3).
3. Put the identity back:
```bash
   cp -a <unpacked>/pki        /etc/kubernetes/pki
   cp -a <unpacked>/*.conf     /etc/kubernetes/
   mkdir -p /etc/kubernetes/manifests
```
4. Restore etcd's data (section 3, step 4).
5. Copy the static pod manifests from the bundle into
   `/etc/kubernetes/manifests/`, then `systemctl enable --now kubelet`.
6. Wait for `/readyz`, then check `kubectl get nodes`. The workers reconnect on
   their own because the CA they trust has been restored.
7. Re-apply host configuration from Git:
```bash
   cd infrastructure/ansible && ansible-playbook playbooks/hosts.yml -K
```
   This restores the backup timer, the metrics settings and the pull user.

---

## 5. Repairing a structurally damaged etcd database

Symptom: etcd runs fine, but `etcdutl snapshot status` fails with
`nil bucket: ...`. That means stray records sit outside any bucket in the bbolt
file (this happened after the September 2026 hand-rebuilt recovery).

1. Check what's there: `bbolt buckets <snapshot>` should list exactly
   `alarm auth authRoles authUsers cluster key lease members members_removed meta`.
2. Clean **a copy** offline with `infrastructure/ansible/.../clean.go` (the
   `~/etcd-clean` helper): it deletes top-level entries that aren't one of those buckets.
3. `etcdutl snapshot status` on the cleaned file must now succeed.
4. Test-restore it into a throwaway etcd on ports 12379/12380 and compare the
   number of keys per resource type against live.
5. Swap it in with `/root/etcd-swap.sh`, which stops the API server, takes a
   fresh snapshot, cleans and verifies it, swaps the data directory and rolls
   back automatically on any failure. Downtime measured: **47 seconds**.

---

## 6. After any restore

```bash
kubectl get nodes
kubectl get pods -A | awk '$4!="Running" && $4!="Completed"'
kubectl get applications -n argocd

# Vault comes back SEALED after any restart — unseal with 3 of the 5 keys
kubectl exec -it vault-0 -n vault -- vault operator unseal      # run 3 times
kubectl exec -it vault-0 -n vault -- vault status | grep -E 'Sealed|Initialized'

# secrets flowing again?
kubectl get externalsecret -A

# storage
kubectl -n longhorn-system get volumes.longhorn.io

# app reachable end to end
curl -ks -o /dev/null -w "%{http_code}\n" --resolve taskflow.platform.internal:443:192.168.75.240 \
  https://taskflow.platform.internal/healthz

# take a fresh backup once things are healthy
sudo systemctl start etcd-backup.service
```

**Expected data loss:** up to 6 hours of Kubernetes object changes (the backup
interval). Application data in PostgreSQL, MinIO and the monitoring stack is
**not** in these backups: that's Velero's job, and Velero's volume restore is
still an open item.

---

## 7. Traps that have cost time before

| Trap | What happens | What to do |
|---|---|---|
| `etcdctl` / `etcdutl` version mismatch | `snapshot status` fails with confusing errors | Match the server version (3.6.8). In 3.6, `snapshot status`/`restore` live in **etcdutl**, not etcdctl |
| A backup file left in `/etc/kubernetes/manifests` | The kubelet starts it as a **second** etcd or scheduler | Always back up manifests **outside** that folder. Never use `lineinfile backup: yes` there |
| Changing only an Argo CD **hook** (the `vault-config` Job/ConfigMap/SA) | Nothing happens: hooks are excluded from the sync comparison | Trigger a sync: `kubectl patch application <app> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"sagar"},"sync":{}}}'` |
| Argo CD shows "Synced" | Only means Git matches the cluster, not that controllers accepted it | Check the object's status conditions (e.g. Alertmanager `Reconciled=False`) |
| Files edited on Windows | An invisible `\r` breaks comparisons and configs | `cat -A` shows `^M`; strip with `sed -i 's/\r//g'` |
| New group membership (e.g. `etcdbackup`) | "Permission denied" in the current shell | Log out and back in; groups are read at login |
| Empty variable in a pipeline | A command waits forever on the keyboard | Guard with `[ -n "$VAR" ] \|\| exit 1` |

---

## 8. Emergency access

- **Vault sealed:** unseal with 3 of the 5 keys (password manager).
- **Vault admin:** `vault login -method=userpass username=sagar`. There is no
  root token any more; if the admin login is lost, use
  `vault operator generate-root` with 3 unseal keys.
- **Backup decryption key:** `C:\Backups\etcd-backup-key.txt` on the laptop, plus
  the password manager copy. **Without it, every backup is unreadable.**
- **Cluster admin:** `/etc/kubernetes/admin.conf` on `k8s-cp01`, also inside every
  backup bundle.

---

## 10. Velero off-cluster copy

| | |
|---|---|
| **Runs** | `velero-offsite.timer` on `k8s-cp01`, daily 03:15 UTC (after the 01:00 and 02:00 Velero schedules) |
| **Script** | `/usr/local/sbin/velero-offsite.sh` (Ansible role `velero_offsite`) |
| **How** | `rclone sync` of bucket `velero-backups` → `/var/lib/velero-offsite/mirror`, then an age-encrypted tar into `/var/backups/velero-offsite` |
| **Retention** | 7 days on the node, 14 days on the laptop (`C:\Backups\velero`) |
| **Monitoring** | `velero_offsite_last_success_timestamp_seconds` → `VeleroOffsiteCopyTooOld` (>36h), `VeleroOffsiteMetricMissing` |

**To restore from it:** decrypt and unpack the snapshot, then either upload the
tree back into MinIO (`rclone sync <dir> lab:velero-backups`) and let Velero read
it as usual, or point a BackupStorageLocation at wherever you put it. The tree is
a Kopia repository, so it must be restored whole, not file by file.

**Note:** `dl.min.io` stopped serving the `mc` client (HTTP 410), which is why
this uses `rclone` from Ubuntu's repositories instead. Prefer packaged tools over
vendor download URLs in automation.

## 11. Defragmentation

etcd compacts history every 5 minutes but never shrinks the bbolt file, so
physical size climbs to its high-water mark. On 2026-09-24 the db was 342 MB
with 16 MB in use (95% reclaimable), tracking toward the 2 GiB backend quota
that puts etcd read-only.

- `etcd-defrag.timer` runs Sundays 03:30, via the `etcd_defrag` Ansible role.
- It only defrags above 100 MB physical AND >50% reclaimable; otherwise it
  skips and takes no outage.
- Single-member cluster: defrag blocks etcd, so a real run means a brief API
  outage (sub-second at current size). Multi-member clusters defrag one member
  at a time and stay available.
- Manual: `sudo /usr/local/sbin/etcd-defrag.sh`
  Force: `sudo THRESHOLD_PCT=0 MIN_SIZE_BYTES=0 /usr/local/sbin/etcd-defrag.sh`
- Verify: `etcdctl endpoint status -w table` (DB SIZE vs IN USE) and
  `etcdctl alarm list` must be empty.
