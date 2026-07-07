#!/bin/sh
# Apply cgroup v1 memory hard limit to all PIDs matching command names.
# Usage: cgroup-mem-limit <name> <mem_limit> [<memsw_limit>] [comm1,comm2,...]
# Limits can be suffixed with k/m/g (case-insensitive).

NAME="$1"
MEM_LIMIT="$2"
MEMSW_LIMIT="$3"
COMMS="$4"

[ -z "$NAME" ] || [ -z "$MEM_LIMIT" ] && { echo "usage: $0 <name> <mem_limit> [memsw_limit] [comm,..]"; exit 1; }

bytes() {
    local v="$1"
    v=$(echo "$v" | tr A-Z a-z)
    case "$v" in
        *k) echo $(( ${v%k} * 1024 )) ;;
        *m) echo $(( ${v%?} * 1024 * 1024 )) ;;
        *g) echo $(( ${v%?} * 1024 * 1024 * 1024 )) ;;
        *) echo "$v" ;;
    esac
}

MEM_BYTES=$(bytes "$MEM_LIMIT")
[ -n "$MEMSW_LIMIT" ] && MEMSW_BYTES=$(bytes "$MEMSW_LIMIT") || MEMSW_BYTES=""

CG="/sys/fs/cgroup/memory/limit_$NAME"
mkdir -p "$CG"

# Set physical hard limit first. Try memsw if kernel supports swap accounting.
echo "$MEM_BYTES" > "$CG/memory.limit_in_bytes"
if [ -n "$MEMSW_BYTES" ]; then
    [ "$MEMSW_BYTES" -lt "$MEM_BYTES" ] && MEMSW_BYTES=$MEM_BYTES
    if [ -w "$CG/memory.memsw.limit_in_bytes" ]; then
        echo "$MEMSW_BYTES" > "$CG/memory.memsw.limit_in_bytes" 2>/dev/null || true
    fi
fi

[ -n "$COMMS" ] || COMMS="$NAME"
OLDIFS="$IFS"
IFS=','
for comm in $COMMS; do
    IFS="$OLDIFS"
    for pid in $(pidof "$comm" 2>/dev/null); do
        [ "$pid" -eq 1 ] && continue
        [ "$pid" -eq $$ ] && continue
        echo "$pid" > "$CG/tasks" 2>/dev/null || true
    done
done
IFS="$OLDIFS"
