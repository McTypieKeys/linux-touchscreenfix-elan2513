#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Install this exact tested-family workaround using matching Ubuntu kernel source.
set -Eeuo pipefail
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'Run via sudo bash scripts/install.sh /path/to/linux-source'
[[ $# == 1 ]] || fail 'Pass the extracted Ubuntu Linux source root as one argument.'
ROOT=$(cd -- "$1" && pwd)
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
NAME=elan2513-combined
VERSION=0.1
DEST="/usr/src/$NAME-$VERSION"
MOK_PRIV=/var/lib/shim-signed/mok/MOK.priv
MOK_DER=/var/lib/shim-signed/mok/MOK.der
CONF=/etc/dkms/framework.conf.d/98-elan2513-mok.conf
SERVICE=/etc/systemd/system/elan2513-dkms.service
LOADER=/usr/local/sbin/elan2513-dkms-start
SLEEP_HOOK=/usr/lib/systemd/system-sleep/elan2513-dkms-resume
KVER=$(uname -r)

for cmd in python3 dkms mokutil modinfo update-initramfs systemctl; do
    command -v "$cmd" >/dev/null || fail "Missing $cmd; see README dependencies."
done
[[ -d "/lib/modules/$KVER/build" ]] || fail "Missing headers for running kernel $KVER"
[[ $KVER == 7.0.0-* ]] || fail "Validated on 7.0.0-43-generic; refusing first install on $KVER without review."
[[ -s $MOK_PRIV && -s $MOK_DER ]] || fail 'Ubuntu module-signing MOK is missing; see README enrollment steps.'
# Some Ubuntu mokutil versions print positive enrollment but return exit 1.
# Accept a positive result only; do not bypass a missing or rejected certificate.
mok_status=0
mok_result=$(mokutil --test-key "$MOK_DER" 2>&1) || mok_status=$?
if [[ $mok_status -ne 0 && $mok_result != *' is already enrolled'* ]]; then
    fail "MOK not verified (status $mok_status): $mok_result"
fi
if [[ $mok_result != *' is already enrolled'* ]]; then
    fail "MOK is not confirmed enrolled (status $mok_status): $mok_result"
fi
printf 'MOK: %s\n' "$mok_result"

[[ ! -e $DEST ]] || fail "$DEST already exists. Do not overwrite a working DKMS installation."
[[ ! -e $CONF ]] || fail "$CONF already exists. Review before installing."
[[ ! -e $SERVICE && ! -e $LOADER ]] || fail 'Service or loader already exists; review before installing.'
[[ ! -e $SLEEP_HOOK ]] || fail 'Resume hook already exists; review before installing.'
[[ -d /sys/bus/acpi/devices/ELAN2513:00 ]] || fail 'ELAN2513 ACPI device not found'
actual=$(cat /sys/bus/acpi/devices/ELAN2513:00/path)
[[ $actual == '\_SB_.PC00.I2C0.TPL1' ]] || fail "Unsupported touchscreen path $actual"
# Stage before writing to /usr/src; source check refuses unknown kernel source changes.
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT
python3 "$HERE/scripts/prepare-sources.py" --source-root "$ROOT" --dest "$STAGE/prepared"
install -d -m 0755 "$DEST"
cp -a "$STAGE/prepared/." "$DEST/"
chmod 0644 "$DEST"/*
# Private signing key stays in /var/lib/shim-signed/mok. Never copy it.
install -d -m 0755 /etc/dkms/framework.conf.d
cat > "$CONF" <<'EOF'
# ELAN2513 kit: use already-enrolled Ubuntu module-signing MOK.
mok_signing_key="/var/lib/shim-signed/mok/MOK.priv"
mok_certificate="/var/lib/shim-signed/mok/MOK.der"
EOF
chmod 0644 "$CONF"

echo '=== DKMS add/build/install ==='
dkms add -m "$NAME" -v "$VERSION"
dkms build -m "$NAME" -v "$VERSION" -k "$KVER"
dkms install -m "$NAME" -v "$VERSION" -k "$KVER"
for mod in elan2513_enum i2c_hid i2c_hid_acpi; do
    path=$(modinfo -n "$mod")
    [[ $path == *'/updates/dkms/'* ]] || fail "$mod not selected from DKMS: $path"
    signer=$(modinfo -F signer "$mod")
    [[ -n $signer ]] || fail "$mod is unsigned"
    echo "$mod: $path (signed by $signer)"
done
install -m 0755 "$HERE/systemd/elan2513-dkms-start" "$LOADER"
install -m 0644 "$HERE/systemd/elan2513-dkms.service" "$SERVICE"
install -d -m 0755 /usr/lib/systemd/system-sleep
install -m 0755 "$HERE/systemd/elan2513-dkms-resume" "$SLEEP_HOOK"
systemctl daemon-reload
systemctl enable elan2513-dkms.service
update-initramfs -u -k "$KVER"
echo 'Installed for normal Kubuntu boot. Read README before rebooting.'
