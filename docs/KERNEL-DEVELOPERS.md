# Kernel developer notes: HP Pavilion ELAN2513 I²C HID probe failure

**Scope:** Reproducible on one HP Pavilion Laptop 15-eg3xxx with a replacement touchscreen panel, Kubuntu 26.04, kernel `7.0.0-43-generic`. The no-overlay, DKMS/MOK-signed workaround was tested with Secure Boot enabled on 2026-11-15. This is an **empirical workaround**, not a proven generic kernel fix. Kernel upgrades beyond the tested release are not yet validated.

## Hardware / descriptor

- ACPI device: `ELAN2513:00`, **full ACPI namespace path** `\_SB_.PC00.I2C0.TPL1`, HID `ELAN2513`, CID `PNP0C50`.
- I²C DesignWare controller `i2c-0`, slave `0x10`, HID descriptor register address `0x0001`.
- Successful Linux HID ID: `2A94:A835`, with `hid-multitouch` and `libinput` touch capability, screen size about 320×180 mm.
- Independent Synaptics touchpad: `SYNA32EA:00`, `06CB:CE17`. Avoid disabling its functionality while fixing the touchscreen.
- Windows and UEFI firmware can drive the touchscreen. Windows exposes an I2C HID Device (`ACPI\ELAN2513\0`) and HID touchscreen collections (`HID\ELAN2513&COL01` and `COL02`).

Successful raw 30-byte HID descriptor, when unbound and observed in the appropriate ACPI state:

```text
1e 00 00 01 a3 01 21 00 24 00 3f 00 e7 00 3f 00
22 00 23 00 94 2a 35 a8 05 3f 00 00 00 00
```

This decodes to vendor/product `2A94:A835` and later agrees with the successfully attached `hid-multitouch` device. Do not assume a different vendor/product from a similarly named ELAN2513 controller applies to every replacement panel.

## Failure / decisive observations

Unpatched `i2c_hid_acpi` cannot attach:

```text
i2c_hid_acpi i2c-ELAN2513:00: failed to fetch HID descriptor: -121
i2c_hid_acpi i2c-ELAN2513:00: Failed to fetch the HID Descriptor
```

`-121` is `-EREMOTEIO`. `ftrace` showed the same two-message I²C transaction in the failing driver and successful manual `i2ctransfer`: write two bytes `[01 00]` followed by read 30 bytes, with manual `ret=2` and kernel attempt `ret=-121`. This makes a simple transaction-format issue unlikely, but not impossible.

ACPI power resource `\_SB.PC00.I2C0.PTPL` (`/sys/bus/acpi/devices/LNXPOWER:06` on the tested machine) is referenced by `_PR0` and `_PR3` for `TPL1`. Tracing one failed probe showed:

```text
TPL1._CRS
PTPL._ON -> PON
TPL1._PS0 -> PS0X
TPL1._DSM
HID descriptor read -> -121
TPL1._PS3 -> PS3X
PTPL._OFF -> POFF
```

The power-resource methods manipulate GPIO-related fields via `SGOV`/`SGRA`, with short timing delays. Manual descriptor reads often succeed after the failed probe, when sysfs reports `D3cold`, `PTPL/resource_in_use=0`. With the HID module blocked at boot the same system could initially show `D0`, `PTPL=1`, and manual descriptor reads fail. **These are correlations, not a complete root-cause proof.**

A manually retried driver bind after the initial failure, from `D3cold`/`PTPL=0`, succeeded once a non-D0-aware `i2c_hid_acpi` and SMBus-bypassing core were installed. Physical touch input worked, not just HID enumeration.

## Three components of the proven workaround

1. **Scoped SMBus pre-probe bypass** in `drivers/hid/i2c-hid/i2c-hid-core.c`: only when `client->name == "ELAN2513:00"`, skip `i2c_hid_probe_address(ihid)`. A direct initial SMBus byte probe returned `ENXIO` in prior tests. Later HID descriptor read still failed without the power-state handling, so this alone is insufficient.
2. **Non-D0 probe opt-in** in the initializer for `i2c_hid_acpi_driver` in `drivers/hid/i2c-hid/i2c-hid-acpi.c`: `.flags = I2C_DRV_ACPI_WAIVE_D0_PROBE`. See [Linux kernel non-D0 documentation](https://docs.kernel.org/firmware-guide/acpi/non-d0-probe.html).
3. **Strictly guarded enumeration-state helper**, `modules/elan2513-enum.c`, finds only the ACPI `ELAN2513` whose full pathname is `\_SB_.PC00.I2C0.TPL1`, then changes `adev->power.state_for_enumeration` from `0` to `ACPI_STATE_D3_COLD (4)`. This emulates an ACPI `_DSC` desired enumeration state in memory **without** inserting an ACPI SSDT. A systemd oneshot service performs at most one guarded bind retry when the device is unbound in `D3cold` and `PTPL=0`.

The helper is **not an approved upstream interface**. It directly touches an internal `struct acpi_device` field, which can change, and carries lifetime/race assumptions. In the tested configuration the helper remained loaded while the override was in effect and restored the previous field on unload.

### Captured successful log

```text
elan2513-enum: \_SB_.PC00.I2C0.TPL1 enumeration state 0 -> D3cold (4)
i2c_hid_acpi i2c-ELAN2513:00: ELAN2513: skipping SMBus pre-probe
input: ELAN2513:00 2A94:A835 as .../i2c-ELAN2513:00/.../input
hid-multitouch ... I2C HID v1.00 Device [ELAN2513:00 2A94:A835]
```

The user subsequently confirmed the no-overlay method works after repeated normal Kubuntu reboots **with Secure Boot enabled**. DKMS built and MOK-signed `elan2513-enum`, `i2c-hid`, `i2c-hid-acpi` modules for `7.0.0-43-generic`.

## Suspend/resume regression and empirically verified recovery

On 2026-11-16, a sleep/wake test revealed an additional failure distinct from initial boot probing:

```text
i2c_hid_acpi i2c-ELAN2513:00: failed to change power setting.
i2c_hid_acpi i2c-ELAN2513:00: PM: dpm_run_callback(): acpi_subsys_resume returns -121
i2c_hid_acpi i2c-ELAN2513:00: PM: failed to resume async: error -121
```

Despite remaining bound to `i2c_hid_acpi`, the touchscreen stopped responding. After resume the device reported D0 and `PTPL/resource_in_use=1`. Unbinding **only** `i2c-ELAN2513:00` from `/sys/bus/i2c/drivers/i2c_hid_acpi/unbind` caused D3cold and PTPL=0; binding it again through `.../bind` successfully restored HID enumeration **and physical touch**. No I²C-HID modules were unloaded, the independent Synaptics touchpad was left alone, and Secure Boot remained enabled.

The repository now contains `systemd/elan2513-dkms-resume` to perform this **hardware-specific** recovery after resume, with path/module/power guards and a single bind. The *manual operation* was tested; **the automatic sleep hook itself remains to be validated on the actual laptop**.

This finding warrants upstream attention to ACPI/I²C-HID PM callbacks and the different power-resource states reached after resume, not just initial enumeration. A correct in-kernel solution should handle the faulty power transition without a userspace sysfs rebind or fragile internal ACPI state mutation. **Avoid copying a raw resume log into a public issue without redacting identifying fields.**

## What was tried and did not solve the issue

- BIOS upgrade, disabling Windows Fast Startup, cold shutdown, earlier Linux kernel and live ISO, `acpi_osi="Windows 2020"`.
- Skipping `i2c_hid_probe_address()` **without** further power changes.
- Additional 500 ms post-power-up delay.
- Manually invoking `PTPL._OFF` during the core `power_up` callback (also a dangerous mismatch with ACPI power-resource accounting): descriptor still failed.
- Calling `acpi_device_set_power(..., ACPI_STATE_D3_COLD)` just before the core probe: not early enough, failed.
- Adding an early initrd SSDT implementing `_DSC` proved a useful **diagnostic** when combined with an appropriate second probe, but initramfs ACPI table overrides are blocked by Linux lockdown under Secure Boot. Hence the no-overlay helper.

## Suggestions for a proper upstream fix

A future fix should avoid shipping `struct acpi_device` field writes via an unrelated standalone module. Potential avenues requiring review and experiment:

- Identify the exact difference between firmware-reported ACPI power sequencing and the state that permits the I²C HID descriptor read; validate reset/interrupt GPIO levels and timing through ACPI tracing and logic analysis.
- Develop a narrowly scoped ACPI/I²C quirk keyed by ACPI HID + DMI/system identification + relevant path; this is **not** evidence for bypassing SMBus probing globally.
- Handle the enumeration power-state policy at the time ACPI/I²C normally performs its first probe, rather than relying on a late systemd rebind.
- Audit ACPI power reference counting and suspend/resume so the device is not inadvertently left without required power, especially across firmware/BIOS revisions and alternate panels.
- Test with both replacement and original panels and with the independent SYNA32EA touchpad.

**Important uncertainty:** The result strongly implicates the boot-time ACPI power-state transition, but does *not* prove `PTPL._ON` alone is faulty or that keeping all ELAN2513 devices in D3cold is universally safe. Please do not forward-port this as a blanket kernel quirk without additional evidence.

## Reproduce and gather reports

```bash
uname -r
cat /sys/bus/acpi/devices/ELAN2513:00/path
cat /sys/bus/acpi/devices/ELAN2513:00/power_state
cat /sys/bus/acpi/devices/LNXPOWER:06/resource_in_use
sudo journalctl -k -b -o cat --no-pager | grep -iE 'ELAN2513|hid.multitouch|HID descriptor' | tail -40
sudo libinput list-devices | grep -A12 -B2 -i ELAN2513
sudo dkms status
```

Even with `-o cat`, logs can contain device-specific paths and identifiers; review and redact before posting. Do not post DMI serial numbers, full `dmidecode` outputs without redaction, private signing keys, or privileged device dumps containing unrelated data. Note exact BIOS, kernel, source-package versions, whether this is a replacement panel, and whether touch input physically works.
