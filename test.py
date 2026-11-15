#!/usr/bin/env python3
"""Exercise the privileged script with fake system tools in a temporary directory.

No sudo, real launchctl, real sysctl writes, or installed application changes.
Run on macOS: python3 test.py
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parent
MOCK = r'''
import json, os, pathlib, plistlib, subprocess, sys
root = pathlib.Path(__file__).parent
state_file = root / "state.json"
state = json.loads(state_file.read_text())
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if tool == "id":
    print(os.environ.get("TEST_UID", "0"))
elif tool == "stat":
    print("0")
elif tool == "chown":
    pass
elif tool == "sysctl":
    if args[0] == "-n":
        print(state["value"])
    else:
        key, value = args[1].split("=", 1)
        assert key == "net.inet.tcp.sendspace"
        state["value"] = int(value)
        state_file.write_text(json.dumps(state))
elif tool == "launchctl":
    command = args[0]
    if command == "print":
        if not state.get("loaded"):
            sys.exit(1)
        print("last exit code = 0")
    elif command in ("bootstrap", "kickstart"):
        if os.environ.get("TEST_BOOTSTRAP_FAIL"):
            sys.exit(5)
        if command == "bootstrap":
            state["plist"] = args[2]
        config = plistlib.loads(pathlib.Path(state["plist"]).read_bytes())
        assert config["RunAtLoad"] is True
        assert config["ProgramArguments"] == [str(root / "sysctl"), "-w", "net.inet.tcp.sendspace=1300000"]
        state["value"] = 1300000
        state["loaded"] = True
        state["runs"] = state.get("runs", 0) + 1
    elif command == "bootout":
        state["loaded"] = False
    elif command == "enable":
        state["enabled"] = True
    else:
        raise AssertionError(args)
    state_file.write_text(json.dumps(state))
else:
    raise AssertionError(tool)
'''


def test_network_script(built_app=None):
    with tempfile.TemporaryDirectory(prefix="mabinogi-tests-") as temporary:
        root = Path(temporary)
        daemons = root / "LaunchDaemons"
        daemons.mkdir()
        source = (PROJECT / "network-settings.sh").read_text()
        source = source.replace("/Library/LaunchDaemons", str(daemons))
        for command in ("/usr/bin/id", "/usr/bin/stat", "/usr/sbin/chown", "/usr/sbin/sysctl", "/bin/launchctl"):
            fake = root / Path(command).name
            fake.write_text("#!" + sys.executable + "\n" + MOCK)
            fake.chmod(0o755)
            source = source.replace(command, str(fake))
        script = root / "network-settings.sh"
        script.write_text(source)
        state_file = root / "state.json"
        plist = daemons / "io.github.kimi7011.mabinogi-mobile-macos.tcp.plist"

        def reset(value=131072):
            if plist.exists() or plist.is_symlink():
                plist.unlink()
            state_file.write_text(json.dumps({"value": value, "loaded": False}))

        def run(action, success=True, **environment):
            result = subprocess.run(["/bin/bash", str(script), action], text=True, capture_output=True,
                                    env={**os.environ, **environment})
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return json.loads(state_file.read_text())

        reset()
        run("install", success=False, TEST_UID="501")
        assert not plist.exists(), "unprivileged install must not create a daemon"
        run("invalid", success=False)
        state = run("install")
        config = plistlib.loads(plist.read_bytes())
        assert state["value"] == 1300000 and state["loaded"] and state["enabled"]
        assert config["MabinogiOriginalSendspace"] == 131072
        assert plist.stat().st_mode & 0o777 == 0o644
        state = run("install")
        assert state["runs"] == 2
        assert plistlib.loads(plist.read_bytes())["MabinogiOriginalSendspace"] == 131072
        state = run("remove")
        assert state["value"] == 131072 and not state["loaded"] and not plist.exists()
        assert run("remove")["value"] == 131072

        reset()
        run("install")
        state = json.loads(state_file.read_text())
        state["value"] = 1500000
        state_file.write_text(json.dumps(state))
        assert run("remove")["value"] == 1500000, "preserve a later administrator change"

        reset()
        sentinel = root / "unrelated.plist"
        sentinel.write_text("unrelated data")
        plist.symlink_to(sentinel)
        run("install", success=False)
        run("remove", success=False)
        assert sentinel.read_text() == "unrelated data"

        reset()
        plist.write_bytes(plistlib.dumps({"Label": "another.project"}))
        original = plist.read_bytes()
        run("install", success=False)
        run("remove", success=False)
        assert plist.read_bytes() == original

        reset()
        run("install", success=False, TEST_BOOTSTRAP_FAIL="1")
        assert json.loads(state_file.read_text())["value"] == 131072
        assert run("install")["value"] == 1300000
        run("remove")

        if built_app:
            package = root / "package"
            package.mkdir()
            app_name = "瑪奇 Mobile 啟動.app"
            subprocess.run(["/usr/bin/ditto", str(built_app), str(package / app_name)], check=True)
            (package / "network-settings.sh").write_text(source)
            # Redirect only the fixture copy. Never change HOME or register test Apps.
            user_root = root / "user"
            sudo = root / "sudo"
            sudo.write_text('#!/bin/sh\nexec "$@"\n')
            sudo.chmod(0o755)
            register = root / "lsregister"
            register.write_text('#!/bin/sh\nexit 0\n')
            register.chmod(0o755)
            for filename in ("install.command", "uninstall.command"):
                wrapper = (PROJECT / filename).read_text().replace("$HOME", str(user_root))
                wrapper = wrapper.replace("/usr/bin/sudo", str(sudo))
                wrapper = wrapper.replace("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", str(register))
                (package / filename).write_text(wrapper)
            installed = user_root / "Applications" / app_name

            def wrapper_run(filename, success=True):
                result = subprocess.run(["/bin/bash", str(package / filename)], text=True, capture_output=True)
                assert (result.returncode == 0) == success, result.stdout + result.stderr

            wrapper_run("install.command")
            assert installed.is_dir() and plist.exists()
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(installed)], check=True)
            wrapper_run("install.command")
            assert list((user_root / "Library/Application Support/MabinogiMobileMac/backups").glob("*/" + app_name))
            wrapper_run("uninstall.command")
            assert not installed.exists() and not plist.exists()
            assert list((user_root / ".Trash").glob("*/" + app_name))
            assert json.loads(state_file.read_text())["value"] == 131072
            subprocess.run(["/usr/bin/ditto", str(built_app), str(installed)], check=True)
            info = installed / "Contents/Info.plist"
            metadata = plistlib.loads(info.read_bytes())
            metadata["CFBundleIdentifier"] = "another.project"
            info.write_bytes(plistlib.dumps(metadata))
            wrapper_run("install.command", success=False)
            assert not plist.exists() and installed.exists()
            wrapper_run("uninstall.command")
            assert installed.exists(), "unrelated App must be preserved"
            print("PASS: packaged installer, signed App copy, repeated install backup, trash removal, unrelated App protection")
    print("PASS: install, repeated install, removal, original value, later changes, permissions, symlinks, unrelated files, startup failure recovery")


if __name__ == "__main__":
    if sys.platform != "darwin":
        raise SystemExit("These tests use macOS plutil and PlistBuddy; run on macOS.")
    for filename in ("build.sh", "install.command", "uninstall.command", "network-settings.sh"):
        subprocess.run(["/bin/bash", "-n", str(PROJECT / filename)], check=True)
    test_network_script(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None)
