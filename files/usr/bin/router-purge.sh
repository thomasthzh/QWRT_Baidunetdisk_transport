#!/bin/sh
# DANGER: Aggressive purge for routers with very low RAM.
# Disables IPv6 and removes video/IPTV/unused LuCI apps and their daemons.
# Review the package list before running. Some VPN server packages are removed.

BACKUP_DIR="/root/router_purge_backup_$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/sysctl.d/99-memory.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/sysctl.d/99-disable-ipv6.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/config/network "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/config/dhcp "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/config/firewall "$BACKUP_DIR/" 2>/dev/null || true

echo "Backup saved to $BACKUP_DIR"

# 1. Disable IPv6
cat > /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
# Disable IPv6 to save memory on 415 MB router
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

echo "Applying IPv6 disable..."
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf

/etc/init.d/odhcpd disable 2>/dev/null || true
/etc/init.d/odhcpd stop 2>/dev/null || true
killall odhcp6c 2>/dev/null || true

uci set network.lan.ipv6='0' 2>/dev/null || true
uci set network.wan.ipv6='0' 2>/dev/null || true
uci set network.wan6.auto='0' 2>/dev/null || true
uci commit network

uci set dhcp.lan.ra='disabled' 2>/dev/null || true
uci set dhcp.lan.dhcpv6='disabled' 2>/dev/null || true
uci set dhcp.lan.ndp='disabled' 2>/dev/null || true
uci commit dhcp

# 2. Remove video/IPTV/unused packages
PKGS="
app-meta-hermes
luci-app-hermes
luci-i18n-hermes-zh-cn
luci-app-msd_lite
luci-i18n-msd_lite-zh-cn
msd_lite
luci-app-xupnpd
luci-i18n-xupnpd-zh-cn
xupnpd
luci-app-vsftpd
luci-i18n-vsftpd-zh-cn
vsftpd-alt
luci-app-usb-printer
luci-i18n-usb-printer-zh-cn
kmod-usb-printer
luci-app-ttyd
luci-i18n-ttyd-zh-cn
ttyd
luci-app-vlmcsd
luci-i18n-vlmcsd-zh-cn
vlmcsd
luci-app-wolplus
luci-i18n-wolplus-zh-cn
luci-app-autoreboot
luci-i18n-autoreboot-zh-cn
luci-app-samba
luci-i18n-samba-zh-cn
luci-i18n-samba-en
autosamba
samba36-server
wsdd2
luci-app-accesscontrol
luci-i18n-accesscontrol-zh-cn
luci-app-arpbind
luci-i18n-arpbind-zh-cn
luci-app-filetransfer
luci-i18n-filetransfer-zh-cn
luci-app-ipsec-server
luci-i18n-ipsec-server-zh-cn
iptables-mod-ipsec
kmod-ipt-ipsec
kmod-ipsec
kmod-ipsec4
kmod-ipsec6
strongswan-ipsec
strongswan-mod-kernel-libipsec
strongswan
strongswan-charon
strongswan-minimal
strongswan-mod-aes
strongswan-mod-gmp
strongswan-mod-hmac
strongswan-mod-kernel-netlink
strongswan-mod-nonce
strongswan-mod-openssl
strongswan-mod-pubkey
strongswan-mod-random
strongswan-mod-sha1
strongswan-mod-socket-default
strongswan-mod-stroke
strongswan-mod-updown
strongswan-mod-x509
strongswan-mod-xauth-generic
strongswan-mod-xcbc
luci-app-openvpn-server
luci-i18n-openvpn-server-zh-cn
"

echo "Removing packages..."
for p in $PKGS; do
    if opkg list-installed | grep -q "^$p -"; then
        echo "  -> $p"
        opkg remove --force-removal-of-dependent-packages --autoremove "$p" 2>&1 | tail -3
    fi
done

echo "Final autoremove..."
opkg autoremove 2>&1 | tail -10 || true

# 3. Restart network
echo "Restarting network..."
/etc/init.d/network restart

# 4. Clean stale init symlinks
for svc in vsftpd xupnpd wsdd2 ttyd msd_lite usb_printer samba vlmcsd etherwake; do
    rm -f /etc/rc.d/S"*""$svc" 2>/dev/null || true
    rm -f /etc/rc.d/K"*""$svc" 2>/dev/null || true
done

echo
echo "=== Done ==="
echo "IPv6 disabled: $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)"
echo "Memory:"
free -h
