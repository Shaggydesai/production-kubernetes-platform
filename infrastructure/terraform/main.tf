# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

resource "libvirt_network" "lab" {
  name      = var.network_name
  mode      = "nat"
  domain    = var.dns_domain
  addresses = [var.network_cidr]
  autostart = true

  # DHCP is deliberately OFF. Every address is assigned by cloud-init, so it
  # comes from Git rather than from a lease living inside the hypervisor. A
  # rebuild therefore produces the same addresses without depending on libvirt
  # having remembered anything.
  dhcp {
    enabled = false
  }

  dns {
    enabled    = true
    local_only = false

    # Node names resolve without touching /etc/hosts on the host.
    dynamic "hosts" {
      for_each = var.nodes
      content {
        hostname = hosts.key
        ip       = hosts.value.ip
      }
    }

    # The API server name, so kubeadm's controlPlaneEndpoint and certSANs can
    # use a name instead of an IP. ADR-006 decision 5.
    hosts {
      hostname = var.control_plane_endpoint
      ip       = one([for k, v in var.nodes : v.ip if v.role == "control-plane"])
    }
  }
}

# ---------------------------------------------------------------------------
# Disks
# ---------------------------------------------------------------------------

resource "libvirt_volume" "base" {
  name   = "${var.cluster_name}-base.qcow2"
  pool   = var.storage_pool
  source = var.base_image_source
  format = "qcow2"
}

resource "libvirt_volume" "node" {
  for_each = var.nodes

  name = "${each.key}.qcow2"
  pool = var.storage_pool

  # Copy-on-write from the shared base image: three guests cost one full image
  # plus their divergence, and cloud-init grows the root partition on first boot.
  base_volume_id = libvirt_volume.base.id
  size           = each.value.disk_gb * 1024 * 1024 * 1024
  format         = "qcow2"
}

# ---------------------------------------------------------------------------
# cloud-init
# ---------------------------------------------------------------------------

resource "libvirt_cloudinit_disk" "node" {
  for_each = var.nodes

  name = "${each.key}-cloudinit.iso"
  pool = var.storage_pool

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname   = each.key
    fqdn       = "${each.key}.${var.dns_domain}"
    admin_user = var.admin_user
    ssh_key    = trimspace(var.ssh_public_key)
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    ip      = each.value.ip
    prefix  = split("/", var.network_cidr)[1]
    gateway = var.network_gateway
    dns     = var.network_gateway
    search  = var.dns_domain
  })
}

# ---------------------------------------------------------------------------
# Guests
# ---------------------------------------------------------------------------

resource "libvirt_domain" "node" {
  for_each = var.nodes

  name      = each.key
  vcpu      = each.value.vcpu
  memory    = each.value.memory
  autostart = var.autostart_domains

  # Lets Terraform and `virsh domifaddr` read the guest's real addresses.
  # cloud-init installs and enables the agent.
  qemu_agent = true

  # Passes the host CPU through rather than emulating a generic model. Better
  # performance, and the guest sees the instruction set it actually runs on.
  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.node[each.key].id

  disk {
    volume_id = libvirt_volume.node[each.key].id
  }

  network_interface {
    network_id = libvirt_network.lab.id

    # virtio, not an emulated e1000. On 2026-09-24 the host slept with guests
    # running and VMware's emulated e1000 on the control plane wedged with
    # 'e1000 Tx Unit Hang'; recovery took two hours. A paravirtualised device
    # has no emulated NIC state machine to get stuck in.
    # See docs/incidents/2026-09-25-host-sleep.md
    #
    # DHCP is disabled on the network, so there is no lease to wait for -
    # Terraform would otherwise block until it timed out.
    wait_for_lease = false
  }

  # Serial console: `virsh console k8s-cp01`. This is what you need when a guest
  # fails to boot and SSH is therefore not an option.
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  # VNC bound to localhost only. Same reason - a way in when the network is the
  # thing that is broken.
  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "127.0.0.1"
    autoport       = true
  }
}
