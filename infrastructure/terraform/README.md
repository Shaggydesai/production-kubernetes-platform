# Terraform: the three guests

Creates the libvirt network and three Ubuntu 24.04 guests that the Ansible
layer then turns into a Kubernetes cluster. See `docs/adr/ADR-006-bootstrap.md`
for why KVM, why Terraform, and why the subnet does not change.

## Host prerequisites

Handled by `infrastructure/host/` (Ansible). If you are doing it by hand:

```bash
sudo apt install -y qemu-kvm libvirt-daemon-system virtinst \
                    libvirt-clients bridge-utils terraform
sudo usermod -aG libvirt,kvm "$USER"   # log out and back in
virsh --connect qemu:///system list --all   # must work without sudo
```

`virsh` working without sudo is the check that matters. If it does not, the
provider will fail with a permission error that reads like a Terraform problem
and is not one.

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # admin_user + ssh_public_key are required

terraform init
terraform validate
terraform plan
terraform apply

terraform output -raw ansible_inventory > ../ansible/inventory/lab.yml
```

First `apply` downloads the cloud image (~600 MB) unless `base_image_source`
points at a local copy. Guests are reachable in roughly a minute; cloud-init
needs a few seconds after boot to install the guest agent.

```bash
for ip in 192.168.75.136 192.168.75.137 192.168.75.138; do
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
      "$(terraform output -raw -json 2>/dev/null >/dev/null; echo sagar)@$ip" \
      'hostname; ip -br a | grep -v LOOPBACK' || echo "$ip not up yet"
done
```

## Rebuild

```bash
terraform destroy && terraform apply
```

This is the point of using Terraform rather than a script: the rebuild is a
routine, not a project. It is also postmortem item 13 from
`docs/incidents/2026-09-25-host-sleep.md`, which had never been executed because
executing it used to mean repeating the manual build.

**`destroy` deletes the guest disks.** Everything not in Git or in a Velero
backup is gone. The restore drill in `docs/runbooks/database-restore-drill.md`
was done first for exactly this reason.

## Things that will bite you

**The cloud image URL is a moving target.** `.../releases/noble/release/` changes
when Canonical publishes a new build, so two applies months apart give different
base images. Download it once, verify the checksum, and point
`base_image_source` at the local file. Same reasoning as the vendored Helm charts.

**DHCP is off.** Addresses come from cloud-init. If you add a node, its IP goes
in the `nodes` map — there is no lease to inspect and nothing to reserve.

**The storage pool defaults to `default`**, which is usually `/var/lib/libvirt/images`.
On the rebuild that should be a pool on the SSD. Three guests at 60+80+80 GB are
thin-provisioned qcow2, so actual usage starts far below 220 GB and grows.

**`autostart_domains` is false by default.** Three guests racing a cold page
cache on boot is how you get Longhorn volumes attaching before their replicas
are ready. Read `docs/runbooks/lab-startup-shutdown.md` before turning it on.

**Guest console when SSH will not do:**

```bash
virsh --connect qemu:///system console k8s-cp01     # Ctrl-] to exit
virsh --connect qemu:///system domifaddr k8s-cp01   # needs the guest agent
```
