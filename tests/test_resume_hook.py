"""Non-privileged contract checks for the suspend/resume recovery hook."""
from pathlib import Path
import subprocess
import unittest

HOOK = Path(__file__).resolve().parents[1] / "systemd" / "elan2513-dkms-resume"


class ResumeHookContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = HOOK.read_text()

    def test_bash_syntax(self):
        subprocess.run(["bash", "-n", str(HOOK)], check=True)

    def test_non_resume_operations_are_noop(self):
        for args in [("pre", "suspend"), ("post", "hibernate"), ("pre", "hybrid-sleep")]:
            with self.subTest(args=args):
                subprocess.run(["bash", str(HOOK), *args], check=True)

    def test_hardware_and_power_guards(self):
        for expected in (
            r"\_SB_.PC00.I2C0.TPL1",
            "elan2513_enum",
            "/updates/dkms/",
            "readlink -f",
            '"$DRIVER/unbind"',
            '"$DRIVER/bind"',
            "D3cold",
            "inuse != 0",
            "flock -n",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.content)


if __name__ == "__main__":
    unittest.main()
