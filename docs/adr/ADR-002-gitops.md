# ADR-002: GitOps with Argo CD

- **Status:** Accepted
- **Date:** 2026-09-25
- **Supersedes:** none

## Context

The platform is 17 Argo CD Applications across a three-node kubeadm cluster.
Several decisions in this area were made implicitly over weeks and only became
visible when they caused problems. This records them deliberately.

## Decisions

### 1. App-of-apps, with `platform-root` applied by hand

`kubernetes/gitops/bootstrap/platform-root.yaml` is applied with `kubectl`.
It watches `kubernetes/gitops/argocd/`, where each file is one Application.

The root is not managed by anything. That is intentional: something has to
apply the thing that applies everything else, and keeping that one object
outside the system means it can be repaired without the system.

**Consequence:** changes to `platform-root.yaml` require a manual
`kubectl apply`. This is written in the runbook because nothing enforces it.

### 2. The root self-heals but does not prune; the children do both

    platform-root:  automated { selfHeal: true }              # no prune
    children:       automated { selfHeal: true, prune: true }

Every child app prunes, so a root that also pruned would cascade: delete a file
from `kubernetes/gitops/argocd/` and the Application disappears, taking that
app's entire workload - Longhorn, Postgres, whatever it owns - with it. One
careless `git rm` would be unrecoverable.

Self-healing everywhere; automatic deletion only where the blast radius is
bounded. Removing an application is a deliberate manual step.

**Evidence this matters:** `platform-vault` silently lost its `automated` block
during the September recovery and nothing noticed for three days, because the
root had no selfHeal at the time.

### 3. Argo CD is installed by Ansible, not by itself

`infrastructure/ansible/roles/argocd` runs `helm upgrade --install` against the
in-repo wrapper chart at `kubernetes/platform/argocd`.

Self-managing Argo CD is possible, but a controller that reconciles its own
Deployment can interrupt a sync mid-flight, and `prune: true` on itself is a
foot-gun. Keeping its lifecycle in Ansible means a broken Argo CD can be fixed
without a working Argo CD.

**This was previously ambiguous and actively harmful.** The role installed the
upstream `argo/argo-cd` chart while the repo also held a wrapper chart with its
own values and an HTTPRoute template. Whichever ran last won, and they produced
different clusters - running the playbook silently replaced the release and
deleted the Argo CD UI route. There is now one install path and one values file.

### 4. Chart dependencies are vendored

Each wrapper chart commits its upstream dependency as a `.tgz` under `charts/`,
with `Chart.lock`. The platform is rebuildable from Git alone, with the exact
bytes that were tested, independent of upstream availability - which is not
theoretical: `dl.min.io` began returning HTTP 410 mid-project.

`.gitattributes` marks `*.tgz` binary so diffs stay readable.

### 5. `main` is the source of truth, and it is protected

Until 2026-09-25 all 17 Applications tracked `feature/ubuntu-template`. They
now track `main`, which requires a pull request and a passing `test` check,
applies to admins, forbids force pushes, and requires linear history.

Required approvals is **0**, not 1: GitHub does not allow self-approval, so 1
would lock a solo maintainer out of their own repository. Zero still forces
every change through a PR with a diff, a CI run and a record.

### 6. CI opens a pull request; it does not push to `main`

The image build used to `git push` the new tag straight onto the branch. A
protected `main` rejects that - `GITHUB_TOKEN` does not bypass protection - so
the build would have published an image and then failed to update the manifest,
leaving the registry ahead of Git.

CI now opens a PR with the bump. One path into `main`, and the deploy is a
reviewable event.

**Intended direction:** Argo CD Image Updater with `write-back-method: argocd`
removes CI's write access to Git entirely. Not yet adopted.

## Consequences

- Deleting an application is manual, by design.
- `platform-root.yaml` changes need a manual apply, by design.
- Every image build produces a PR to merge. Friction accepted in exchange for a
  single auditable path into `main`.
- Repo size grows with vendored charts. Accepted.
- Argo CD upgrades run through Ansible, not GitOps. Accepted.
