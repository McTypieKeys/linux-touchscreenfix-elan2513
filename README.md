# ELAN2513 touchscreen fix for Linux — Secure Boot + DKMS

An experimental, **hardware-specific** workaround for an ELAN2513 I²C-HID touchscreen that fails to initialize on an HP Pavilion 15-eg3xxx under Linux. It builds two minimally patched Ubuntu I²C-HID modules and a small ACPI enumeration-state helper using **DKMS**, signs them with an enrolled **Machine Owner Key (MOK)**, and starts a guarded probe retry through systemd. **No custom GRUB entry or ACPI SSDT overlay is required.**

> **Status (15 November 2026):** Confirmed working on one HP Pavilion Laptop 15-eg3xxx, Kubuntu 26.04, Linux `7.0.0-43-generic`, including normal reboots with UEFI Secure Boot **enabled**. The touchscreen and separate SYNA32EA touchpad both enumerate. **Operation following a future kernel update has not yet been verified.** This is not an upstream kernel patch or a general ELAN2513 solution.

## Tested configuration

| Item | Observed value |
| --- | --- |
| Machine | HP Pavilion Laptop 15-eg3xxx (replacement touchscreen panel) |
| Distribution | Kubuntu 26.04, KDE/Wayland |
| Kernel | `7.0.0-43-generic` |
| ACPI HID / exact path | `ELAN2513:00`, `\_SB_.PC00.I2C0.TPL1` |
| I²C controller / address | `i2c-0`, `0x10` |
| ACPI power resource | `PTPL`, exposed as `LNXPOWER:06` on tested system |
| Linux HID identity after successful probe | `2A94:A835` |
| Separate touchpad | `SYNA32EA:00 06CB:CE17` |
| Secure Boot | Enabled, DKMS modules signed by an enrolled MOK |

### Symptoms and successful result

Typical failure on an unpatched Linux boot:

```text
i2c_hid_acpi i2c-ELAN2513:00: failed to fetch HID descriptor: -121
i2c_hid_acpi i2c-ELAN2513:00: Failed to fetch the HID Descriptor
```

After the workaround:

```text
elan2513-enum: \_SB_.PC00.I2C0.TPL1 enumeration state 0 -> D3cold (4)
i2c_hid_acpi i2c-ELAN2513:00: ELAN2513: skipping SMBus pre-probe
input: ELAN2513:00 2A94:A835
hid-multitouch ... I2C HID v1.00 Device [ELAN2513:00 2A94:A835]
```

`libinput list-devices` reports **`Capabilities: touch`**, and physical touches respond. See [the kernel-developer investigation](docs/KERNEL-DEVELOPERS.md) for the ACPI/I²C evidence and proposed direction for an upstream fix.

## Read this first

- **Not a generic installer.** The helper refuses to modify an ACPI device unless its HID and full path match the tested machine. Check your hardware before doing anything. An HP Pavilion 15-eg series label alone is not sufficient.
- This package compiles and installs **out-of-tree kernel modules**. Use a backup, keep a USB mouse handy, and **retain a known-working kernel in GRUB Advanced Options**. Loading/replacing I²C-HID modules can temporarily disable the touchpad.
- Do **not** copy or publish a private MOK signing key. The scripts use the existing root-owned Ubuntu key at `/var/lib/shim-signed/mok/`; this repository contains no keys.
- The original SSDT-overlay experiment is **not used**. The kit works with a normal signed Ubuntu kernel and Secure Boot lockdown; do not combine it with the previous custom ACPI overlay.
- The installation is tested on **Ubuntu Linux 7.0.0-43** only. DKMS attempts automatic rebuilds for later kernels, but internal APIs may change. Do not assume the touchscreen will survive every upgrade without adapting the code.
- **If this device's actual ACPI path differs, stop.** The path guard is intentionally strict.

## Privacy and safe diagnostic sharing

The **HP model family, kernel version, ACPI namespace path, I²C bus/address, HID vendor/product IDs, and anonymized probe traces** above are included deliberately to help reproduce the bug. They are technical device descriptors, **not** a device serial number, account identifier, or MOK signing key. In combination with a public GitHub profile they may still reveal aspects of an individual's hardware configuration.

**Do not post unredacted command output** to GitHub issues. In particular, `uname -a` and `systemctl status` can display the computer hostname; `journalctl` records often include it; `modinfo -F signer` may reveal a personal or machine-specific certificate name. Before sharing diagnostics, remove hostnames, usernames, personal home paths, UUIDs, serial numbers, network addresses, email addresses, and unrelated logs. Never post `MOK.priv` or any other signing key. The provided `scripts/status.sh` suppresses signer names and avoids service-journal output by default, but **review its output before sharing**. The `.gitignore` reduces accidental commits but does not guarantee privacy if ignored files are forced into Git.

## Copy-paste installation guide (fresh Kubuntu 26.04)

These steps are intended for a **fresh installation** on the exact tested hardware, not for reinstalling over an already-installed `elan2513-combined/0.1` DKMS package. They do not modify GRUB. Run each numbered section separately and check its output before moving on.

### 1. Verify the kernel and hardware

Open Konsole and paste:

```bash
uname -r
cat /sys/bus/acpi/devices/ELAN2513:00/path
cat /sys/bus/acpi/devices/ELAN2513:00/power_state
mokutil --sb-state
```

Proceed **only** if the kernel is `7.0.0-43-generic` and the ACPI path prints exactly `\_SB_.PC00.I2C0.TPL1`. The power state may vary. If the ELAN2513 ACPI directory doesn't exist, this fix is not verified for your machine. If you are on a newer kernel, use [the developer notes](docs/KERNEL-DEVELOPERS.md) and adapt/test before installing.

### 2. Install packages and get the matching Ubuntu driver sources

```bash
sudo apt update
sudo apt install -y git dkms build-essential python3 \
  "linux-headers-$(uname -r)" linux-source-7.0.0 \
  mokutil shim-signed initramfs-tools libinput-tools

mkdir -p "$HOME/elan2513-linux-source"
tar -xf /usr/src/linux-source-7.0.0.tar.* -C "$HOME/elan2513-linux-source"
ls "$HOME/elan2513-linux-source/linux-source-7.0.0/drivers/hid/i2c-hid/i2c-hid-core.c"
```

The installer automatically patches *copies* of five driver source/header files and `drivers/hid/hid-ids.h`. It **does not rebuild the complete Linux kernel** and does not edit files in `/usr/src/linux-headers-*`. See [technical patch explanation](docs/KERNEL-DEVELOPERS.md).

### 3. Download the repository's dedicated branch

```bash
cd "$HOME"
git clone --branch secureboot-dkms-elan2513-fix --single-branch \
  https://github.com/McTypieKeys/linux-touchscreenfix-elan2513.git
cd linux-touchscreenfix-elan2513
```

If the repository is private, GitHub will require authenticated access. For other users to follow this guide, the repository owner must make the repository available to them. Review the scripts before executing as root.

### 4. Create/enroll the Ubuntu MOK (skip creation if already enrolled)

```bash
sudo test -s /var/lib/shim-signed/mok/MOK.priv && echo 'MOK private key present'
sudo test -s /var/lib/shim-signed/mok/MOK.der && echo 'MOK certificate present'
sudo mokutil --test-key /var/lib/shim-signed/mok/MOK.der
```

The desired text is `is already enrolled`. On the tested system `mokutil` oddly returned exit code 1 **despite** that positive message; the installer checks the **explicit enrollment message** instead of trusting only the return code. If the key is missing or **not enrolled**, use:

```bash
sudo update-secureboot-policy --new-key
sudo update-secureboot-policy --enroll-key
sudo reboot
```

If prompted, set a one-time password, select **Enroll MOK** in the blue MOK Manager screen during reboot, and confirm with that password. Repeat the enrollment check above **after reboot**. Do not proceed until it explicitly says `is already enrolled`. You can leave Secure Boot enabled throughout this process; Ubuntu may require the MOK enrollment reboot before signed custom modules can load.

### 5. Build, sign, and install the DKMS workaround

```bash
cd "$HOME/linux-touchscreenfix-elan2513"
sudo bash scripts/install.sh \
  "$HOME/elan2513-linux-source/linux-source-7.0.0"
```

The installer checks the machine path, Linux kernel family, MOK enrollment, and expected source layout. It:

1. Copies and minimally patches the driver source into `/usr/src/elan2513-combined-0.1/`.
2. Registers **three modules** with DKMS: `elan2513-enum`, `i2c-hid`, `i2c-hid-acpi`.
3. Builds and MOK-signs all three; keeps the original Ubuntu `.ko` files available to DKMS rollback.
4. Installs and enables `elan2513-dkms.service`, whose startup script retries the touchscreen probe **only** in the verified `D3cold`/`PTPL=0` state.
5. Installs an independent systemd **post-resume recovery hook** for suspend, using only the guarded ELAN2513 unbind/rebind sequence. This hook has not yet been tested automatically across sleep/wake cycles on the reported machine.
6. Regenerates the **normal** kernel initramfs. No GRUB entry or ACPI table is modified.

Check the result **before** rebooting:

```bash
sudo dkms status
for module in elan2513_enum i2c_hid i2c_hid_acpi; do
  echo "=== $module ==="
  modinfo -n "$module"
  test -n "$(modinfo -F signer "$module")" && echo "Signature present (signer redacted)" || echo "UNSIGNED"
done
systemctl is-enabled elan2513-dkms.service
```

Expect `elan2513-combined/0.1 ... installed`, each path under `/updates/dkms/`, **signature confirmation** for all three, and `enabled` for the service. `Original modules exist` in DKMS status is normal. If the build fails, inspect `/var/lib/dkms/elan2513-combined/0.1/build/make.log`; see [troubleshooting](docs/TROUBLESHOOTING.md).

### 6. Reboot **normal Kubuntu** and verify physical touch

```bash
sudo reboot
```

Do not choose a legacy `elan2513-fixed-*` GRUB entry from earlier experiments. After logging in, tap/drag the screen with your finger and verify:

```bash
cd "$HOME/linux-touchscreenfix-elan2513"
bash scripts/status.sh
sudo dkms status
sudo journalctl -u elan2513-dkms.service -b -o cat --no-pager
```

Look for `ELAN2513 attached`, libinput `Capabilities: touch`, and a successful service. The tested machine also retained its separate SYNA32EA touchpad. Device recognition alone is insufficient: **confirm physical touches work**.

### 7. Confirm Secure Boot is enforcing signatures

```bash
mokutil --sb-state
cat /sys/kernel/security/lockdown
for module in elan2513_enum i2c_hid i2c_hid_acpi; do
  test -n "$(modinfo -F signer "$module")" && echo "Signature present (signer redacted)" || echo "UNSIGNED"
done
```

Expect `SecureBoot enabled`, `[integrity]` selected in lockdown state, and a signature confirmation for each module. If your firmware still has Secure Boot disabled, enable it in the HP firmware settings and repeat the normal-boot test. Do not enable it before confirming MOK enrollment/signatures.

## Suspend/resume recovery (manual recovery confirmed; automatic hook awaits testing)

The initial DKMS solution initializes the touchscreen at boot, but **sleep/resume uncovered an additional problem** on the tested laptop. After waking, the driver remained attached but physical touch stopped responding. The kernel reported:

```text
i2c_hid_acpi i2c-ELAN2513:00: failed to change power setting.
i2c_hid_acpi i2c-ELAN2513:00: PM: dpm_run_callback(): acpi_subsys_resume returns -121
i2c_hid_acpi i2c-ELAN2513:00: PM: failed to resume async: error -121
```

The failed resume left the ACPI device in **D0** with **PTPL=1**. A controlled touchscreen-only unbind transitioned it to **D3cold / PTPL=0**, and a subsequent bind restored physical touch. The recovery hook at `systemd/elan2513-dkms-resume` automates **that tested sequence** after suspend. It checks the exact ACPI path, loaded helper, DKMS driver paths and binding, and will not rebind unless D3cold / PTPL=0 is reached. It does **not** unload drivers, touch the separate touchpad, patch GRUB, or require new module signatures. It executes after each applicable resume even if the touchscreen might already be working; there can be a short interruption while the device is reattached.

**Fresh installations using the updated installer include this hook automatically.** If the original DKMS fix is **already installed and working**, do not rerun the fresh installer. Instead, install only the hook:

```bash
# Keep your existing signed DKMS installation and known-working kernel.
if [ -d "$HOME/linux-touchscreenfix-elan2513/.git" ]; then
  git -C "$HOME/linux-touchscreenfix-elan2513" fetch origin secureboot-dkms-elan2513-fix
  git -C "$HOME/linux-touchscreenfix-elan2513" switch secureboot-dkms-elan2513-fix
  git -C "$HOME/linux-touchscreenfix-elan2513" pull --ff-only
else
  git clone --branch secureboot-dkms-elan2513-fix --single-branch \
    https://github.com/McTypieKeys/linux-touchscreenfix-elan2513.git \
    "$HOME/linux-touchscreenfix-elan2513"
fi

sudo install -d -m 0755 /usr/lib/systemd/system-sleep
sudo install -m 0755 \
  "$HOME/linux-touchscreenfix-elan2513/systemd/elan2513-dkms-resume" \
  /usr/lib/systemd/system-sleep/elan2513-dkms-resume
test -x /usr/lib/systemd/system-sleep/elan2513-dkms-resume && echo "Resume hook installed"
```

**Test:** Save open documents, keep a USB mouse available, and suspend normally using the desktop's Sleep menu or `systemctl suspend`. Wake the laptop, verify physical taps and drags, and inspect the hook's output:

```bash
sudo journalctl -b -u systemd-suspend.service -o cat --no-pager |
  grep 'elan2513-dkms-resume:' | tail -n 25
```

Success requires both a reattachment message and **physical touch working**. The manual unbind/rebind procedure is verified; **automatic invocation of this new hook has not yet been confirmed on the tested machine**. If the script fails or disrupts sleep, disable only the new hook (the normal boot fix remains intact):

```bash
sudo rm -f /usr/lib/systemd/system-sleep/elan2513-dkms-resume
```

The systemd system-sleep mechanism invokes executable hooks after resume, but these hooks are an explicitly experimental integration point; see [systemd-sleep documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd-sleep.html). This is a recovery workaround, **not an upstream root-cause fix**.

## Kernel upgrades and GRUB updates

**DKMS attempts** to rebuild/sign the three modules for a newly installed kernel when compatible headers are available (`AUTOINSTALL=yes`). It **does not** automatically fetch and adapt newer upstream I²C-HID source code. Our source was validated against `7.0.0-43-generic`; kernel changes may break compilation or behavior.

Before rebooting after an upgrade:

```bash
sudo dkms status
ls /lib/modules/$(uname -r)/updates/dkms/ 2>/dev/null || true
```

Inspect the `dkms status` row for the **new** installed kernel, not only the currently running kernel. If DKMS failed for the new kernel, **retain and boot your last known-working kernel** from GRUB Advanced Options. See [upgrade troubleshooting](docs/TROUBLESHOOTING.md). No custom GRUB entry is required; routine `update-grub` does not need to be patched for this fix.

## Uninstall / rollback

From a working normal Kubuntu boot:

```bash
cd "$HOME/linux-touchscreenfix-elan2513"
sudo bash scripts/uninstall.sh
sudo reboot
```

This disables the service, removes the DKMS package, and refreshes installed initramfs images; stock drivers are restored. **Without the workaround, the ELAN2513 touchscreen may fail again; keep a USB mouse available.** This script intentionally does not change GRUB defaults or firmware Secure Boot state. If you still have a historical custom-SSDT GRUB entry, rollback leaves it untouched.

## Developer resources

- [How the failure was diagnosed, kernel-level hypotheses, trace evidence, and upstream considerations](docs/KERNEL-DEVELOPERS.md)
- [Build, MOK, startup, and update troubleshooting](docs/TROUBLESHOOTING.md)
- [`scripts/prepare-sources.py`](scripts/prepare-sources.py): generates a standalone DKMS source tree from clean Ubuntu source, applying the **two driver patches** in-place to copies
- [`modules/elan2513-enum.c`](modules/elan2513-enum.c): guarded ACPI enumeration-state helper (no ACPI table override)
- [`modules/Makefile`](modules/Makefile), [`modules/dkms.conf`](modules/dkms.conf): three-module DKMS build recipe
- [`systemd/elan2513-dkms-start`](systemd/elan2513-dkms-start): guarded boot-time retry
- [`systemd/elan2513-dkms-resume`](systemd/elan2513-dkms-resume): guarded post-resume recovery; manual sequence verified, automatic hook pending validation

**Relevant upstream references:** [Linux ACPI non-D0 probing documentation](https://docs.kernel.org/firmware-guide/acpi/non-d0-probe.html), [Ubuntu Secure Boot and MOK documentation](https://documentation.ubuntu.com/security/security-features/platform-protections/secure-boot/), [DKMS](https://github.com/dell/dkms). For proper kernel integration, prefer a narrowly scoped DMI/ACPI quirk and tested power sequencing over a general-purpose bypass or global state mutation. This repository records a **field-validated workaround, not a reviewed root-cause fix**.

## AI assistance and disclaimer

This repository's documentation, shell/Python installation and maintenance scripts, DKMS packaging, ACPI helper module, and source-patching logic were drafted with assistance from **OpenAI ChatGPT (GPT-6)**. The troubleshooting process and the successful touchscreen behavior on the tested laptop were reported and verified by the device owner; the AI did not independently run the software on that machine.

**AI-generated code may contain errors, unsafe assumptions, or incompatibilities.** This is an experimental, hardware-specific workaround—not an official Linux kernel, Ubuntu, HP, or ELAN patch, and not independently audited or approved for upstream inclusion. Users and maintainers should inspect the source, confirm their hardware and kernel version, back up their systems, retain a known-working boot option, and test carefully. In particular, Secure Boot success and DKMS operation on the documented test kernel do **not** guarantee compatibility with later kernel versions. No warranty or fitness for a particular purpose is implied; see the repository license for terms.

## License and contributions

The helper and automation are provided under **GPL-2.0-only**, matching the kernel module licensing constraints; see [LICENSE](LICENSE). The Ubuntu kernel source code is **not** vendored here; users generate their own patched copies from distribution-provided sources. Issues containing ACPI paths, kernel versions, probe logs and DMI identifiers are useful, but please redact serial numbers, machine keys, personal identifiers and private signing material.
