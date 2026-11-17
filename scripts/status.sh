#!/usr/bin/env bash
set -u
printf '%s\n' '=== Kernel / Secure Boot ==='
uname -r
mokutil --sb-state 2>/dev/null || true
cat /sys/kernel/security/lockdown 2>/dev/null || true
printf '\n=== ACPI overlay loaded? (should be NO on normal entry) ===\n'
journalctl -k -b --no-pager 2>/dev/null | grep 'Table Upgrade: install \[SSDT-  ELAN- DSC2513\]' | tail -n 1 || true
printf '\n=== Module paths and signatures ===\n'
for mod in elan2513_enum i2c_hid i2c_hid_acpi; do
  printf '%s : ' "$mod"
  modinfo -n "$mod" 2>/dev/null || echo not-found
  signer=$(modinfo -F signer "$mod" 2>/dev/null || true)
  if [[ -n $signer ]]; then
    echo '  signature: present (signer name withheld)'
  else
    echo '  signature: absent or unreadable'
  fi
done
printf '\n=== Service ===\n'
systemctl is-enabled elan2513-dkms.service 2>/dev/null || true
systemctl show elan2513-dkms.service --no-pager \
  --property=LoadState,ActiveState,SubState,Result,ExecMainStatus 2>/dev/null || true
printf '\n=== Post-resume recovery hook ===\n'
if [ -x /usr/lib/systemd/system-sleep/elan2513-dkms-resume ]; then
  echo 'installed (automatic suspend/resume recovery not yet confirmed on every system)'
else
  echo 'not installed'
fi
printf '\n=== Touchscreen state ===\n'
for file in /sys/bus/acpi/devices/ELAN2513:00/power_state /sys/bus/acpi/devices/LNXPOWER:06/resource_in_use; do
  [ ! -r "$file" ] || { printf '%s: ' "$file"; cat "$file"; }
done
if [ -L /sys/bus/i2c/devices/i2c-ELAN2513:00/driver ]; then
  echo 'ELAN2513 attached'
else
  echo 'ELAN2513 NOT attached'
fi
command -v libinput >/dev/null && sudo libinput list-devices | grep -A 12 -B 2 -i ELAN2513 || true
