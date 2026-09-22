#!/usr/bin/env bash
# Vault bootstrap — run by a human admin, NOT by automation. Safe to re-run.
# Needs a privileged token: admin userpass, or a temporary root from `vault operator generate-root`.
# Secrets are passed via stdin only: never on screen, in shell history, or in process args.
set -euo pipefail
cd "$(dirname "$0")"

read -rsp "Vault token (admin or temporary root): " VT; echo
vx() { kubectl exec -i -n vault vault-0 -- sh -c "read -r VAULT_TOKEN; export VAULT_TOKEN; $1"; }

echo "== engines & auth methods (enable only if missing) =="
printf '%s\n' "$VT" | vx 'vault secrets list | grep -q "^secret/" || vault secrets enable -path=secret kv-v2'
printf '%s\n' "$VT" | vx 'vault auth list | grep -q "^kubernetes/" || vault auth enable kubernetes'
printf '%s\n' "$VT" | vx 'vault auth list | grep -q "^userpass/"   || vault auth enable userpass'

echo "== policies from git =="
for p in vault-configurator admin; do
  { printf '%s\n' "$VT"; cat "policies/$p.hcl"; } | vx "vault policy write $p -"
done

echo "== k8s auth role for the configure Job =="
printf '%s\n' "$VT" | vx 'vault write auth/kubernetes/role/vault-configurator \
  bound_service_account_names=vault-configurator \
  bound_service_account_namespaces=vault \
  token_policies=vault-configurator token_ttl=10m token_max_ttl=15m'

read -rp "Set/reset password for Vault user 'sagar'? [y/N] " A
if [[ "${A,,}" == "y" ]]; then
  read -rsp "New password: " P1; echo; read -rsp "Repeat: " P2; echo
  [[ "$P1" == "$P2" && ${#P1} -ge 12 ]] || { echo "mismatch or shorter than 12 chars"; exit 1; }
  { printf '%s\n' "$VT"; printf '%s' "$P1"; } | vx 'vault write auth/userpass/users/sagar \
    password=- token_policies=admin token_ttl=1h token_max_ttl=8h'
  unset P1 P2
fi
unset VT
echo "Bootstrap done."
