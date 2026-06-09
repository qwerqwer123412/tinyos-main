#!/usr/bin/env bash
set -euo pipefail

sudo pkill -f "dnsmasq .*wsn-dhcpv6-dnsmasq.conf" || true
sudo poff || true
