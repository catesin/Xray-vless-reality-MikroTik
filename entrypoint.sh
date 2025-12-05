#!/bin/sh
d() {
    [ "$LOG_LEVEL" = "DEBUG" ] && echo "[DEBUG] $1"
}
d "debug enabled"
XRAY_CONF_PATH="/usr/local/etc/xray/config.json"
echo "Starting setup container please wait"
sleep 1

d "getting SERVER_IP_ADDRESS from ${SERVER_ADDRESS}"
SERVER_IP_ADDRESS=$(ping -c 1 $SERVER_ADDRESS | awk -F'[()]' '{print $2}')
d "got SERVER_IP_ADDRESS: ${SERVER_IP_ADDRESS}"
d "getting NET_IFACE"
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|tun' | head -n1 | cut -d'@' -f1)
d "got SERVER_IP_ADDRESS: ${NET_IFACE}"

d "ip tuntap del mode tun dev tun0 || true"
ip tuntap del mode tun dev tun0 || true
d "ip tuntap add mode tun dev tun0"
ip tuntap add mode tun dev tun0
d "ip addr add 172.31.200.10/30 dev tun0"
ip addr add 172.31.200.10/30 dev tun0
d "ip link set dev tun0 up"
ip link set dev tun0 up
d "ip route del default via 172.18.20.5 || true"
ip route del default via 172.18.20.5 || true
d "ip route add default via 172.31.200.10"
ip route add default via 172.31.200.10
d "ip route add "${SERVER_IP_ADDRESS}/32" via 172.18.20.5"
ip route add "${SERVER_IP_ADDRESS}/32" via 172.18.20.5

echo "nameserver 172.18.20.5" > /etc/resolv.conf

cat <<EOF > "${XRAY_CONF_PATH}"
{
  "log": {
    "loglevel": "$LOG_LEVEL"
  },
  "inbounds": [
    {
      "port": 10800,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_ADDRESS",
            "port": $SERVER_PORT,
            "users": [
              {
                "id": "$USER_ID",
                "encryption": "$ENCRYPTION",
                "flow": "$FLOW"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT_FP",
          "serverName": "$SERVER_NAME_SNI",
          "publicKey": "$PUBLIC_KEY_PBK",
          "spiderX": "$SPIDERX",
          "shortId": "$SHORT_ID_SID"
        },
        "xhttpSettings": {
          "path": "/",
          "mode": "auto"
        }
      },
      "tag": "proxy"
    }
  ]
}
EOF

echo "Start Xray core"
/usr/local/bin/xray run -config "${XRAY_CONF_PATH}" &
echo "Start tun2socks"
/usr/bin/tun2socks -loglevel "${LOG_LEVEL}" -tcp-sndbuf 3m -tcp-rcvbuf 3m -device tun0 -proxy socks5://127.0.0.1:10800 -interface "${NET_IFACE}"
echo "Container customization is complete"
