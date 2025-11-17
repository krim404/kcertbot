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

# 2. Get certificates for this node from cert-registry
echo "[INFO] Fetching certificates from cert-registry..."
kubectl get configmap cert-registry -n storage -o jsonpath='{.data.registry\.yaml}' > /tmp/registry.yaml
SECRET_NAMES=$(yq eval ".certificates | to_entries | .[] | select(.value.node == \"$NODE_NAME\") | .key" /tmp/registry.yaml)

if [ -z "$SECRET_NAMES" ]; then
  echo "[WARN] No certificates found for node $NODE_NAME"
  exit 0
fi

# 3. For each certificate, restore renewal config and certs
for SECRET_NAME in $SECRET_NAMES; do
  echo "[INFO] Processing certificate: $SECRET_NAME"

  # Get TLS secret (skip if doesn't exist yet)
  if ! kubectl get secret "$SECRET_NAME" -n storage >/dev/null 2>&1; then
    echo "[WARN] Secret $SECRET_NAME not found, skipping"
    continue
  fi

  # Get primary domain (first domain in array) from registry
  PRIMARY_DOMAIN=$(yq eval ".certificates.\"$SECRET_NAME\".domains[0]" /tmp/registry.yaml)

  # Create directories
  mkdir -p /etc/letsencrypt/renewal
  mkdir -p /etc/letsencrypt/archive/$PRIMARY_DOMAIN
  mkdir -p /etc/letsencrypt/live/$PRIMARY_DOMAIN

  # Restore renewal config if exists
  if kubectl get secret "$SECRET_NAME" -n storage -o jsonpath='{.data.renewal\.conf}' 2>/dev/null | base64 -d > /etc/letsencrypt/renewal/$PRIMARY_DOMAIN.conf 2>/dev/null; then
    echo "[OK] Restored renewal config for $PRIMARY_DOMAIN"
  else
    echo "[WARN] No renewal.conf for $PRIMARY_DOMAIN"
  fi

  # Restore certs as version 1
  kubectl get secret "$SECRET_NAME" -n storage -o jsonpath='{.data.cert\.pem}' | base64 -d > /etc/letsencrypt/archive/$PRIMARY_DOMAIN/cert1.pem
  kubectl get secret "$SECRET_NAME" -n storage -o jsonpath='{.data.chain\.pem}' | base64 -d > /etc/letsencrypt/archive/$PRIMARY_DOMAIN/chain1.pem
  kubectl get secret "$SECRET_NAME" -n storage -o jsonpath='{.data.fullchain\.pem}' | base64 -d > /etc/letsencrypt/archive/$PRIMARY_DOMAIN/fullchain1.pem
  kubectl get secret "$SECRET_NAME" -n storage -o jsonpath='{.data.privkey\.pem}' | base64 -d > /etc/letsencrypt/archive/$PRIMARY_DOMAIN/privkey1.pem

  # Create symlinks in live/
  ln -sf ../../archive/$PRIMARY_DOMAIN/cert1.pem /etc/letsencrypt/live/$PRIMARY_DOMAIN/cert.pem
  ln -sf ../../archive/$PRIMARY_DOMAIN/chain1.pem /etc/letsencrypt/live/$PRIMARY_DOMAIN/chain.pem
  ln -sf ../../archive/$PRIMARY_DOMAIN/fullchain1.pem /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem
  ln -sf ../../archive/$PRIMARY_DOMAIN/privkey1.pem /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem

  echo "[OK] Restored $PRIMARY_DOMAIN"
done

echo "[OK] Let's Encrypt structure restored for $NODE_NAME"
