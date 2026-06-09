#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER_PORT="${1:-/dev/ttyUSB1}"
PPP_IF="${PPP_IF:-ppp0}"
HOST_ADDR="${WSN_DHCPV6_HOST_ADDR:-fd00:23:42:1::100}"
PREFIX_LEN="${WSN_DHCPV6_PREFIX_LEN:-64}"
DNSMASQ_CONF="${ROOT_DIR}/wsn-dhcpv6-dnsmasq.conf"
LEASE_FILE="${ROOT_DIR}/wsn-dhcpv6.leases"
DNSMASQ_LOG="${ROOT_DIR}/wsn-dhcpv6.log"
DNSMASQ_PID="${ROOT_DIR}/wsn-dhcpv6.pid"
PPP_LOG="${ROOT_DIR}/wsn-pppd.log"

sudo pkill -f "dnsmasq .*wsn-dhcpv6-dnsmasq.conf" || true
sudo poff || true
sudo rm -f "${PPP_LOG}" "${DNSMASQ_LOG}"
touch "${PPP_LOG}" "${DNSMASQ_LOG}"
chmod 666 "${PPP_LOG}" "${DNSMASQ_LOG}"

echo "[1/5] starting PPP on ${ROUTER_PORT}"
sudo pppd debug passive noauth 115200 "${ROUTER_PORT}" \
  nocrtscts nocdtrcts lcp-echo-interval 0 noccp noip ipv6 ::23,::24 \
  logfile "${PPP_LOG}"

echo "[2/5] waiting for ${PPP_IF}"
for _ in $(seq 1 20); do
  if ip link show "${PPP_IF}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
ip link show "${PPP_IF}" >/dev/null

echo "[3/5] assigning host IPv6 ${HOST_ADDR}/${PREFIX_LEN} to ${PPP_IF}"
sudo ip -6 addr replace "${HOST_ADDR}/${PREFIX_LEN}" dev "${PPP_IF}"
sudo ip link set "${PPP_IF}" up
sudo ip -6 route replace fe80::/64 dev "${PPP_IF}" metric 1

echo "[4/5] enabling IPv6 forwarding"
sudo sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
sudo sysctl -w "net.ipv6.conf.${PPP_IF}.forwarding=1" >/dev/null

echo "[5/5] starting dnsmasq DHCPv6 server"
sudo dnsmasq \
  --conf-file="${DNSMASQ_CONF}" \
  --dhcp-leasefile="${LEASE_FILE}" \
  --log-facility="${DNSMASQ_LOG}" \
  --pid-file="${DNSMASQ_PID}"

echo "DHCPv6 server started."
echo "Lease file: ${LEASE_FILE}"
echo "Log file:   ${DNSMASQ_LOG}"
echo "PPP log:    ${PPP_LOG}"
echo
echo "Watch leases:"
echo "  tail -f ${LEASE_FILE}"
echo
echo "Stop dnsmasq:"
echo "  sudo kill \$(cat ${DNSMASQ_PID})"
