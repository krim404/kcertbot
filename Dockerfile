FROM certbot/certbot
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
RUN apk update && apk add curl yq bash
RUN pip install certbot-dns-cloudflare

# Default environment variables (can be overridden in pod spec)
ENV CERT_NAMESPACE=storage
ENV CERT_REGISTRY_NAME=cert-registry

RUN ARCH=$(uname -m) && \
    case $ARCH in \
    x86_64)  ARCH="amd64" ;; \
    aarch64) ARCH="arm64" ;; \
    esac && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
RUN chmod 777 ./kubectl && mv ./kubectl /usr/bin/

# Scripts kopieren
COPY update-k8s-secret.sh /scripts/update-k8s-secret.sh
COPY restore-letsencrypt.sh /scripts/restore-letsencrypt.sh
RUN chmod +x /scripts/update-k8s-secret.sh /scripts/restore-letsencrypt.sh

RUN mkdir /var/lib/letsencrypt && mkdir /var/log/letsencrypt && chmod 777 /var/lib/letsencrypt && chmod 777 /var/log/letsencrypt
