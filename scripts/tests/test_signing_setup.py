"""Regression checks for public defaults and private, stable renewal identity."""

import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from signing_config import (  # noqa: E402
    DEFAULTS, SETTING_NAMES, TARGETS, configure_personal_team, extract_project_signing,
    identifier, read_local, read_project, variable, write_local,
)


class SigningSettingsTests(unittest.TestCase):
    def test_personal_team_uses_one_stable_prefix_for_both_apps(self):
        values = configure_personal_team("TEST123456", "org.sample.styleus")
        self.assertEqual(values["STYLEUS_IPAD_BUNDLE_ID"], "org.sample.styleus.ipad")
        self.assertEqual(values["STYLEUS_MAC_BUNDLE_ID"], "org.sample.styleus.mac")
        for target in TARGETS:
            self.assertEqual(values[variable(target, "DEVELOPMENT_TEAM")], "TEST123456")
            self.assertEqual(values[variable(target, "CODE_SIGN_STYLE")], "Automatic")
            self.assertEqual(values[variable(target, "CODE_SIGN_IDENTITY")], "Apple Development")

    def test_invalid_team_or_prefix_is_rejected(self):
        for team, prefix in (("short", "org.sample.styleus"), ("TEST123456", "no-spaces here"),
                             ("TEST123456", "org..app"), ("TEST123456", "oneword")):
            with self.subTest(team=team, prefix=prefix), self.assertRaises(ValueError):
                configure_personal_team(team, prefix)

    def test_import_preserves_different_signing_for_each_target(self):
        objects = {}
        for target in TARGETS:
            for config in ("Debug", "Release"):
                objects[identifier(f"{target}:{config}")] = {"buildSettings": {
                    "DEVELOPMENT_TEAM": "TEST123456" if target == "StyleusPad" else "OTHER12345",
                    "PRODUCT_BUNDLE_IDENTIFIER": "org.example." + target.lower(),
                    "CODE_SIGN_IDENTITY": "Apple Development" if target == "StyleusPad" else "-",
                    "CODE_SIGN_STYLE": "Automatic" if target == "StyleusPad" else "Manual",
                }}
        values = extract_project_signing({"objects": objects})
        self.assertEqual(values["STYLEUS_IPAD_DEVELOPMENT_TEAM"], "TEST123456")
        self.assertEqual(values["STYLEUS_MAC_DEVELOPMENT_TEAM"], "OTHER12345")
        self.assertEqual(values["STYLEUS_MAC_CODE_SIGN_IDENTITY"], "-")

    def test_conflicting_debug_release_import_fails_instead_of_changing_identity(self):
        objects = {
            identifier("StyleusPad:Debug"): {"buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.a.ipad"}},
            identifier("StyleusPad:Release"): {"buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.b.ipad"}},
        }
        with self.assertRaisesRegex(ValueError, "different Debug/Release"):
            extract_project_signing({"objects": objects})

    def test_custom_xcode_variables_or_conditions_are_rejected_without_silent_loss(self):
        for key, value in (("PRODUCT_BUNDLE_IDENTIFIER", "$(CUSTOM_BUNDLE)"),
                           ("DEVELOPMENT_TEAM", "${CUSTOM_TEAM}"),
                           ("CODE_SIGN_IDENTITY[sdk=iphoneos*]", "Apple Development")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                extract_project_signing({"objects": {
                    identifier("StyleusPad:Debug"): {"buildSettings": {key: value}},
                }})

    def test_custom_local_settings_are_not_silently_discarded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Local.xcconfig"
            for content in ("MY_CUSTOM_TEAM = TEST123456\n", '#include "Other.xcconfig"\n'):
                path.write_text(content)
                with self.assertRaisesRegex(ValueError, "custom settings or includes"):
                    read_local(path)
                self.assertEqual(path.read_text(), content)

    def test_private_file_round_trips_and_is_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Local.xcconfig"
            values = configure_personal_team("TEST123456", "org.sample.styleus")
            write_local(path, values)
            self.assertEqual(read_local(path), values)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            path.chmod(0o644)
            write_local(path, values)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            with self.assertRaises(ValueError):
                write_local(path, {"STYLEUS_IPAD_BUNDLE_ID": "one\nOTHER = two"})


class ProjectGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        for name in ("generate_project.py", "configure-signing.py", "signing_config.py"):
            shutil.copy2(SCRIPTS / name, self.root / "scripts" / name)
        for directory in ("Shared", "iPad", "Mac", "Config", "Styleus.xcodeproj"):
            (self.root / directory).mkdir()
        for directory in ("Shared", "iPad", "Mac"):
            (self.root / directory / "Example.swift").write_text("// fixture\n")
        shutil.copy2(SCRIPTS.parent / "Config/Signing.xcconfig", self.root / "Config/Signing.xcconfig")

    def generate(self):
        result = subprocess.run([sys.executable, str(self.root / "scripts/generate_project.py")],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.root / "Styleus.xcodeproj/project.pbxproj"

    def test_clean_checkout_uses_optional_private_config_with_generic_defaults(self):
        project = read_project(self.generate())
        objects = project["objects"]
        config = objects[identifier("signing:config")]
        self.assertEqual(config["path"], "Config/Signing.xcconfig")
        self.assertFalse((self.root / "Config/Local.xcconfig").exists())
        for target in TARGETS:
            for build in ("Debug", "Release"):
                settings = objects[identifier(f"{target}:{build}")]
                self.assertEqual(settings["baseConfigurationReference"], identifier("signing:config"))
                for setting in SETTING_NAMES:
                    self.assertEqual(settings["buildSettings"][setting], f"$({variable(target, setting)})")
        self.assertEqual(DEFAULTS["STYLEUS_IPAD_DEVELOPMENT_TEAM"], "")
        self.assertEqual(DEFAULTS["STYLEUS_MAC_DEVELOPMENT_TEAM"], "")
        self.assertEqual(DEFAULTS["STYLEUS_IPAD_BUNDLE_ID"], "com.example.styleus.ipad")
        self.assertIn('#include? "Local.xcconfig"', (self.root / "Config/Signing.xcconfig").read_text())

    def test_generation_never_reads_embeds_or_overwrites_private_signing(self):
        baseline = self.generate().read_bytes()
        local = self.root / "Config/Local.xcconfig"
        values = configure_personal_team("TEST123456", "org.private.fixture")
        write_local(local, values)
        before = local.read_bytes()
        project = self.generate().read_bytes()
        self.assertEqual(project, baseline)
        self.assertEqual(local.read_bytes(), before)
        self.assertNotIn(b"TEST123456", project)
        self.assertNotIn(b"org.private.fixture", project)
        # Public variable references must not replace literal private values on import.
        self.assertEqual(extract_project_signing(read_project(self.generate())), {})

    def test_asset_catalogs_are_resources_for_their_own_target(self):
        for directory in ("iPad", "Mac"):
            (self.root / directory / "Assets.xcassets").mkdir()
        objects = read_project(self.generate())["objects"]
        for target, directory in (("StyleusPad", "iPad"), ("StyleusMac", "Mac")):
            relative = f"{directory}/Assets.xcassets"
            reference = identifier("file:" + relative)
            build_reference = identifier(target + ":resource:" + relative)
            self.assertEqual(objects[reference]["lastKnownFileType"], "folder.assetcatalog")
            self.assertEqual(objects[reference]["path"], relative)
            self.assertEqual(objects[build_reference]["fileRef"], reference)
            self.assertEqual(objects[identifier(target + ":resources")]["files"], [build_reference])
            self.assertIn(reference, objects[identifier(target + ":group")]["children"])
            for build in ("Debug", "Release"):
                settings = objects[identifier(target + ":" + build)]["buildSettings"]
                self.assertEqual(settings["ASSETCATALOG_COMPILER_APPICON_NAME"], "AppIcon")

    def test_configure_command_keeps_public_project_deterministic(self):
        baseline = self.generate().read_bytes()
        result = subprocess.run([
            sys.executable, str(self.root / "scripts/configure-signing.py"),
            "--team", "TEST123456", "--bundle-prefix", "org.sample.styleus",
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "Styleus.xcodeproj/project.pbxproj").read_bytes(), baseline)
        private = read_local(self.root / "Config/Local.xcconfig")
        self.assertEqual(private["STYLEUS_IPAD_BUNDLE_ID"], "org.sample.styleus.ipad")
        self.assertNotIn("TEST123456", result.stdout + result.stderr)
        imported = subprocess.run([
            sys.executable, str(self.root / "scripts/configure-signing.py"), "--import-xcode",
        ], capture_output=True, text=True)
        self.assertEqual(imported.returncode, 0, imported.stderr)
        self.assertEqual(read_local(self.root / "Config/Local.xcconfig"), private)


class ScriptUsageTests(unittest.TestCase):
    def run_script(self, name, *arguments):
        return subprocess.run(["zsh", str(SCRIPTS / name), *arguments], capture_output=True, text=True)

    def test_installer_requires_exactly_one_explicit_device(self):
        for arguments in ((), ("first", "second"), ("",), ("--unknown",)):
            with self.subTest(arguments=arguments):
                result = self.run_script("install-ipad.sh", *arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn("DEVICE_ID_OR_NAME", result.stderr)

    def test_help_does_not_build_install_or_require_device(self):
        for script in ("install-ipad.sh", "build.sh"):
            result = self.run_script(script, "--help")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Usage:", result.stdout)

    def test_build_rejects_unknown_options(self):
        result = self.run_script("build.sh", "--unknown")
        self.assertEqual(result.returncode, 2)
        self.assertIn("--check-only", result.stderr)


if __name__ == "__main__":
    unittest.main()
