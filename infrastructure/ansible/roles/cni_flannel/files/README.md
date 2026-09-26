# Vendored Flannel manifest

`kube-flannel.yml` is committed here rather than fetched at apply time, for the
same reason the Helm charts are vendored: `dl.min.io` returned HTTP 410
mid-project, and a build that depends on upstream availability is not
reproducible.

To refresh it, matching `flannel_version` in `group_vars/all.yml`:

    curl -fsSL -o kube-flannel.yml \
      https://github.com/flannel-io/flannel/releases/download/v0.28.9/kube-flannel.yml

Then check the network matches `pod_subnet`:

    grep -A4 'net-conf.json' kube-flannel.yml

The role asserts this at apply time, so a mismatch fails the run rather than
producing a cluster whose pods cannot route.

## Why Ansible applies this and not Argo CD

Argo CD is a set of pods. Pods need pod networking. Pod networking is the CNI.
Argo cannot install the thing it depends on in order to exist — so of everything
on this platform, the CNI is the one component that cannot be GitOps-managed.
See ADR-006 decision 6.
