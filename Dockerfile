FROM registry.krim.dev/proxy/certbot/certbot
RUN apk update && apk install curl
RUN ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m) && \
    case ${ARCH} in \
      x86_64|amd64) echo "amd64" > /tmp/arch ;; \
      aarch64|arm64) echo "arm64" > /tmp/arch ;; \
      *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    DETECTED_ARCH=$(cat /tmp/arch)
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${DETECTED_ARCH}/kubectl"
RUN chmod 777 ./kubectl && mv ./kubectl /usr/bin/