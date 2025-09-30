#!/bin/sh
echo "Starting setup container please wait"
sleep 1

SERVER_IP_ADDRESS=$(ping -c 1 $SERVER_ADDRESS | awk -F'[()]' '{print $2}')

NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|tun' | head -n1 | cut -d'@' -f1)


if [ -z "$SERVER_IP_ADDRESS" ]; then
  echo "Failed to obtain an IP address for FQDN $SERVER_ADDRESS"
  echo "Please configure DNS on Mikrotik"
  exit 1
fi

ip tuntap del mode tun dev tun0
ip tuntap add mode tun dev tun0
ip addr add 172.31.200.10/30 dev tun0
ip link set dev tun0 up
ip route del default via 172.18.20.5
ip route add default via 172.31.200.10
ip route add $SERVER_IP_ADDRESS/32 via 172.18.20.5
#ip route add 1.0.0.1/32 via 172.18.20.5
#ip route add 8.8.4.4/32 via 172.18.20.5

rm -f /etc/resolv.conf
tee -a /etc/resolv.conf <<< "nameserver 172.18.20.5"
#tee -a /etc/resolv.conf <<< "nameserver 1.0.0.1"
#tee -a /etc/resolv.conf <<< "nameserver 8.8.4.4"


cat <<EOF > /opt/xray/config/config.json
{
  "log": {
    "loglevel": "silent"
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
                "alterId": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT_FP",
          "serverName": "$SERVER_NAME_SNI",
          "publicKey": "$PUBLIC_KEY_PBK",
          "spiderX": "",
          "shortId": "$SHORT_ID_SID"
        }
      },
	  "tag": "proxy"
    }
  ]
}
EOF
echo "Xray and tun2socks preparing for launch"
rm -rf /tmp/xray/ && mkdir /tmp/xray/
7z x /opt/xray/xray.7z -o/tmp/xray/ -y
chmod 755 /tmp/xray/xray
rm -rf /tmp/tun2socks/ && mkdir /tmp/tun2socks/
7z x /opt/tun2socks/tun2socks.7z -o/tmp/tun2socks/ -y
chmod 755 /tmp/tun2socks/tun2socks
echo "Start Xray core"
/tmp/xray/xray run -config /opt/xray/config/config.json &
#pkill xray
echo "Start tun2socks"
/tmp/tun2socks/tun2socks -loglevel silent -tcp-sndbuf 3m -tcp-rcvbuf 3m -device tun0 -proxy socks5://127.0.0.1:10800 -interface $NET_IFACE &
#pkill tun2socks
echo "Container customization is complete"
