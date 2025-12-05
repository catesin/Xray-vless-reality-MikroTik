#Используем базовый образ с Alpine Linux для минимального размера
ARG ALPINE_VERSION=3.22.2
FROM ghcr.io/xtls/xray-core:25.10.15 AS xray-core
FROM xjasonlyu/tun2socks:v2.6.0 AS tun2socks
FROM alpine:${ALPINE_VERSION}
COPY --from=xray-core /usr/local/bin/xray /usr/local/bin/xray
COPY --from=tun2socks /usr/bin/tun2socks /usr/bin/tun2socks
COPY ./entrypoint.sh /entrypoint.sh
RUN apk update && apk add --no-cache openrc openresolv iproute2 libqrencode tcpdump && mkdir -p /usr/local/etc/xray
ENTRYPOINT ["/entrypoint.sh"]
