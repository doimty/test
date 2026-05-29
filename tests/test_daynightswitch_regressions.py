import pathlib
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
TWEAK = (REPO / "Tweak.xm").read_text(encoding="utf-8")
ROOT_PLIST = (REPO / "daynightswitch/Resources/Root.plist").read_text(encoding="utf-8")
PLANE = (REPO / "PlaneSwitch.m").read_text(encoding="utf-8")
DONG = (REPO / "DongRiYueSwitch.m").read_text(encoding="utf-8")
TEETH = (REPO / "TeethSwitch.m").read_text(encoding="utf-8")
WORKFLOW = (REPO / ".github/workflows/build.yml").read_text(encoding="utf-8")
CONTROL = (REPO / "control").read_text(encoding="utf-8")

CHECKOUT_SHA = "34e114876b0b11c390a56381ad16ebd13914f8d5"
UPLOAD_SHA = "ea165f8d65b6e75b540449e92b4886f43607fa02"
THEOS_SHA = "88506b2c22e9e07dd4ed055f23c9e398a117a2c7"
SDKS_SHA = "0222fd5413cf4b9af096f37b4621afa2688572f7"


def block_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:i]
    raise AssertionError(f"unterminated block for {marker}")


def method_body(source: str, signature: str) -> str:
    return block_body(source, signature + " {")


class DayNightSwitchRegressionTests(unittest.TestCase):
    def test_prefs_path_uses_explicit_jailbreak_locations(self):
        body = block_body(TWEAK, 'static NSString *DNSPrefsPath(void)')
        self.assertNotIn("NSHomeDirectory()", body)
        self.assertIn('static NSString *const DNSPrefsMobilePath = @"/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";', TWEAK)
        self.assertIn('static NSString *const DNSPrefsRootlessPath = @"/var/jb/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";', TWEAK)
        self.assertIn('return DNSPrefsMobilePath;', body)
        self.assertIn('return DNSPrefsRootlessPath;', body)

    def test_root_plist_matches_deb_ui_copy(self):
        self.assertNotIn('<string>enabled</string>', ROOT_PLIST)
        self.assertNotIn('关于作者', ROOT_PLIST)
        self.assertIn('<string>global</string>', ROOT_PLIST)
        self.assertIn('<string>switchStyle</string>', ROOT_PLIST)

    def test_dns_setup_registers_for_prefs_refresh_before_custom_switch_exists(self):
        body = method_body(TWEAK, '- (void)dns_setup')
        observer_call = 'addObserver:self selector:@selector(dns_preferencesChanged)'
        should_apply_check = 'if (![self dns_shouldApply])'
        self.assertIn(observer_call, body)
        self.assertIn(should_apply_check, body)
        self.assertLess(body.index(observer_call), body.index(should_apply_check))

    def test_prefs_reading_is_type_safe_and_style_whitelisted(self):
        self.assertIn('static BOOL DNSBoolPref(id value, BOOL fallback)', TWEAK)
        self.assertIn('static NSInteger DNSIntegerPref(id value, NSInteger fallback)', TWEAK)
        self.assertIn('static BOOL DNSIsValidSwitchStyle(NSInteger style)', TWEAK)
        self.assertIn('enabled = DNSBoolPref(enabledCF,', TWEAK)
        self.assertIn('global = DNSBoolPref(globalCF,', TWEAK)
        self.assertIn('NSInteger savedStyle = DNSIntegerPref(', TWEAK)
        self.assertIn('switchStyle = DNSIsValidSwitchStyle(savedStyle) ? savedStyle : 0;', TWEAK)

    def test_dns_sync_custom_switch_restores_selector_guards(self):
        body = method_body(TWEAK, '- (void)dns_syncCustomSwitchWithOn:(BOOL)on animated:(BOOL)animated')
        self.assertIn('respondsToSelector:@selector(blockChangeActionAnimated:)', body)
        self.assertIn('respondsToSelector:@selector(unblockChangeAction)', body)
        self.assertIn('respondsToSelector:@selector(setOn:)', body)

    def test_layout_uses_library_application_support_not_var_mobile(self):
        good = REPO / 'layout/Library/Application Support/DayNightSwitch/cloud.png'
        bad = REPO / 'layout/var/mobile/Library/Application Support/DayNightSwitch/cloud.png'
        self.assertTrue(good.exists(), good)
        self.assertFalse(bad.exists(), bad)

    def test_plane_switch_cleans_looping_animations_and_rotates_plane(self):
        self.assertIn('self.planeIcon.transform = CGAffineTransformIdentity;', PLANE)
        self.assertNotIn('CGAffineTransformMakeRotation(M_PI_4)', PLANE)
        self.assertNotIn('CGAffineTransformMakeRotation(M_PI_2)', PLANE)
        body = method_body(PLANE, '- (void)didMoveToWindow')
        self.assertIn('else', body)
        self.assertIn('[self dns_stopAllLoopingAnimations];', body)
        self.assertIn('- (void)dns_stopAllLoopingAnimations', PLANE)
        self.assertIn('- (void)dealloc', PLANE)

    def test_dong_switch_cleans_looping_animations(self):
        self.assertIn('- (void)dns_stopAllLoopingAnimations', DONG)
        body = method_body(DONG, '- (void)didMoveToWindow')
        self.assertIn('[self dns_stopAllLoopingAnimations];', body)
        self.assertIn('- (void)dealloc', DONG)

    def test_all_switches_use_consistent_change_action_semantics(self):
        self.assertIn('self.changeAction(on, !self.isMoved);', DONG)
        self.assertIn('self.changeAction(on, !self.isMoved);', PLANE)
        self.assertIn('self.changeAction(on, !self.isMoved);', TEETH)
        self.assertIn('if (self.isOn != self.isOnBeforeDrag && self.changeAction)', DONG)
        self.assertIn('if (self.isOn != self.isOnBeforeDrag && self.changeAction)', PLANE)
        self.assertIn('if (self.isOn != self.isOnBeforeDrag && self.changeAction)', TEETH)
        self.assertGreaterEqual(DONG.count('self.changeAction(self.isOn, YES);'), 1)
        self.assertGreaterEqual(PLANE.count('self.changeAction(self.isOn, YES);'), 1)
        self.assertGreaterEqual(TEETH.count('self.changeAction(self.isOn, YES);'), 1)

    def test_workflow_pins_actions_and_build_dependencies(self):
        self.assertIn(f'uses: actions/checkout@{CHECKOUT_SHA}', WORKFLOW)
        self.assertIn(f'uses: actions/upload-artifact@{UPLOAD_SHA}', WORKFLOW)
        self.assertIn(f'git -C "$THEOS" checkout --detach {THEOS_SHA}', WORKFLOW)
        self.assertIn(f'git -C /tmp/theos-sdks checkout --detach {SDKS_SHA}', WORKFLOW)
        self.assertNotIn('actions/checkout@v4', WORKFLOW)
        self.assertNotIn('actions/upload-artifact@v4', WORKFLOW)

    def test_control_matches_deb_metadata_copy(self):
        self.assertIn('Package: de.finngaida.daynightswitch', CONTROL)
        self.assertIn('Description: Add some style to your switches', CONTROL)
        self.assertIn('Depiction: https://finngaida.de/repo/depictions/de.finngaida.daynightswitch', CONTROL)
        self.assertIn('Maintainer: Finn Gaida', CONTROL)
        self.assertIn('Author: Finn Gaida', CONTROL)
        self.assertNotIn('github.com/doimty/DayNightSwitch', CONTROL)
        self.assertNotIn('raw.githubusercontent.com/doimty/DayNightSwitch', CONTROL)


if __name__ == '__main__':
    unittest.main()
