#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNSMASQ_PID="${ROOT_DIR}/wsn-dhcpv6.pid"

if [ -f "${DNSMASQ_PID}" ]; then
  sudo kill "$(cat "${DNSMASQ_PID}")" || true
  rm -f "${DNSMASQ_PID}"
fi

sudo pkill -f "dnsmasq .*wsn-dhcpv6-dnsmasq.conf" || true
sudo poff || true
