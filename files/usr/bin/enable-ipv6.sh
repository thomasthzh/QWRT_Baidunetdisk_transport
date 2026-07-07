#!/bin/sh
# Re-enable IPv6 (reverse router-purge.sh IPv6 changes)
# Packages removed by router-purge.sh are NOT reinstalled automatically.

rm -f /etc/sysctl.d/99-disable-ipv6.conf

# Re-enable immediately
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0
sysctl -w net.ipv6.conf.lo.disable_ipv6=0

uci delete network.lan.ipv6 2>/dev/null || true
uci delete network.wan.ipv6 2>/dev/null || true
uci set network.wan6.auto='1' 2>/dev/null || true
uci commit network

uci delete dhcp.lan.ra 2>/dev/null || true
uci delete dhcp.lan.dhcpv6 2>/dev/null || true
uci delete dhcp.lan.ndp 2>/dev/null || true
uci commit dhcp

/etc/init.d/odhcpd enable
/etc/init.d/odhcpd start
/etc/init.d/network restart

echo "IPv6 re-enabled."
