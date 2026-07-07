#!/bin/sh
# Allow SSH/LuCI management from a specific campus/office subnet.
# Usage: allow-campus-access.sh 10.23.118.0/24

SUBNET="${1:-10.23.118.0/24}"

echo "Allowing management access from $SUBNET"

uci add firewall rule >/dev/null
uci set firewall.@rule[-1].name='allow-ssh-campus'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].src_ip="$SUBNET"
uci set firewall.@rule[-1].dest_port='22'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule >/dev/null
uci set firewall.@rule[-1].name='allow-http-campus'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].src_ip="$SUBNET"
uci set firewall.@rule[-1].dest_port='80'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
/etc/init.d/firewall restart

echo "Done. You can now access:"
echo "  SSH:    ssh root@<路由器WAN_IP>"
echo "  Web:    http://<路由器WAN_IP>"
