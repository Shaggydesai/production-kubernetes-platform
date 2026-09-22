# Human admin (userpass "sagar"). Broad on purpose, but unlike the root token
# it is tied to an identity in the audit trail, expires, and can be revoked.
path "*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}
