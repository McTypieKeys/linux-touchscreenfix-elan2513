"""Portable, no-kernel-required unit tests of patch generation guards."""
import importlib.util
from pathlib import Path
import unittest

P = Path(__file__).resolve().parents[1] / 'scripts/prepare-sources.py'
spec = importlib.util.spec_from_file_location('prep', P)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestSourcePatches(unittest.TestCase):
    def test_core_scoped_bypass(self):
        raw = 'int f(void) {\n  ret = i2c_hid_probe_address(ihid);\n}\n#include <linux/a.h>\n'
        out = mod.patch_core(raw)
        self.assertIn('strcmp(client->name, "ELAN2513:00")', out)
        self.assertIn('ret = i2c_hid_probe_address(ihid);', out)
        self.assertEqual(out, mod.patch_core(out))

    def test_core_rejects_unknown_location(self):
        with self.assertRaises(ValueError):
            mod.patch_core('int f(void) { return 0; }')

    def test_core_rejects_old_experiment(self):
        with self.assertRaises(ValueError):
            mod.patch_core('ELAN2513: waiting 500 ms')

    def test_acpi_flag(self):
        raw = 'static struct i2c_driver i2c_hid_acpi_driver = {\n\t.probe = foo,\n};\n'
        out = mod.patch_acpi(raw)
        self.assertIn('\t.flags = I2C_DRV_ACPI_WAIVE_D0_PROBE,', out)
        self.assertEqual(out, mod.patch_acpi(out))

    def test_acpi_rejects_old_experiment(self):
        with self.assertRaises(ValueError):
            mod.patch_acpi('PTPL._OFF completed')


if __name__ == '__main__':
    unittest.main()
