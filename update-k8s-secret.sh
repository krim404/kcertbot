#!/bin/bash
set -e

# Certbot setzt automatisch diese Variablen:
# $RENEWED_DOMAINS - Die erneuerte Domain
# $RENEWED_LINEAGE - Pfad zum live/ Verzeichnis

DOMAIN="$RENEWED_DOMAINS"
CERT_PATH="$RENEWED_LINEAGE"
SECRET_NAME="tls-${DOMAIN//./-}"
SECRETS_NAMESPACE="secrets"

echo "[INFO] Processing renewed cert for domain: $DOMAIN"

# Erstelle Secret mit fullchain.pem, privkey.pem und renewal.conf
kubectl create secret generic "$SECRET_NAME" -n "$SECRETS_NAMESPACE" \
  --from-file=fullchain.pem="$CERT_PATH/fullchain.pem" \
  --from-file=privkey.pem="$CERT_PATH/privkey.pem" \
  --from-file=renewal.conf="/etc/letsencrypt/renewal/$DOMAIN.conf" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[OK] Secret $SECRET_NAME created/updated in $SECRETS_NAMESPACE"
echo "[INFO] Reflector will distribute to requesting namespaces"
