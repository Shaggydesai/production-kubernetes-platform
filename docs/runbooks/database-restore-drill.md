# Runbook: database restore drill

Proves that a Velero backup can be turned back into a working database. Run it
after any change to the backup schedule, the storage class or the PostgreSQL
chart, and at least quarterly.

Restore into a **separate namespace**. Live data is never at risk, and the drill
can be repeated any time without a maintenance window.

## Result of the last drill: 2026-09-26

| Measure | Value |
|---|---|
| Data volume size | 65,041,859 bytes (~62 MB) |
| Backup duration | 18 s |
| Restore duration, correct procedure | 3 min |
| Backup to queryable database | ~5 min 50 s |
| Rows recovered | 1 user, 1 project, 6 tasks |
| Verification | sha256 of the task dump identical before and after: `15fc56f8e35d2958…` |
| Schema state after restore | `version 1, dirty f` |

Two attempts were needed. The first failed, and why it failed is the most
valuable part of this document.

## Never narrow a file-system restore with --include-resources

The first attempt passed
`--include-resources persistentvolumeclaims,secrets,configmaps,services,statefulsets,serviceaccounts`
to keep the sandbox tidy. It broke in two ways.

**The PVC could not bind.**

    fail to patch dynamic PV, err: context deadline exceeded,
      PVC: data-postgresql-0, PV: pvc-de541a75-...

With `persistentvolumes` excluded, the restored PVC kept `spec.volumeName`
pointing at the PV the *live* database is bound to. It sat `Pending` for 16
minutes and could never have bound.

**No data was restored at all.** Velero performs a file-system restore by
injecting a `restore-wait` init container into the restored **Pod**. With `pods`
excluded, the StatefulSet controller created a fresh pod with no such container.
`kubectl -n velero get podvolumerestores.velero.io -l velero.io/restore-name=<r>`
returned nothing.

The second failure is the dangerous one. Had the PVC bound, Postgres would have
started cleanly on an empty disk and the restore would have reported success.

Select by label instead. This restores every resource *type* Velero needs while
still leaving the rest of the namespace behind:

    --selector app.kubernetes.io/name=postgresql

## The database cannot be recovered from Velero alone

Postgres reads its password from the `postgresql-credentials` Secret, which
External Secrets Operator renders from Vault. That Secret carries ESO's labels,
not PostgreSQL's, so a label-selected restore does not include it and the pod
fails with:

    Error: secret "postgresql-credentials" not found

The pod shows `CreateContainerConfigError`, which gives no hint that the real
answer is "go unseal Vault". **Recovery order is therefore:**

1. **Vault** — unseal, 3 of 5 shares
2. **External Secrets Operator** — so it can render the credentials Secret
3. **Postgres** — Velero restore

## Procedure

### 1. Record the assertion

    PSQL='PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -At'
    mkdir -p /tmp/drill

    kubectl -n taskflow exec postgresql-0 -- sh -c \
      "$PSQL -c 'select count(*) from users' \
             -c 'select count(*) from projects' \
             -c 'select count(*) from tasks'" > /tmp/drill/before-counts.txt

    kubectl -n taskflow exec postgresql-0 -- sh -c \
      "$PSQL -F'|' -c 'select id, title, status, created_at from tasks order by created_at'" \
      > /tmp/drill/before-tasks.txt

Dump rows, not just counts. Matching counts prove quantity; matching UUIDs and
microsecond timestamps prove identity.

### 2. Take a fresh backup

    B=drill-$(date +%Y%m%d%H%M%S)
    velero backup create "$B" --include-namespaces taskflow \
      --default-volumes-to-fs-backup --wait

### 3. Verify the backup before trusting it

    velero backup describe "$B"
    kubectl -n velero get podvolumebackups.velero.io -l velero.io/backup-name="$B" \
      -o custom-columns=POD:.spec.pod.name,VOL:.spec.volume,PHASE:.status.phase,BYTES:.status.progress.bytesDone

A `postgresql-0` / `data` PodVolumeBackup, `Completed`, with a plausible byte
count. No PodVolumeBackup means there is nothing to restore.

### 4. Restore into an isolated namespace

    velero restore create "restore-$B" --from-backup "$B" \
      --namespace-mappings taskflow:taskflow-restore \
      --selector app.kubernetes.io/name=postgresql --wait

No Argo CD changes are needed: Argo prunes only resources carrying its own
tracking annotation, and `platform-postgresql` targets the `taskflow` namespace.
Nothing races. (An **in-place** restore is different — there you must disable
auto-sync on `platform-postgresql` and `taskflow-api` first.)

### 5. Supply the credentials Secret

Either unseal Vault and let ESO render it, or copy it across without printing it:

    kubectl -n taskflow get secret postgresql-credentials -o json | python3 -c "
    import json, sys
    s = json.load(sys.stdin)
    s['metadata'] = {'name': s['metadata']['name'], 'namespace': 'taskflow-restore'}
    s.pop('status', None)
    json.dump(s, sys.stdout)
    " | kubectl apply -f - >/dev/null

    kubectl -n taskflow-restore delete pod postgresql-0
    kubectl -n taskflow-restore wait --for=condition=ready pod/postgresql-0 --timeout=600s

Deleting the pod is safe: the PVC already holds the restored files.

### 6. Assert

    kubectl -n taskflow-restore exec postgresql-0 -- sh -c \
      "$PSQL -F'|' -c 'select id, title, status, created_at from tasks order by created_at'" \
      > /tmp/drill/after-tasks.txt

    diff /tmp/drill/before-tasks.txt /tmp/drill/after-tasks.txt && echo 'ROWS IDENTICAL'
    sha256sum /tmp/drill/before-tasks.txt /tmp/drill/after-tasks.txt

Then read the Postgres log. See the next section before worrying about it.

### 7. Clean up

    kubectl delete ns taskflow-restore
    velero restore delete "restore-$B" --confirm
    velero backup delete "$B" --confirm

## Gotchas

**`kubectl get backups` is ambiguous.** Both `longhorn.io/v1beta2` and
`velero.io/v1` register a `Backup` kind. `kubectl -n velero get backups` can
return an empty list that means "wrong CRD", not "no backups". Always write
`backups.velero.io`.

**The backup is crash-consistent, not transactionally clean.** Kopia copies a
running data directory, so Postgres recovers exactly as it would after a power
cut. Expect this on startup, and it is all normal:

    database system was not properly shut down; automatic recovery in progress
    redo starts at 0/1DD8EE8
    invalid record length at 0/1DD8FD0: expected at least 24, got 0
    redo done at 0/1DD8F98
    database system is ready to accept connections

`invalid record length` is **not** corruption. It is how Postgres finds the end
of the write-ahead log: it reads forward until it hits a header that is not
there. Every crash recovery logs it. `redo done` followed by
`ready to accept connections` is the success signal.

A drill passing does not prove every backup is clean — it proves this one was,
and that the recovery mechanism works. For a transactionally consistent dump you
would need `pg_dump` or a pre-backup hook that issues `CHECKPOINT`.

**Retention is 168h.** `velero-daily-data` keeps backups for seven days, so data
loss noticed on day eight is unrecoverable. `velero-daily-metadata` keeps 336h.

**Schedules are named `velero-daily-data` and `velero-daily-metadata`** — not
`daily-data`.
