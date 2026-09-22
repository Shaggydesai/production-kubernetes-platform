# Used by the vault-configure Job (Kubernetes auth, SA vault/vault-configurator).
# Least privilege: it may NOT edit its own policy or role (no self-escalation),
# and may only CREATE secrets (KV v2 "create" cannot overwrite existing data).

path "auth/kubernetes/config" {
  capabilities = ["create", "read", "update"]
}
path "auth/kubernetes/role/external-secrets-role" {
  capabilities = ["create", "read", "update"]
}
path "sys/policies/acl/external-secrets-policy" {
  capabilities = ["create", "read", "update"]
}

# seeding: existence checks via metadata (no values), create-only writes
path "secret/metadata/*" {
  capabilities = ["read"]
}
path "secret/data/*" {
  capabilities = ["create"]
}
# velero seed copies the MinIO credentials
path "secret/data/minio" {
  capabilities = ["create", "read"]
}

path "sys/tools/random/*" {
  capabilities = ["update"]
}
