# ---------------------------------------------------------------------------
# Connection and storage
# ---------------------------------------------------------------------------

variable "libvirt_uri" {
  description = "libvirt connection URI. qemu:///system runs guests as root, which is what you want for a lab that survives logout."
  type        = string
  default     = "qemu:///system"
}

variable "storage_pool" {
  description = "libvirt storage pool for guest disks. On the rebuild this should live on the SSD."
  type        = string
  default     = "default"
}

variable "base_image_source" {
  description = <<-EOT
    Ubuntu cloud image: a URL or a local path.

    A URL under .../releases/noble/release/ is a MOVING TARGET - it changes when
    Canonical publishes a new build, so two `terraform apply` runs months apart
    give you different base images. This repo's stated principle is that the
    platform is rebuildable with the exact bytes that were tested (see
    PROJECT_STATE on vendored Helm charts, after dl.min.io returned HTTP 410).

    So: download the image once, verify it against SHA256SUMS, keep it on the
    SSD, and point this at that local path. The URL default is a convenience for
    the first run, not the intended steady state.
  EOT
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

# ---------------------------------------------------------------------------
# Identity - no defaults, because these must not be inherited from someone else
# ---------------------------------------------------------------------------

variable "admin_user" {
  description = "Login user created by cloud-init, with passwordless sudo and no password login."
  type        = string
}

variable "ssh_public_key" {
  description = "Your SSH public key, one line. Password authentication is disabled, so a wrong value here means an unreachable cluster."
  type        = string

  validation {
    condition     = can(regex("^(ssh-(rsa|ed25519)|ecdsa-sha2-) ", var.ssh_public_key))
    error_message = "Must be an OpenSSH public key line, e.g. 'ssh-ed25519 AAAA... you@host'. A private key or a file path will not work."
  }
}

# ---------------------------------------------------------------------------
# Network - see ADR-006 decision 3: the subnet deliberately does not change
# ---------------------------------------------------------------------------

variable "cluster_name" {
  type    = string
  default = "k8s-lab"
}

variable "network_name" {
  type    = string
  default = "k8s-lab"
}

variable "network_cidr" {
  description = "Guest subnet. Kept at 192.168.75.0/24 so every address already committed to Git - node IPs, the MetalLB pool 192.168.75.240-250, the Gateway - stays valid. Must not collide with your LAN."
  type        = string
  default     = "192.168.75.0/24"
}

variable "network_gateway" {
  description = "The libvirt bridge address. Also serves DNS via dnsmasq, which is why it is used as the nameserver."
  type        = string
  default     = "192.168.75.1"
}

variable "dns_domain" {
  description = "Search domain served by the libvirt network."
  type        = string
  default     = "platform.internal"
}

variable "control_plane_endpoint" {
  description = <<-EOT
    DNS name for the API server, registered in the libvirt network's DNS and
    passed to kubeadm as controlPlaneEndpoint with a matching certSAN.

    ADR-006 decision 5: the current cluster has apiServer:{} and no endpoint, so
    the control plane's IP is baked into the PKI. A name costs nothing at init
    and saves regenerating certificates later.
  EOT
  type        = string
  default     = "k8s-api.platform.internal"
}

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

variable "nodes" {
  description = <<-EOT
    Sizing revised for the new host (12 logical CPUs, 31.9 GB RAM). The previous
    allocation gave the control plane - running etcd - only 2 vCPU while a worker
    had 4. This gives etcd twice the CPU, and leaves roughly 2 vCPU / 8 GB for
    the host, libvirt and page cache.
  EOT

  type = map(object({
    ip      = string
    vcpu    = number
    memory  = number # MiB
    disk_gb = number
    role    = string # control-plane | worker
  }))

  default = {
    k8s-cp01 = {
      ip = "192.168.75.136", vcpu = 4, memory = 8192, disk_gb = 60, role = "control-plane"
    }
    k8s-worker01 = {
      ip = "192.168.75.137", vcpu = 3, memory = 8192, disk_gb = 80, role = "worker"
    }
    k8s-worker02 = {
      ip = "192.168.75.138", vcpu = 3, memory = 8192, disk_gb = 80, role = "worker"
    }
  }

  validation {
    condition     = length([for k, v in var.nodes : k if v.role == "control-plane"]) == 1
    error_message = "Exactly one node must have role = \"control-plane\". This platform is deliberately single-control-plane (accepted risk 12); multiple would need a load balancer this design does not provide."
  }

  validation {
    condition     = alltrue([for k, v in var.nodes : contains(["control-plane", "worker"], v.role)])
    error_message = "role must be either \"control-plane\" or \"worker\"."
  }

  validation {
    condition     = length(distinct([for k, v in var.nodes : v.ip])) == length(var.nodes)
    error_message = "Two nodes share an IP address."
  }
}

variable "autostart_domains" {
  description = "Start guests when the host boots. True is right for a lab you want back after a reboot - but read docs/runbooks/lab-startup-shutdown.md first: Longhorn and etcd want a staged start, not three VMs racing a cold page cache."
  type        = bool
  default     = false
}
