ARG BASE_IMAGE=alpine:3.21
FROM ${BASE_IMAGE}

RUN set -eux; \
    apk add --no-cache bash ca-certificates curl openssl python3; \
    update-ca-certificates

WORKDIR /work

ENV HOME=/root \
    OUTPUT_DIR=/work \
    ACME_INSTALL_EMAIL=""

COPY auto_cert_bind.sh /usr/local/bin/auto_cert_bind.sh
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY acme.sh/acme.sh /opt/acme.sh/acme.sh
COPY acme.sh/dnsapi/dns_cf.sh /opt/acme.sh/dnsapi/dns_cf.sh

RUN set -eux; \
    chmod +x /usr/local/bin/auto_cert_bind.sh; \
    chmod +x /usr/local/bin/docker-entrypoint.sh; \
    chmod +x /opt/acme.sh/acme.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
