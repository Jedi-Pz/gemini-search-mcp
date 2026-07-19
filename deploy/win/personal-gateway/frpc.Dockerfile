# frp client: exposes personal-nginx to the VPS on the public port.
# The frpc binary is downloaded at image-build time (inside the Linux VM) so
# that it never touches the Windows host filesystem — host AV (e.g. Huorong)
# flags and deletes frp binaries on sight.
FROM python:3.12-slim

ARG FRP_VERSION=0.61.2
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/frp.tgz \
      "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz" \
    && tar xzf /tmp/frp.tgz -C /usr/local/bin --strip-components=1 \
      "frp_${FRP_VERSION}_linux_amd64/frpc" \
    && rm /tmp/frp.tgz

COPY frpc.toml /etc/frp/frpc.toml

CMD ["frpc", "-c", "/etc/frp/frpc.toml"]
