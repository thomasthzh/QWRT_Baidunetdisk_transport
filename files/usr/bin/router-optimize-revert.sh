#!/bin/sh
# Re-enable services disabled by router-optimize.sh
# Usage: router-optimize-revert.sh [backup_dir]

BACKUP_DIR="${1:-/root/router_opt_backup_*}"
# If glob matches multiple, pick latest
if [ -d "$BACKUP_DIR" ]; then
    true
else
    BACKUP_DIR=$(ls -d /root/router_opt_backup_* 2>/dev/null | tail -1)
fi

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    echo "Restoring configs from $BACKUP_DIR"
    [ -f "$BACKUP_DIR/netdata.conf" ] && cp "$BACKUP_DIR/netdata.conf" /etc/netdata/netdata.conf
    [ -f "$BACKUP_DIR/99-memory.conf" ] && cp "$BACKUP_DIR/99-memory.conf" /etc/sysctl.d/99-memory.conf
    [ -f "$BACKUP_DIR/dhcp" ] && cp "$BACKUP_DIR/dhcp" /etc/config/dhcp
    [ -f "$BACKUP_DIR/system" ] && cp "$BACKUP_DIR/system" /etc/config/system
    [ -f "$BACKUP_DIR/cgroup_mem_limits" ] && cp "$BACKUP_DIR/cgroup_mem_limits" /etc/init.d/cgroup_mem_limits
    [ -f "$BACKUP_DIR/root" ] && cp "$BACKUP_DIR/root" /etc/crontabs/root
fi

for svc in vsftpd xupnpd wsdd2 ttyd msd_lite etherwake relayd usb_printer lacpd hyfi-bridging rstp diag_socket_app linksys_recovery autoreboot conntrackd samba kms; do
    if [ -f "/etc/init.d/$svc" ]; then
        echo "Re-enabling $svc"
        /etc/init.d/$svc enable 2>/dev/null || true
        /etc/init.d/$svc start 2>/dev/null || true
    fi
done

echo "Applying restored sysctl..."
sysctl -p /etc/sysctl.d/99-memory.conf >/dev/null 2>&1 || true

/etc/init.d/log restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/netdata restart >/dev/null 2>&1 || true
/etc/init.d/cgroup_mem_limits start >/dev/null 2>&1 || true

echo "Revert done."
free -h
