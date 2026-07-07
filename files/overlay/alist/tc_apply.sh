#!/bin/sh
IFACE=br-lan
DATA=/overlay/alist/ip_limits.json

apply() {
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc del dev $IFACE ingress 2>/dev/null

    tc qdisc add dev $IFACE root handle 1: htb default 2 || return 1
    tc class add dev $IFACE parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit || return 1
    tc class add dev $IFACE parent 1: classid 1:2 htb rate 1000mbit ceil 1000mbit || return 1
    tc filter add dev $IFACE protocol ip parent 1: prio 10 u32 match ip dst 0.0.0.0/0 flowid 1:2 2>/dev/null || true

    tc qdisc add dev $IFACE ingress || return 1

    [ -s "$DATA" ] || return 0
    local keys
    keys=$(jq -r 'keys[]' "$DATA" 2>/dev/null)
    [ -z "$keys" ] && return 0

    local id=10
    for ip in $keys; do
        local down up down_kbps up_kbps hex burst
        down=$(jq -r --arg ip "$ip" '.[$ip].down // 0' "$DATA")
        up=$(jq -r --arg ip "$ip" '.[$ip].up // 0' "$DATA")
        down_kbps=$((down * 8))
        up_kbps=$((up * 8))
        id=$((id + 1))
        hex=$(printf '%x' $id)
        if [ "$down_kbps" -gt 0 ]; then
            tc class add dev $IFACE parent 1: classid 1:$hex htb rate ${down_kbps}kbit ceil ${down_kbps}kbit 2>/dev/null || true
            tc filter add dev $IFACE protocol ip parent 1: prio 1 u32 match ip dst $ip flowid 1:$hex 2>/dev/null || true
        fi
        if [ "$up_kbps" -gt 0 ]; then
            burst=$((up / 8 + 64))
            tc filter add dev $IFACE parent ffff: protocol ip prio 1 u32 match ip src $ip police rate ${up_kbps}kbit burst ${burst}k drop flowid :1 2>/dev/null || true
        fi
    done
}

clear_rules() {
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc del dev $IFACE ingress 2>/dev/null
}

case "$1" in
    apply) apply ;;
    clear) clear_rules ;;
    *) echo "usage: $0 {apply|clear}" ;;
esac
