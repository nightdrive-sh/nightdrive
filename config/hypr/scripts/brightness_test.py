"""Tests for hypr/scripts/brightness: the perceptual curve between the percent shown and the device value.

The script runs against a fake brightnessctl (a state file: name, class, value, max) and a fake sysfs for the panel's
scale, so nothing touches the real backlight.
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "brightness")

# brightnessctl's -m line is name,class,value,percent%,max; `set N` writes a raw value, -s saves the old one first
FAKE_BRIGHTNESSCTL = r"""#!/bin/bash
read -r name class cur max < "$FAKE_STATE"
save=0 cmd="" val=""
while (( $# )); do
  case $1 in
    -c|-d) shift ;;
    -s) save=1 ;;
    -m) cmd=get ;;
    set) cmd=set; val=$2; shift ;;
  esac
  shift
done
if [[ $cmd == set ]]; then
  (( save )) && echo "$cur" > "$FAKE_STATE.saved"
  echo "$name $class $val $max" > "$FAKE_STATE"
  echo "$val" >> "$FAKE_STATE.log"
else
  echo "$name,$class,$cur,$(( cur * 100 / max ))%,$max"
fi
"""


@unittest.skipUnless(shutil.which("awk"), "needs awk")
class BrightnessTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        bindir = os.path.join(self.dir, "bin")
        os.mkdir(bindir)
        for name, body in (("brightnessctl", FAKE_BRIGHTNESSCTL), ("qs", "#!/bin/sh\necho \"$*\" >> \"$FAKE_STATE.osd\"\n")):
            path = os.path.join(bindir, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)
        self.state = os.path.join(self.dir, "state")
        self.sysfs = os.path.join(self.dir, "sysfs")
        self.env = dict(os.environ, PATH=bindir + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
                        FAKE_STATE=self.state, BRIGHTNESS_SYSFS=self.sysfs)
        self.panel(400, 500, "linear")

    def panel(self, cur, maximum, scale, name="apple-panel-bl"):
        with open(self.state, "w") as f:
            f.write(f"{name} backlight {cur} {maximum}\n")
        os.makedirs(os.path.join(self.sysfs, name), exist_ok=True)
        with open(os.path.join(self.sysfs, name, "scale"), "w") as f:
            f.write(scale + "\n")

    def raw(self):
        with open(self.state) as f:
            return int(f.read().split()[2])

    def run_(self, *args, dev="screen"):
        out = subprocess.run([SCRIPT, dev, *args], env=self.env, capture_output=True, text=True, check=True).stdout
        return json.loads(out)["brightness"]

    def test_linear_panel_reads_through_the_curve(self):
        # 400 of 500 is 80 % of the light, which the eye sees as about 89 %
        self.assertEqual(self.run_(), 89)

    def test_setting_maps_percent_to_square(self):
        self.assertEqual(self.run_("50"), 50)
        self.assertEqual(self.raw(), 125)   # 500 * 0.5^2
        self.run_("100")
        self.assertEqual(self.raw(), 500)

    def test_read_back_is_what_was_set_where_the_panel_can_tell(self):
        for p in range(20, 101):
            self.assertEqual(self.run_(str(p)), p, p)

    def test_setting_what_was_read_keeps_the_value(self):
        # An undo sets the percent read before: it must land on the same device value, low end included
        for p in range(1, 101):
            self.run_(str(p))
            before = self.raw()
            self.run_(str(self.run_()))
            self.assertEqual(self.raw(), before, p)

    def test_typed_zero_stays_lit(self):
        self.run_("0")
        self.assertEqual(self.raw(), 1)

    def test_every_step_changes_the_device_value(self):
        self.panel(500, 500, "linear")
        seen = [self.raw()]
        while self.raw() > 0:
            self.run_("down", "--quiet")
            self.assertLess(self.raw(), seen[-1])
            seen.append(self.raw())
        # 5 % steps at the top, bigger ones only where percents share a device value
        self.assertEqual(self.run_(), 0)
        self.assertGreater(len(seen), 15)
        while self.raw() < 500:
            before = self.raw()
            self.run_("up", "--quiet")
            self.assertGreater(self.raw(), before)

    def test_up_from_top_and_down_from_zero_stay(self):
        self.panel(500, 500, "linear")
        self.assertEqual(self.run_("up", "--quiet"), 100)
        self.panel(0, 500, "linear")
        self.assertEqual(self.run_("down", "--quiet"), 0)

    def test_quiet_shows_no_toast_and_keys_do(self):
        self.run_("up", "--quiet")
        self.assertFalse(os.path.exists(self.state + ".osd"))
        self.run_("up")
        with open(self.state + ".osd") as f:
            self.assertEqual(f.read().split(), ["ipc", "call", "osd", "brightness"])

    def test_non_linear_panel_stays_straight(self):
        self.panel(400, 500, "non-linear", name="intel_backlight")
        self.assertEqual(self.run_(), 80)
        self.run_("50")
        self.assertEqual(self.raw(), 250)

    def test_keyboard_stays_straight_in_tens(self):
        self.panel(100, 255, "linear", name="kbd_backlight")
        self.assertEqual(self.run_(dev="kbd"), 39)
        self.assertEqual(self.run_("up", "--quiet", dev="kbd"), 40)
        self.assertEqual(self.run_("down", "--quiet", dev="kbd"), 30)

    def test_dim_saves_and_only_lowers(self):
        self.run_("dim", "10")
        self.assertEqual(self.raw(), 5)   # 500 * 0.1^2
        with open(self.state + ".saved") as f:
            self.assertEqual(int(f.read()), 400)
        self.panel(3, 500, "linear")
        self.run_("dim", "10")
        self.assertEqual(self.raw(), 3)

    def test_rejects_bad_percent(self):
        r = subprocess.run([SCRIPT, "screen", "150"], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
