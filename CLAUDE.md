# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KCertbot is a Docker-based extension of the official certbot that includes kubectl. It enables automatic SSL certificate renewal within Kubernetes clusters with the ability to reload webservers after certificate updates. The project is designed to run as a Kubernetes CronJob.

## Architecture

### Container Build
- Base image: `certbot/certbot`
- Adds kubectl binary (supports both amd64 and arm64 architectures)
- Creates necessary directories: `/var/lib/letsencrypt` and `/var/log/letsencrypt`
- Multi-architecture support via GitLab CI buildx

### Kubernetes Components
The project consists of four Kubernetes resources in the `yaml/` directory:

1. **ServiceAccount** (`certbot-serviceaccount.yaml`): Service account used by the CronJob
2. **Role** (`certbot-pod-exec-role.yaml`): Grants permissions for pods/exec and service access
3. **RoleBinding** (`certbot-rolebind.yaml`): Binds the role to the service account in the `web` namespace
4. **CronJob** (`certbot-cronjob.yaml`): Runs every 12 hours, executes `certbot renew` and reloads nginx via kubectl

### Key Workflow
1. CronJob triggers certbot renewal
2. After renewal, executes: `kubectl exec service/nginx -- nginx -s reload`
3. Uses host path volumes for persistence: `/var/certbot/www` and `/var/certbot/conf`
4. Runs as non-root user (UID/GID 33)

## Common Commands

### Build Docker Image
```bash
docker build -t kcertbot:latest .
```

### Build Multi-Architecture Image (local)
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t kcertbot:latest .
```

### Deploy to Kubernetes
```bash
kubectl apply -f yaml/certbot-serviceaccount.yaml
kubectl apply -f yaml/certbot-pod-exec-role.yaml
kubectl apply -f yaml/certbot-rolebind.yaml
kubectl apply -f yaml/certbot-cronjob.yaml
```

### Check CronJob Status
```bash
kubectl get cronjob certbot-cron
kubectl get jobs --selector=app=certbot
```

### View CronJob Logs
```bash
kubectl logs -l app=certbot --tail=50
```

## GitLab CI/CD Pipeline

The pipeline consists of three stages:

1. **build**: Builds Docker image and pushes to Harbor registry (runs on all branches)
2. **scan**: Runs Trivy security scan for HIGH/CRITICAL vulnerabilities (non-default branches only, allowed to fail)
3. **push**: Multi-arch build (amd64/arm64) and push with `latest` tag (main branch only)

**Important**: The pipeline requires these GitLab CI variables:
- `HARBOR_HOST`: Harbor registry hostname
- `HARBOR_USERNAME`: Harbor registry username
- `HARBOR_PASSWORD`: Harbor registry password
- Docker-in-Docker certificates for buildx

## Important Considerations

- The namespace in `certbot-rolebind.yaml` is hardcoded to `web` - adjust if deploying to a different namespace
- The CronJob assumes nginx service is available and named `nginx`
- Host path volumes require appropriate permissions on the Kubernetes nodes
- Certificate files are stored at `/var/certbot/conf` on the host
- The image is tagged as `$HARBOR_HOST/library/$CI_PROJECT_NAME`
