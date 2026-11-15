#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build a standalone DKMS source tree from matching Ubuntu Linux sources.

This is intentionally strict: changes to upstream driver layouts should fail
rather than silently installing an untested patch.
"""
import argparse
from pathlib import Path
import re
import shutil
import sys

FILES = (
    'i2c-hid-core.c',
    'i2c-hid-acpi.c',
    'i2c-hid-dmi-quirks.c',
    'i2c-hid.h',
    'i2c-hid-acpi.h',
)


def patch_core(text: str) -> str:
    if 'PTPL._OFF completed' in text or 'ELAN2513: waiting 500 ms' in text:
        raise ValueError('failed earlier ELAN2513 power experiments detected; use clean Ubuntu source')
    if 'ELAN2513: skipping SMBus pre-probe' in text:
        return text
    match = list(re.finditer(r'(?m)^([ \t]*)ret\s*=\s*i2c_hid_probe_address\(ihid\);[ \t]*$', text))
    if len(match) != 1:
        raise ValueError(f'expected exactly one i2c_hid_probe_address() assignment, found {len(match)}')
    indent = match[0].group(1)
    replacement = '\n'.join([
        f'{indent}if (!strcmp(client->name, "ELAN2513:00")) {{',
        f'{indent}\tdev_info(&client->dev, "ELAN2513: skipping SMBus pre-probe\\n");',
        f'{indent}\tret = 0;',
        f'{indent}}} else {{',
        f'{indent}\tret = i2c_hid_probe_address(ihid);',
        f'{indent}}}',
    ])
    text = text[:match[0].start()] + replacement + text[match[0].end():]
    if '#include <linux/string.h>' not in text:
        first_include = re.search(r'(?m)^#include <[^>]+>\s*$', text)
        if not first_include:
            raise ValueError('no #include found in i2c-hid-core.c')
        text = text[:first_include.start()] + '#include <linux/string.h>\n' + text[first_include.start():]
    return text


def patch_acpi(text: str) -> str:
    if 'D3cold-before-probe' in text or 'PTPL._OFF completed' in text:
        raise ValueError('failed earlier experimental power patch detected; use clean Ubuntu sources')
    if 'I2C_DRV_ACPI_WAIVE_D0_PROBE' in text:
        return text
    pat = re.compile(r'(?m)^(static struct i2c_driver i2c_hid_acpi_driver\s*=\s*\{[ \t]*)$')
    matches = list(pat.finditer(text))
    if len(matches) != 1:
        raise ValueError(f'expected one i2c_hid_acpi_driver declaration, found {len(matches)}')
    match = matches[0]
    return text[:match.end()] + '\n\t.flags = I2C_DRV_ACPI_WAIVE_D0_PROBE,' + text[match.end():]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-root', required=True, type=Path)
    ap.add_argument('--dest', required=True, type=Path)
    args = ap.parse_args()
    root = args.source_root.expanduser().resolve()
    driver = root / 'drivers/hid/i2c-hid'
    if root.name == 'i2c-hid' and (root / 'i2c-hid-core.c').exists():
        driver = root
    dest = args.dest
    if dest.exists():
        sys.exit(f'refusing to overwrite existing directory: {dest}')
    missing = [str(driver / p) for p in FILES if not (driver / p).is_file()]
    hid_ids = driver.parent / 'hid-ids.h'
    if not hid_ids.is_file():
        hid_ids = driver / 'hid-ids.h'
    if not hid_ids.is_file():
        missing.append(str(hid_ids))
    if missing:
        sys.exit('missing Linux source files:\n' + '\n'.join(missing))
    dest.mkdir(parents=True)
    try:
        for name in FILES:
            shutil.copyfile(driver / name, dest / name)
        shutil.copyfile(hid_ids, dest / 'hid-ids.h')
        core = dest / 'i2c-hid-core.c'
        core.write_text(patch_core(core.read_text()))
        acpi = dest / 'i2c-hid-acpi.c'
        acpi.write_text(patch_acpi(acpi.read_text()))
        for name in FILES:
            if not name.endswith('.c'):
                continue
            file = dest / name
            contents = file.read_text().replace('#include "../hid-ids.h"', '#include "hid-ids.h"')
            file.write_text(contents)
        kit = Path(__file__).resolve().parents[1] / 'modules'
        for name in ('elan2513-enum.c', 'Makefile', 'dkms.conf'):
            shutil.copyfile(kit / name, dest / name)
    except Exception:
        shutil.rmtree(dest)
        raise
    print('Prepared DKMS driver source tree:', dest)
    print('SMBus workaround and ACPI non-D0 probe flag confirmed')
    print('Note: _DSC overlay is not used; enumeration helper is separate')


if __name__ == '__main__':
    main()
