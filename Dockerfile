FROM certbot/certbot
RUN apk update && apk add curl
RUN pip install certbot-dns-cloudflare

RUN ARCH=$(uname -m) && \
    case $ARCH in \
        x86_64)  ARCH="amd64" ;; \
        aarch64) ARCH="arm64" ;; \
    esac && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
RUN chmod 777 ./kubectl && mv ./kubectl /usr/bin/
RUN mkdir /var/lib/letsencrypt && mkdir /var/log/letsencrypt && chmod 777 /var/lib/letsencrypt && chmod 777 /var/log/letsencrypt