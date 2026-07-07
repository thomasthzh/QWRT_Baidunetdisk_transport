#!/bin/sh
# Migrate Alist binary + data from USB path to /overlay/alist (eMMC).
# Useful when the USB stick is unreliable or missing.

SRC="/mnt/usbdata/mnt/usbdata/alist"
[ ! -f "$SRC/alist" ] && SRC="/mnt/usbdata/alist"
DST="/overlay/alist"

if [ ! -f "$SRC/alist" ]; then
    echo "Alist binary not found at $SRC/alist. Abort."
    exit 1
fi

echo "Migrating Alist from $SRC to $DST"
mkdir -p "$DST"

cp -a "$SRC/alist" "$DST/alist"
chmod +x "$DST/alist"

if [ -d "$SRC/data" ]; then
    cp -a "$SRC/data" "$DST/data"
else
    mkdir -p "$DST/data"
fi

# Fix absolute paths inside config.json
CFG="$DST/data/config.json"
[ -f "$CFG" ] && sed -i 's|/mnt/usbdata/alist/data|/overlay/alist/data|g' "$CFG"

[ -f "$SRC/ip_limits.json" ] && cp -a "$SRC/ip_limits.json" "$DST/ip_limits.json"

# Point /usr/bin/alist to the overlay binary
rm -f /usr/bin/alist
ln -s "$DST/alist" /usr/bin/alist

echo "Alist migrated. Size: $(du -sh "$DST" | awk '{print $1}')"
echo "Restarting Alist..."
/etc/init.d/alist restart
sleep 2
pidof alist >/dev/null && echo "Alist is running." || echo "Alist failed to start."
