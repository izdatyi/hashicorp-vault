ARG VAULT_VERSION=latest
FROM hashicorp/vault:${VAULT_VERSION}
RUN apk add --no-cache bash bind-tools ca-certificates uuidgen
ADD rootfs /
RUN chmod +x /docker*.sh
ENV VAULT_ADDR=http://127.0.0.1:8200
ENTRYPOINT [ "/docker-entrypoint-shim.sh" ]
CMD ["server"]
