#!/bin/bash
set -e

# Certbot setzt automatisch diese Variablen:
# $RENEWED_DOMAINS - Die erneuerte Domain (kann mehrere sein, space-separated)
# $RENEWED_LINEAGE - Pfad zum live/ Verzeichnis

# Extract primary domain from RENEWED_LINEAGE path (handles multi-domain certs)
PRIMARY_DOMAIN=$(basename "$RENEWED_LINEAGE")
CERT_PATH="$RENEWED_LINEAGE"
SECRET_NAME="tls-${PRIMARY_DOMAIN//./-}"
SECRETS_NAMESPACE="${CERT_NAMESPACE:-storage}"
CERT_REGISTRY_NAME="${CERT_REGISTRY_NAME:-cert-registry}"

echo "[INFO] Processing renewed cert for primary domain: $PRIMARY_DOMAIN"
echo "[INFO] All domains: $RENEWED_DOMAINS"

# Erstelle Secret mit allen Zertifikatsdateien und renewal.conf
kubectl create secret generic "$SECRET_NAME" -n "$SECRETS_NAMESPACE" \
  --from-file=cert.pem="$CERT_PATH/cert.pem" \
  --from-file=chain.pem="$CERT_PATH/chain.pem" \
  --from-file=fullchain.pem="$CERT_PATH/fullchain.pem" \
  --from-file=privkey.pem="$CERT_PATH/privkey.pem" \
  --from-file=renewal.conf="/etc/letsencrypt/renewal/$PRIMARY_DOMAIN.conf" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[OK] Secret $SECRET_NAME created/updated in $SECRETS_NAMESPACE"

# Update cert-registry ConfigMap with last-renew-date
echo "[INFO] Updating cert-registry ConfigMap..."
if kubectl get configmap "$CERT_REGISTRY_NAME" -n "$SECRETS_NAMESPACE" >/dev/null 2>&1; then
    kubectl get configmap "$CERT_REGISTRY_NAME" -n "$SECRETS_NAMESPACE" -o jsonpath='{.data.registry\.yaml}' > /tmp/registry.yaml

    # Update last-renew-date
    CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    yq eval ".certificates.\"$SECRET_NAME\".\"last-renew-date\" = \"$CURRENT_DATE\"" -i /tmp/registry.yaml

    # Apply updated registry
    kubectl create configmap "$CERT_REGISTRY_NAME" -n "$SECRETS_NAMESPACE" \
        --from-file=registry.yaml=/tmp/registry.yaml \
        --dry-run=client -o yaml | kubectl apply -f -

    rm -f /tmp/registry.yaml
    echo "[OK] cert-registry updated: last-renew-date=$CURRENT_DATE"
else
    echo "[WARN] cert-registry ConfigMap not found, skipping update"
fi

echo "[INFO] Reflector will distribute to requesting namespaces"
