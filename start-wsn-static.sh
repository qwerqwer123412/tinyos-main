#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER_PORT="${1:-/dev/ttyUSB1}"
PPP_IF="${PPP_IF:-ppp0}"
HOST_ADDR="${WSN_STATIC_HOST_ADDR:-fd00:23:42:1::100}"
PREFIX_LEN="${WSN_STATIC_PREFIX_LEN:-64}"
PPP_LOG="${ROOT_DIR}/wsn-pppd.log"

sudo pkill -f "dnsmasq .*wsn-dhcpv6-dnsmasq.conf" || true
sudo poff || true
sudo rm -f /var/lock/LCK.."$(basename "${ROUTER_PORT}")" /run/lock/LCK.."$(basename "${ROUTER_PORT}")"
sudo rm -f "${PPP_LOG}"
touch "${PPP_LOG}"
chmod 666 "${PPP_LOG}"

echo "[1/4] starting PPP on ${ROUTER_PORT}"
sudo pppd debug passive noauth 115200 "${ROUTER_PORT}" \
  nocrtscts nocdtrcts lcp-echo-interval 0 noccp noip ipv6 ::23,::24 \
  logfile "${PPP_LOG}"

echo "[2/4] waiting for ${PPP_IF}"
for _ in $(seq 1 20); do
  if ip link show "${PPP_IF}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
ip link show "${PPP_IF}" >/dev/null

echo "[3/4] assigning host IPv6 ${HOST_ADDR}/${PREFIX_LEN} to ${PPP_IF}"
sudo ip -6 addr replace "${HOST_ADDR}/${PREFIX_LEN}" dev "${PPP_IF}"
sudo ip link set "${PPP_IF}" up
sudo ip -6 route replace "fd00:23:42:1::/${PREFIX_LEN}" dev "${PPP_IF}" metric 1
sudo ip -6 route replace fe80::/64 dev "${PPP_IF}" metric 1

echo "[4/4] enabling IPv6 forwarding"
sudo sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
sudo sysctl -w "net.ipv6.conf.${PPP_IF}.forwarding=1" >/dev/null

echo "Static WSN PPP link started."
echo "Host:   ${HOST_ADDR}/${PREFIX_LEN} on ${PPP_IF}"
echo "Nodes:  fd00:23:42:1::2, fd00:23:42:1::3, fd00:23:42:1::4"
echo "PPP log: ${PPP_LOG}"
