# Troubleshooting and maintenance

This document is for the exact HP Pavilion 15-eg3xxx / ACPI `ELAN2513:00` `\_SB_.PC00.I2C0.TPL1` case documented in the main README. Keep a USB mouse available. The instructions below assume `elan2513-combined/0.1` and normal Kubuntu boot, not the older custom-SSDT GRUB entry.

## Privacy reminder

Do not paste raw `systemctl status`, `uname -a`, or full journal output into a public issue. These may reveal hostnames, users, paths, or unrelated system events. Commands below use `journalctl -o cat` to omit the usual hostname/timestamp prefix, but **review and redact all output before sharing**. Local MOK signer names can contain a computer name; report only whether signatures are present.

## Confirm installed state

```bash
cd "$HOME/linux-touchscreenfix-elan2513"
bash scripts/status.sh
sudo dkms status
sudo journalctl -u elan2513-dkms.service -b -o cat --no-pager
sudo journalctl -k -b -o cat --no-pager | grep -iE 'ELAN2513|HID descriptor|module verification|Key was rejected' | tail -60
```

Expected: three module paths in `updates/dkms`, nonempty `modinfo -F signer`, `ELAN2513 attached`, and libinput `Capabilities: touch`. Confirm **physical touches**, not just the input-device listing.

## Installer says MOK is missing or not enrolled

```bash
sudo ls -l /var/lib/shim-signed/mok/MOK.der /var/lib/shim-signed/mok/MOK.priv
sudo mokutil --test-key /var/lib/shim-signed/mok/MOK.der
```

On the tested release `mokutil` printed `is already enrolled` while returning exit status `1`; installer checks the positive message. A missing or un-enrolled certificate must not be bypassed. If necessary:

```bash
sudo update-secureboot-policy --new-key
sudo update-secureboot-policy --enroll-key
sudo reboot
```

Complete the blue MOK Manager enrollment using the one-time password before retrying the installer. This repository never stores keys.

## Build failed

```bash
sudo tail -n 100 /var/lib/dkms/elan2513-combined/0.1/build/make.log
sudo dkms status
```

The known troubleshooting history includes:

- `i2c-hid-acpi.h: No such file or directory`: the original experimental kit forgot this driver header. This repository's source-preparation script copies it.
- `../hid-ids.h: No such file or directory`: this header is under `drivers/hid/`, one level above `i2c-hid`; it is copied and relative includes rewritten.
- DKMS `make ... KERNELRELEASE=...` exit 2 with a Makefile hiding `all`: the corrected Makefile in this repository exposes `all` unconditionally and invokes kbuild in a separate invocation.
- `error: field ... not found` or unresolved ACPI symbols after a kernel upgrade: a Linux internal API may have changed. Keep the old working kernel, obtain matching new source, update the patch/build recipe and test before re-registering a new DKMS version.
- `warning: the compiler differs ...` with the **same** GCC version is not by itself a build failure; look for the first actual `error:` line.

## Touchscreen isn't attached after reboot

```bash
systemctl status elan2513-dkms.service --no-pager
sudo journalctl -u elan2513-dkms.service -b -o cat --no-pager
cat /sys/bus/acpi/devices/ELAN2513:00/power_state
cat /sys/bus/acpi/devices/LNXPOWER:06/resource_in_use
sudo journalctl -k -b -o cat --no-pager | grep -iE 'ELAN2513|hid.multitouch|HID descriptor' | tail -40
```

The startup script is guarded: it refuses to retry if the state isn't `D3cold` with `PTPL` inactive, if the patched driver isn't selected, or if the expected SMBus-bypass trace is missing. **Do not force-bind the device from D0 or while PTPL is active** merely to circumvent these checks.

If an earlier initramfs loads the distro module instead of DKMS, regenerate the initramfs after verifying DKMS installation:

```bash
sudo update-initramfs -u -k "$(uname -r)"
```

Reboot normally. Do not assume `modinfo -n` on disk proves which module image was already loaded by an earlier initramfs; check boot logs.

## Screen is unresponsive after waking from suspend

On the tested system, the kernel reported `acpi_subsys_resume returns -121` and the touchscreen stayed **bound** but did not respond. ACPI showed **D0 / PTPL=1**. Unbinding only the ELAN2513 transitioned to **D3cold / PTPL=0**; rebinding recovered touch. This observation does not prove the root cause and does not implicate the separate touchpad.

Check whether the new post-resume hook is installed:

```bash
test -x /usr/lib/systemd/system-sleep/elan2513-dkms-resume && echo installed || echo missing
sudo journalctl -b -u systemd-suspend.service -o cat --no-pager |
  grep 'elan2513-dkms-resume:' | tail -n 25
cat /sys/bus/acpi/devices/ELAN2513:00/power_state
cat /sys/bus/acpi/devices/LNXPOWER:06/resource_in_use
```

The script runs after supported suspend events (not before them) and unbinds the ELAN2513 if still attached, then attempts to rebind only after confirming the tested D3cold / PTPL=0 state. It does not interact with user-session services while systemd has frozen them. The device owner confirmed that the automatic hook restored physical touchscreen operation after a real sleep/wake cycle on 2026-11-16. Repeatability across additional cycles and kernel versions remains unverified.

If needed, disable only that hook (leave the verified boot DKMS installation in place):

```bash
sudo rm -f /usr/lib/systemd/system-sleep/elan2513-dkms-resume
```

Review log output for hostnames and unrelated identifiers before posting it in a public issue.

## Secure Boot rejects modules

```bash
mokutil --sb-state
cat /sys/kernel/security/lockdown
for m in elan2513_enum i2c_hid i2c_hid_acpi; do
  modinfo -n "$m"
  test -n "$(modinfo -F signer "$m")" && echo "Signature present (signer redacted)" || echo "UNSIGNED"
done
sudo journalctl -k -b -o cat --no-pager | grep -iE 'signature|verification|key was rejected|module' | tail -50
```

A nonempty signer field shows that a signature is present, **not** that Secure Boot accepted it. Verify the corresponding certificate is enrolled, that you booted through the normal Ubuntu shim chain, and that physical input works. Never disable signature enforcement or publish a private MOK key as a shortcut.

## New kernel installed

Before the first reboot, identify the newly installed version:

```bash
ls -d /lib/modules/*-generic | sort -V
sudo dkms status
```

Confirm `elan2513-combined/0.1` is `installed` for the **new** kernel; if it is not, inspect the matching DKMS build log. A successful build is not proof of runtime compatibility. **Keep the previously working kernel installed** and test touches, suspend/resume, and touchpad operation after each update. The DKMS sources copied at initial installation are based on the then-current Ubuntu driver source; refresh and review them when the distro driver API changes. Update this repository with carefully scoped changes and record exact kernel versions/results.

## GRUB upgrades and default entry

The workaround uses a normal Ubuntu kernel/initramfs and a systemd service. It never writes a custom GRUB menu entry. If you previously used an experimental `elan2513-fixed-*` entry, review your default:

```bash
grep '^GRUB_DEFAULT=' /etc/default/grub
sudo grub-editenv list
```

Select the normal Kubuntu entry as the default **only after confirming its actual GRUB menu identity**, and preserve a known-working kernel in Advanced Options. There is no need to disable Secure Boot to use the no-overlay signed-module fix.

## Uninstall

```bash
cd "$HOME/linux-touchscreenfix-elan2513"
sudo bash scripts/uninstall.sh
sudo reboot
```

This removes the DKMS package, service, and the kit-specific signing configuration, but leaves any unrelated MOK keys and user GRUB settings alone. The original Ubuntu I²C HID modules remain available. Expect the touchscreen problem to return until a kernel/firmware fix is applied.
