#!/bin/bash
set -e

NODE_NAME="${NODE_NAME:-unknown}"

echo "[INFO] Restoring Let's Encrypt structure for node: $NODE_NAME"

# 1. Restore ACME account
echo "[INFO] Restoring ACME account..."
mkdir -p /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory/6d21f9f8b03985529f5ed82fea328e24

if [ -f /acme-secret/meta.json ]; then
  cp /acme-secret/meta.json /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory/6d21f9f8b03985529f5ed82fea328e24/
  cp /acme-secret/regr.json /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory/6d21f9f8b03985529f5ed82fea328e24/
  cp /acme-secret/private_key.json /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory/6d21f9f8b03985529f5ed82fea328e24/
  echo "[OK] ACME account restored"
else
  echo "[WARN] No ACME account in secret"
fi

# 2. Get domains for this node from cert-registry
echo "[INFO] Fetching domains from cert-registry..."
kubectl get configmap cert-registry -n secrets -o jsonpath='{.data.registry\.yaml}' > /tmp/registry.yaml
DOMAINS=$(yq eval ".certificates | to_entries | .[] | select(.value.node == \"$NODE_NAME\") | .key" /tmp/registry.yaml)

if [ -z "$DOMAINS" ]; then
  echo "[WARN] No domains found for node $NODE_NAME"
  exit 0
fi

# 3. For each domain, restore renewal config and certs
for domain in $DOMAINS; do
  echo "[INFO] Processing domain: $domain"
  SECRET_NAME="tls-${domain//./-}"

  # Get TLS secret (skip if doesn't exist yet)
  if ! kubectl get secret "$SECRET_NAME" -n secrets >/dev/null 2>&1; then
    echo "[WARN] Secret $SECRET_NAME not found, skipping"
    continue
  fi

  # Create directories
  mkdir -p /etc/letsencrypt/renewal
  mkdir -p /etc/letsencrypt/archive/$domain
  mkdir -p /etc/letsencrypt/live/$domain

  # Restore renewal config if exists
  if kubectl get secret "$SECRET_NAME" -n secrets -o jsonpath='{.data.renewal\.conf}' 2>/dev/null | base64 -d > /etc/letsencrypt/renewal/$domain.conf 2>/dev/null; then
    echo "[OK] Restored renewal config for $domain"
  else
    echo "[WARN] No renewal.conf for $domain"
  fi

  # Restore certs as version 1
  kubectl get secret "$SECRET_NAME" -n secrets -o jsonpath='{.data.fullchain\.pem}' | base64 -d > /etc/letsencrypt/archive/$domain/fullchain1.pem
  kubectl get secret "$SECRET_NAME" -n secrets -o jsonpath='{.data.privkey\.pem}' | base64 -d > /etc/letsencrypt/archive/$domain/privkey1.pem

  # Create symlinks in live/
  ln -sf ../../archive/$domain/fullchain1.pem /etc/letsencrypt/live/$domain/fullchain.pem
  ln -sf ../../archive/$domain/privkey1.pem /etc/letsencrypt/live/$domain/privkey.pem

  echo "[OK] Restored $domain"
done

echo "[OK] Let's Encrypt structure restored for $NODE_NAME"
