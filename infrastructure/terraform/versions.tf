terraform {
  # Upper bound on purpose. ">= 1.6" alone would accept a future 2.x, and this
  # repo has already been bitten once by a constraint that was looser than it
  # looked: "~> 0.8" on the libvirt provider silently resolved to 0.9.9. A floor
  # is not a pin.
  required_version = ">= 1.6, < 2.0.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}
