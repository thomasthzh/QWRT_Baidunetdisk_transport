#!/bin/sh
# Aggressive memory optimization for QWRT AX1800 Pro (415 MB RAM)
# This script disables clearly unused services, tunes netdata/dnsmasq/sysctl,
# and adds cgroup limits for potential heavy services.

BACKUP_DIR="/root/router_opt_backup_$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/netdata/netdata.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/sysctl.d/99-memory.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/config/dhcp "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/config/system "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/init.d/cgroup_mem_limits "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/crontabs/root "$BACKUP_DIR/" 2>/dev/null || true

echo "Backup saved to $BACKUP_DIR"

# 1. Remove duplicate usb_swap symlink from previous iterations
rm -f /etc/rc.d/S40usb_swap

# 2. Disable and stop clearly unnecessary services
UNUSED="vsftpd xupnpd wsdd2 ttyd msd_lite etherwake relayd usb_printer lacpd hyfi-bridging rstp diag_socket_app linksys_recovery autoreboot conntrackd"
for svc in $UNUSED; do
    if [ -f "/etc/init.d/$svc" ]; then
        echo "Disabling $svc"
        /etc/init.d/$svc disable 2>/dev/null || true
        /etc/init.d/$svc stop 2>/dev/null || true
    fi
done

# 3. Optionally disable samba + kms (Windows share / activation) to save ~6 MB
# These can be re-enabled later if needed.
for svc in samba kms; do
    if [ -f "/etc/init.d/$svc" ]; then
        echo "Disabling $svc"
        /etc/init.d/$svc disable 2>/dev/null || true
        /etc/init.d/$svc stop 2>/dev/null || true
    fi
done

# 4. Tune netdata: reduce history, disable tc plugin
cat > /etc/netdata/netdata.conf <<'EOF'
[global]
	update every = 2
	history = 1800
	memory deduplication (ksm) = no
	debug log = syslog
	error log = syslog
	access log = none
	run as user = root

[web]
	allow connections from = localhost 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.*
	allow dashboard from = localhost 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.*

[plugins]
	cgroups = no
	apps = no
	charts.d = no
	fping = no
	node.d = no
	python.d = no
	tc = no

[health]
	enabled = no

[plugin:proc:ipc]
	shared memory totals = no
EOF

# 5. Tune dnsmasq
cachesize=$(uci get dhcp.@dnsmasq[0].cachesize 2>/dev/null || echo "")
[ -z "$cachesize" ] && uci set dhcp.@dnsmasq[0].cachesize='256'
uci set dhcp.@dnsmasq[0].local_ttl='60'
uci commit dhcp

# 6. Reduce system log buffer
uci set system.@system[0].log_size='32'
uci set system.@system[0].conloglevel='7'
uci set system.@system[0].cronloglevel='7'
uci commit system

# 7. Extended sysctl tuning
cat > /etc/sysctl.d/99-memory.conf <<'EOF'
# Memory tuning for 415 MB QWRT router
vm.swappiness=60
vm.vfs_cache_pressure=80
vm.oom_kill_allocating_task=1
vm.panic_on_oom=0
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.min_free_kbytes=8192

# Connection tracking / network buffers
net.netfilter.nf_conntrack_max=16384
net.netfilter.nf_conntrack_expect_max=512
net.core.netdev_max_backlog=1024
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_max_tw_buckets=4096
net.ipv4.tcp_mem=8192 12288 16384
net.ipv4.udp_mem=8192 12288 16384

# ARP cache
net.ipv4.neigh.default.gc_thresh1=512
net.ipv4.neigh.default.gc_thresh2=1024
net.ipv4.neigh.default.gc_thresh3=2048
EOF

# 8. Update cgroup memory limits script to cover more heavy services
cat > /etc/init.d/cgroup_mem_limits <<'EOF'
#!/bin/sh /etc/rc.common
# Apply cgroup memory hard limits to heavy services.
# Runs late at boot and is re-triggered every minute by cron to catch respawns.
START=99
STOP=10

start() {
    sleep 5
    # Core user services already running
    /usr/bin/cgroup-mem-limit.sh kaiplus 256m 384m kaiplus_bin
    /usr/bin/cgroup-mem-limit.sh cloudflared 128m 192m cloudflared
    /usr/bin/cgroup-mem-limit.sh homebox 128m 192m homebox
    /usr/bin/cgroup-mem-limit.sh netdata 96m 128m netdata
    /usr/bin/cgroup-mem-limit.sh alist 192m 256m alist
    /usr/bin/cgroup-mem-limit.sh dockerd 192m 256m dockerd

    # Proxy / VPN / download services (even if currently disabled, limits them if re-enabled)
    /usr/bin/cgroup-mem-limit.sh clash 128m 192m clash
    /usr/bin/cgroup-mem-limit.sh openclash 128m 192m clash_meta
    /usr/bin/cgroup-mem-limit.sh ssr 64m 96m ssr-redir
    /usr/bin/cgroup-mem-limit.sh openvpn 64m 96m openvpn
    /usr/bin/cgroup-mem-limit.sh frpc 64m 96m frpc
    /usr/bin/cgroup-mem-limit.sh zerotier 96m 128m zerotier-one
    /usr/bin/cgroup-mem-limit.sh qbittorrent 256m 384m qbittorrent-nox

    # Optional services (some disabled above; limits remain for safety)
    /usr/bin/cgroup-mem-limit.sh samba 128m 192m smbd,nmbd
    /usr/bin/cgroup-mem-limit.sh kms 32m 48m vlmcsd
    /usr/bin/cgroup-mem-limit.sh xupnpd 64m 96m xupnpd
    /usr/bin/cgroup-mem-limit.sh ttyd 64m 96m ttyd
    /usr/bin/cgroup-mem-limit.sh msd_lite 64m 96m msd_lite
    /usr/bin/cgroup-mem-limit.sh wsdd2 32m 48m wsdd2
    /usr/bin/cgroup-mem-limit.sh vsftpd 32m 48m vsftpd
}

stop() {
    true
}
EOF
chmod +x /etc/init.d/cgroup_mem_limits

# 9. Apply changes
echo "Applying sysctl..."
sysctl -p /etc/sysctl.d/99-memory.conf >/dev/null 2>&1

echo "Restarting tuned services..."
/etc/init.d/log restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/netdata restart >/dev/null 2>&1 || true
/etc/init.d/cgroup_mem_limits start >/dev/null 2>&1 || true

# 10. Print summary
echo
echo "=== Optimization applied ==="
echo "Disabled services: $UNUSED samba kms"
echo "Backup: $BACKUP_DIR"
echo
echo "=== current memory ==="
free -h
