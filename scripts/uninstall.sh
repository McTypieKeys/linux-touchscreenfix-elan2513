#!/usr/bin/env bash
# Remove only the candidate DKMS setup. Preserve earlier verified custom entry.
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
NAME=elan2513-combined
VERSION=0.1
SERVICE=/etc/systemd/system/elan2513-dkms.service
LOADER=/usr/local/sbin/elan2513-dkms-start
SLEEP_HOOK=/usr/lib/systemd/system-sleep/elan2513-dkms-resume
CONF=/etc/dkms/framework.conf.d/98-elan2513-mok.conf
SRC="/usr/src/$NAME-$VERSION"

systemctl disable --now elan2513-dkms.service 2>/dev/null || true
rm -f "$SERVICE" "$LOADER"
# Remove only the locally installed, explicitly identifiable ELAN2513 hook.
if [[ -f $SLEEP_HOOK ]] && grep -Fq 'ELAN2513: ACPI/I2C touchscreen resume recovery' "$SLEEP_HOOK"; then
  rm -f "$SLEEP_HOOK"
fi
systemctl daemon-reload
if command -v dkms >/dev/null; then
  dkms remove -m "$NAME" -v "$VERSION" --all || true
fi
# Delete only files we recognize as our own; never touch other DKMS config.
if [[ -f $CONF ]] && grep -Fq 'ELAN2513 kit:' "$CONF"; then
  rm -f "$CONF"
fi
if [[ -d $SRC ]] && [[ -f $SRC/elan2513-enum.c ]]; then
  rm -rf -- "$SRC"
fi
for kdir in /lib/modules/*; do
  [[ -d $kdir/build && -f /boot/initrd.img-${kdir##*/} ]] || continue
  update-initramfs -u -k "${kdir##*/}" || true
done
printf '\nCandidate DKMS setup removed. Original standalone GRUB touchscreen entry was not modified.\n'
printf 'Restart into the old dedicated GRUB entry if needed.\n'
