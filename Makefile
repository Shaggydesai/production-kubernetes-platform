# Build the platform on a fresh Ubuntu host.
#
#   make check        what is missing before you start
#   make up           host -> VMs -> cluster -> Argo CD, then stops at Vault
#   make vault-init   prints the unseal shares ONCE. You store them.
#   make secrets      unseal, wire External Secrets, let Argo converge
#
# Two commands, not one. See docs/adr/ADR-006-bootstrap.md decision 7: a
# pipeline that generates unseal shares and then stores them somewhere it can
# read them again has produced encryption with the key taped to the box.

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ANSIBLE_DIR := infrastructure/ansible
TF_DIR      := infrastructure/terraform
INVENTORY   := inventory/lab.yml
ROOT_APP    := kubernetes/gitops/bootstrap/platform-root.yaml

BOLD := \033[1m
DIM  := \033[2m
OFF  := \033[0m

.PHONY: help check host vms inventory cluster platform node-config up \
        vault-init secrets destroy status

help:
	@printf '$(BOLD)Build$(OFF)\n'
	@printf '  make check        preflight: tools, credentials, config files\n'
	@printf '  make up           host, VMs, cluster, Argo CD - stops at the Vault gate\n'
	@printf '\n$(BOLD)Then, by hand$(OFF)\n'
	@printf '  make vault-init   initialise Vault. Prints 5 shares ONCE.\n'
	@printf '  make secrets      unseal and wire up External Secrets\n'
	@printf '\n$(BOLD)Individual steps$(OFF)\n'
	@printf '  make host         KVM, libvirt, storage pool, no-sleep\n'
	@printf '  make vms          terraform apply\n'
	@printf '  make inventory    regenerate the Ansible inventory from terraform\n'
	@printf '  make cluster      containerd, kubeadm, Flannel, join workers\n'
	@printf '  make platform     apply platform-root; Argo does the rest\n'
	@printf '  make node-config  backups, metrics, tuning (needs a live cluster)\n'
	@printf '  make status       what exists right now\n'
	@printf '  make destroy      delete the VMs. Everything on them is lost.\n'

# ---------------------------------------------------------------- preflight --
check:
	@fail=0; \
	for t in terraform ansible-playbook virsh kubectl; do \
	  if command -v $$t >/dev/null 2>&1; then printf '  ok    %s\n' "$$t"; \
	  else printf '  MISSING %s\n' "$$t"; fail=1; fi; \
	done; \
	if [ -f $(TF_DIR)/terraform.tfvars ]; then printf '  ok    terraform.tfvars\n'; \
	  else printf '  MISSING %s/terraform.tfvars  (cp terraform.tfvars.example ...)\n' "$(TF_DIR)"; fail=1; fi; \
	if [ -f $(ANSIBLE_DIR)/group_vars/all.yml ]; then printf '  ok    group_vars/all.yml\n'; \
	  else printf '  MISSING %s/group_vars/all.yml  (cp all.example.yml all.yml)\n' "$(ANSIBLE_DIR)"; fail=1; fi; \
	if [ -f $(ANSIBLE_DIR)/roles/cni_flannel/files/kube-flannel.yml ]; then printf '  ok    vendored Flannel manifest\n'; \
	  else printf '  MISSING vendored Flannel manifest (see that role files/README.md)\n'; fail=1; fi; \
	if virsh --connect qemu:///system list >/dev/null 2>&1; then printf '  ok    libvirt without sudo\n'; \
	  else printf '  NOTE  virsh needs sudo - log out and back in after "make host"\n'; fi; \
	exit $$fail

# ------------------------------------------------------------------- build --
host:
	@printf '$(BOLD)==> host: KVM, libvirt, storage pool, sleep disabled$(OFF)\n'
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/kvm-host.yml -K
	@printf '$(DIM)If this added you to the libvirt group, log out and back in before "make vms".$(OFF)\n'

vms:
	@printf '$(BOLD)==> vms: terraform apply$(OFF)\n'
	cd $(TF_DIR) && terraform init -input=false && terraform apply -auto-approve
	@$(MAKE) --no-print-directory inventory

inventory:
	cd $(TF_DIR) && terraform output -raw ansible_inventory > ../ansible/$(INVENTORY)
	@printf '$(DIM)wrote $(ANSIBLE_DIR)/$(INVENTORY)$(OFF)\n'
	@cat $(ANSIBLE_DIR)/$(INVENTORY)

cluster:
	@printf '$(BOLD)==> cluster: containerd, kubeadm, Flannel, workers$(OFF)\n'
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(INVENTORY) playbooks/cluster.yml

platform:
	@printf '$(BOLD)==> platform: Argo CD and the root Application$(OFF)\n'
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(INVENTORY) playbooks/argocd.yml
	kubectl apply -f $(ROOT_APP)
	@printf '$(DIM)Argo will now sync every child app. Anything needing a rendered\n'
	@printf 'Secret stays Pending until Vault is unsealed - that is expected.$(OFF)\n'

node-config:
	@printf '$(BOLD)==> node config: backups, metrics, tuning$(OFF)\n'
	cd $(ANSIBLE_DIR) && ansible-playbook -i $(INVENTORY) playbooks/hosts.yml

up: check host vms cluster platform
	@printf '\n'
	@printf '$(BOLD)============================================================$(OFF)\n'
	@printf '$(BOLD) STOP. Vault is uninitialised.$(OFF)\n'
	@printf '$(BOLD)============================================================$(OFF)\n'
	@printf '\n'
	@printf 'Nothing that consumes a rendered Secret will start until Vault is\n'
	@printf 'unsealed. Postgres will sit in CreateContainerConfigError, which\n'
	@printf 'gives no hint that Vault is the answer - proven by the restore\n'
	@printf 'drill on 2026-09-26.\n'
	@printf '\n'
	@printf '  $(BOLD)make vault-init$(OFF)   prints 5 unseal shares and a root token ONCE\n'
	@printf '  $(BOLD)make secrets$(OFF)      unseal and wire up External Secrets\n'
	@printf '  $(BOLD)make node-config$(OFF)  backups and metrics, once the cluster is settled\n'
	@printf '\n'

# ------------------------------------------------------------------ secrets --
vault-init:
	@printf '$(BOLD)This prints 5 unseal shares and a root token. Once.$(OFF)\n'
	@printf 'They are not written to disk, not logged, and cannot be shown again.\n'
	@printf 'Have your password manager open before you continue.\n'
	@printf '\n'
	@read -r -p 'Ready? [y/N] ' a; [ "$$a" = y ] || { echo aborted; exit 1; }
	kubectl -n vault exec vault-0 -- vault operator init -key-shares=5 -key-threshold=3
	@printf '\n$(BOLD)Store those now.$(OFF) Three of the five unseal any restart of vault-0.\n'
	@printf 'Losing three of five means the data in Vault is unrecoverable.\n'

secrets:
	@if [ ! -x infrastructure/vault/bootstrap.sh ]; then \
	  printf 'infrastructure/vault/bootstrap.sh is missing or not executable.\n'; exit 1; fi
	@printf '$(BOLD)==> unseal and configure Vault$(OFF)\n'
	@printf '$(DIM)Shares are read with a hidden prompt: nothing is echoed or kept in\n'
	@printf 'shell history. Verify secrets by comparing hashes, never by printing\n'
	@printf 'values - see docs/runbooks/secret-rotation.md.$(OFF)\n'
	bash infrastructure/vault/bootstrap.sh

# -------------------------------------------------------------------- misc --
status:
	@printf '$(BOLD)guests$(OFF)\n'
	@virsh --connect qemu:///system list --all 2>/dev/null || printf '  (libvirt unreachable)\n'
	@printf '\n$(BOLD)nodes$(OFF)\n'
	@kubectl get nodes 2>/dev/null || printf '  (no cluster)\n'
	@printf '\n$(BOLD)argo$(OFF)\n'
	@kubectl -n argocd get applications 2>/dev/null \
	   -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
	   || printf '  (no Argo CD)\n'
	@printf '\n$(BOLD)vault$(OFF)\n'
	@kubectl -n vault exec vault-0 -- vault status 2>/dev/null | head -5 || printf '  (no Vault)\n'

destroy:
	@printf '$(BOLD)This deletes all three guests and their disks.$(OFF)\n'
	@printf 'Anything not in Git or in a Velero backup is gone permanently.\n'
	@read -r -p 'Type the word destroy to continue: ' a; [ "$$a" = destroy ] || { echo aborted; exit 1; }
	cd $(TF_DIR) && terraform destroy
