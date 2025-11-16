# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KCertbot is a Docker-based extension of certbot that includes kubectl and yq. It manages SSL certificates in Kubernetes by storing them as Secrets and using Reflector for distribution. Designed to run as Kubernetes CronJobs with emptyDir for certificate storage.

## Architecture

### Container Build
- Base image: `certbot/certbot` (Alpine-based)
- Adds kubectl binary (multi-arch: amd64/arm64)
- Adds yq from Alpine edge/community repository
- Includes custom scripts:
  - `/scripts/update-k8s-secret.sh` - Deploy hook for certbot
  - `/scripts/restore-letsencrypt.sh` - Restores cert structure from secrets
- Multi-architecture support via GitLab CI buildx

### Certificate Storage Architecture
**Key Principle:** Certificates are stored as Kubernetes Secrets, not on persistent volumes.

1. **ACME Account**: Stored in `certbot-acme-account` secret (meta.json, regr.json, private_key.json)
2. **Certificates**: Each domain has a secret `tls-{domain}` containing:
   - `fullchain.pem` - Full certificate chain
   - `privkey.pem` - Private key
   - `renewal.conf` - Certbot renewal configuration
3. **Cert Registry**: ConfigMap mapping domains to nodes
4. **Distribution**: Reflector mirrors secrets to namespaces on demand

### Runtime Flow (per CronJob run)
1. **emptyDir** created (empty filesystem)
2. **InitContainer** (`restore-letsencrypt.sh`):
   - Restores ACME account from secret
   - Queries cert-registry for this node's domains
   - For each domain: restores cert as `archive/domain/{fullchain,privkey}1.pem`
   - Creates symlinks in `live/domain/` → `archive/domain/*1.pem`
3. **Certbot Container**:
   - Runs `certbot renew --deploy-hook /scripts/update-k8s-secret.sh`
   - On renewal: certbot creates `*2.pem` files, updates symlinks
   - Deploy hook saves renewed cert to secret
4. **emptyDir** deleted (next run starts fresh with version 1)

### Why This Works
- emptyDir always starts empty → always restore as version 1
- Certbot renewal creates version 2 during the run
- Next run: emptyDir empty again → restore latest (was v2) as v1
- Certbot creates v2 again if needed

### Scripts

**`update-k8s-secret.sh`** (deploy hook):
- Triggered by certbot for each renewed certificate
- Creates/updates secret `tls-{domain}` with fullchain.pem, privkey.pem, renewal.conf
- No nginx reload (handled separately)

**`restore-letsencrypt.sh`** (initContainer):
- Reads NODE_NAME environment variable
- Restores ACME account structure
- Queries cert-registry ConfigMap
- For each domain assigned to this node:
  - Fetches secret `tls-{domain}`
  - Restores to `/etc/letsencrypt/archive/domain/*1.pem`
  - Creates symlinks in `/etc/letsencrypt/live/domain/`

## Deployment Structure

Located in flux repository at `cluster/secrets/certbot/`:
- `certbot-acme-account-secret.yaml` - ACME account
- `cert-registry.yaml` - Domain to node mapping
- `certbot-serviceaccount.yaml` - Service account in `secrets` namespace
- `certbot-clusterrole.yaml` - Cluster-wide permissions
- `certbot-clusterrolebinding.yaml` - Binds role to SA
- `certbot-cronjob-{node}.yaml` - Per-node CronJobs

## Common Commands

### Build Docker Image
```bash
docker build -t kcertbot:latest .
```

### Build Multi-Architecture Image
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t registry.krim.dev/library/kcertbot:latest --push .
```

### Test Scripts Locally
```bash
# Test restore script (requires kubectl access and NODE_NAME)
export NODE_NAME=pi5
./restore-letsencrypt.sh

# Test deploy hook (requires certbot environment variables)
export RENEWED_DOMAINS=example.com
export RENEWED_LINEAGE=/etc/letsencrypt/live/example.com
./update-k8s-secret.sh
```

### Check CronJob Status
```bash
kubectl get cronjob -n secrets
kubectl get jobs -n secrets --selector=app=certbot
kubectl logs -n secrets -l app=certbot --tail=100
```

## GitLab CI/CD Pipeline

Three stages:
1. **build**: Builds and pushes Docker image to Harbor
2. **scan**: Trivy security scan (HIGH/CRITICAL)
3. **push**: Multi-arch build with `latest` tag (main branch only)

**Required CI Variables:**
- `HARBOR_HOST`, `HARBOR_USERNAME`, `HARBOR_PASSWORD`

## Important Notes

- Certificates are NEVER stored in Git (only in secrets)
- Each node runs its own CronJob with node-specific domains
- hostPath `/srv/certbot/www` is shared with nginx for ACME challenges
- RBAC allows certbot to create/update secrets cluster-wide
- New certificates must be created via separate tooling (not in CronJob)
