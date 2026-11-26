#!/usr/bin/env python3
"""Exercise the privileged script with fake system tools in a temporary directory.

No sudo, real launchctl, real sysctl writes, or installed application changes.
Run on macOS: python3 test.py
"""
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
from zipfile import ZipFile
import zlib

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
        if state.get("pending", 0):
            state["pending"] -= 1
            if state["pending"] == 0:
                state["value"] = 1300000
        print("last exit code = 0")
    elif command in ("bootstrap", "kickstart"):
        if os.environ.get("TEST_BOOTSTRAP_FAIL"):
            sys.exit(5)
        if command == "bootstrap":
            state["plist"] = args[2]
        config = plistlib.loads(pathlib.Path(state["plist"]).read_bytes())
        assert config["RunAtLoad"] is True
        assert config["ProgramArguments"] == [str(root / "sysctl"), "-w", "net.inet.tcp.sendspace=1300000"]
        if os.environ.get("TEST_DELAY_RUN"):
            state["pending"] = 2
        else:
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


def icon_png(color):
    def chunk(name, content):
        return struct.pack(">I", len(content)) + name + content + struct.pack(">I", zlib.crc32(name + content))

    pixels = (b"\x00" + color * 1024) * 1024
    header = struct.pack(">IIBBBBB", 1024, 1024, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")


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
        state["value"] = 131072
        state_file.write_text(json.dumps(state))
        assert run("install", TEST_DELAY_RUN="1")["value"] == 1300000, "wait for the new run, not a stale successful exit"
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
            payload = package / "launcher-payload.zip"

            def package_app(app, archive=payload):
                subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)

            package_app(built_app)
            (package / "network-settings.sh").write_text(source)
            # Redirect only the fixture copy. Never change HOME or register test Apps.
            user_root = root / "user"
            sudo = root / "sudo"
            sudo.write_text('#!/bin/sh\nexec "$@"\n')
            sudo.chmod(0o755)
            (root / "app-store-icon.png").write_bytes(icon_png(b"\x76\x89\xa1"))
            (root / "app-store-icon-updated.png").write_bytes(icon_png(b"\xa9\x42\x25"))
            subprocess.run(["/usr/bin/sips", "-z", "512", "512", "-s", "format", "jpeg",
                            str(root / "app-store-icon.png"), "--out", str(root / "app-store-icon.jpg")],
                           check=True, capture_output=True)
            iconutil = root / "iconutil"
            iconutil.write_text("""#!/bin/bash
case "${TEST_ICON_MODE:-}:$*" in
    failed-conversion:*|failed-large-conversion:*app-store-large.iconset)
        printf 'partial output' > "$4"
        exit 1 ;;
esac
exec /usr/bin/iconutil "$@"
""")
            iconutil.chmod(0o755)
            curl = root / "curl"
            curl.write_text("#!" + sys.executable + "\n" + '''
import json, os, pathlib, shutil, sys
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
assert args[0] == "--disable" and args[args.index("--proto") + 1] == "=https"
assert "--connect-timeout" in args and "--max-time" in args and "--retry" in args
assert "--max-filesize" in args and "--location" not in args and "-L" not in args
output = pathlib.Path(args[args.index("--output") + 1])
url = args[-1]
with (root / "downloads.log").open("a") as log:
    print(url, file=log)
mode = os.environ.get("TEST_ICON_MODE")
cdn = "https://is2-ssl.mzstatic.com/image/thumb/Purple221/v4/test/"
stem = "update.png" if mode == "updated-icon" else "AppIcon.png"
if url == "https://itunes.apple.com/lookup?id=6759030432&country=tw":
    if mode == "failed-lookup":
        sys.exit(28)
    result = {
        "trackId": 6759030433 if mode == "wrong-track" else 6759030432,
        "bundleId": "com.other.app" if mode == "wrong-bundle" else "com.nexon.devcat.mm.tw",
        "artworkUrl512": cdn + stem + "/512x512bb.jpg",
    }
    if mode == "invalid-host":
        result["artworkUrl512"] = result["artworkUrl512"].replace("mzstatic.com", "mzstatic.com.example")
    output.write_text(json.dumps({"resultCount": 1, "results": [result]}))
elif url == cdn + stem + "/1024x1024bb.png":
    if mode == "failed-image":
        sys.exit(22)
    if mode in ("invalid-image", "invalid-large-image"):
        output.write_bytes(b"not an image")
    elif mode == "oversized-image":
        with output.open("wb") as file:
            file.truncate(4194305)
    else:
        fixture = "app-store-icon-updated.png" if mode == "updated-icon" else "app-store-icon.png"
        shutil.copyfile(root / fixture, output)
else:
    assert url == cdn + stem + "/512x512bb.jpg", url
    if mode in ("failed-image", "oversized-image"):
        sys.exit(22)
    if mode == "invalid-image":
        output.write_bytes(b"not an image")
    else:
        shutil.copyfile(root / "app-store-icon.jpg", output)
''')
            curl.chmod(0o755)
            register = root / "lsregister"
            register.write_text("#!" + sys.executable + "\n" + '''
import json, pathlib, sys
root = pathlib.Path(__file__).parent
action, app = sys.argv[1:]
assert pathlib.Path(app).is_dir(), (action, app)
with (root / "app-operations.jsonl").open("a") as log:
    print(json.dumps([action, app]), file=log)
failure = root / "fail-next-registration"
if action == "-f" and failure.exists():
    failure.unlink()
    sys.exit(1)
''')
            register.chmod(0o755)
            opener = root / "open"
            opener.write_text("#!" + sys.executable + "\n" + '''
import json, os, pathlib, sys
root = pathlib.Path(__file__).parent
app, = sys.argv[1:]
assert pathlib.Path(app).is_absolute() and pathlib.Path(app).is_dir(), app
with (root / "app-operations.jsonl").open("a") as log:
    print(json.dumps(["open", app]), file=log)
if os.environ.get("TEST_OPEN_FAIL"):
    sys.exit(1)
''')
            opener.chmod(0o755)
            for filename in ("install.command", "uninstall.command"):
                wrapper = (PROJECT / filename).read_text().replace("$HOME", str(user_root))
                wrapper = wrapper.replace("/usr/bin/sudo", str(sudo))
                wrapper = wrapper.replace("/usr/sbin/sysctl", str(root / "sysctl"))
                wrapper = wrapper.replace("/usr/bin/curl", str(curl))
                wrapper = wrapper.replace("/usr/bin/iconutil", str(iconutil))
                wrapper = wrapper.replace("/usr/bin/open", str(opener))
                wrapper = wrapper.replace('"$staged_app/Contents/MacOS/NexonBridge" --remember-handler', f'echo remember >> "{root / "handler.log"}"')
                wrapper = wrapper.replace('"$app/Contents/MacOS/NexonBridge" --restore-handler', ': # Do not change real URL preferences in fixture tests')
                wrapper = wrapper.replace("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", str(register))
                (package / filename).write_text(wrapper)
            installed = user_root / "Applications" / app_name
            backup_dir = user_root / "Library/Application Support/MabinogiMobileMac/backups"
            info_path = "Contents/Info.plist"

            def wrapper_run(filename, success=True, args=(), **environment):
                result = subprocess.run(["/bin/bash", str(package / filename), *args], text=True, capture_output=True,
                                        env={**os.environ, "TEST_ICON_MODE": "", "TEST_OPEN_FAIL": "", **environment})
                assert (result.returncode == 0) == success, result.stdout + result.stderr
                return result

            def change_app_metadata(app, changes, sign=True):
                info = app / info_path
                metadata = plistlib.loads(info.read_bytes())
                metadata.update(changes)
                info.write_bytes(plistlib.dumps(metadata))
                if sign:
                    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)

            def app_operations():
                return [json.loads(line) for line in (root / "app-operations.jsonl").read_text().splitlines()]

            assert "CFBundleIconFile" not in plistlib.loads((built_app / info_path).read_bytes()), "test with the base build"
            wrapper_run("install.command")
            assert installed.is_dir() and plist.exists()
            assert not (package / app_name).exists()
            assert not list(installed.parent.glob(".mabinogi-install.*"))
            installed_info = installed / info_path
            metadata = plistlib.loads(installed_info.read_bytes())
            assert metadata["CFBundleIdentifier"] == "io.github.kimi7011.mabinogi-mobile-macos"
            assert metadata["CFBundleIconFile"] == "MabinogiOfficial.icns"
            icon_path = installed / "Contents/Resources" / metadata["CFBundleIconFile"]
            first_icon = icon_path.read_bytes()
            assert first_icon[:4] == b"icns"
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(installed)], check=True)

            original_state = state_file.read_bytes()
            for mode, attempts in (("failed-lookup", 1), ("wrong-track", 1), ("wrong-bundle", 1),
                                   ("invalid-host", 1), ("failed-image", 3), ("invalid-image", 3),
                                   ("oversized-image", 3), ("failed-conversion", 3),
                                   ("invalid-large-image", 3), ("failed-large-conversion", 3)):
                (root / "downloads.log").write_text("")
                folder = root / mode
                clean_app = folder / app_name
                result = wrapper_run("install.command", args=("--keep-network", "--app-dir", str(folder)),
                                     TEST_ICON_MODE=mode)
                attempted = (root / "downloads.log").read_text().splitlines()
                assert len(attempted) == attempts, mode
                if attempts == 3:
                    assert attempted[1].endswith("/1024x1024bb.png") and attempted[2].endswith("/512x512bb.jpg"), mode
                clean_info = plistlib.loads((clean_app / info_path).read_bytes())
                if mode in ("invalid-large-image", "failed-large-conversion"):
                    assert clean_info["CFBundleIconFile"] == "MabinogiOfficial.icns", mode
                    assert (clean_app / icon_path.relative_to(installed)).read_bytes().startswith(b"icns"), mode
                else:
                    assert "CFBundleIconFile" not in clean_info and "暫用 macOS 預設圖示" in result.stdout, mode
                    assert not (clean_app / icon_path.relative_to(installed)).exists(), mode
                subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(clean_app)], check=True)
                assert icon_path.read_bytes() == first_icon, mode
                assert state_file.read_bytes() == original_state and not backup_dir.exists(), mode
                assert not list(folder.glob(".mabinogi-install.*")), mode
            wrapper_run("install.command", args=("--keep-network", "--app-dir", str(root / "failed-lookup")))
            assert (root / "failed-lookup" / app_name / icon_path.relative_to(installed)).read_bytes() == first_icon

            def legacy_backup(name, changes, sign=True):
                app = backup_dir / name / app_name
                app.parent.mkdir(parents=True)
                subprocess.run(["/usr/bin/ditto", str(built_app), str(app)], check=True)
                change_app_metadata(app, changes, sign)
                return app

            legacy = legacy_backup("app.legacy", {"CFBundleShortVersionString": "0.1.3"})
            unrelated = legacy_backup("app.unrelated", {"CFBundleIdentifier": "another.project"})
            unsigned = legacy_backup("app.unsigned", {"CFBundleShortVersionString": "0.1.2"}, sign=False)
            wrapper_run("install.command", TEST_ICON_MODE="updated-icon")
            assert icon_path.read_bytes() != first_icon, "reinstall with changed App Store artwork must refresh the icon"
            assert not legacy.exists() and unrelated.is_dir() and unsigned.is_dir()
            archives = list(backup_dir.glob("app.*/*.zip"))
            assert len(archives) == 3
            archived_versions = []
            for archive in archives:
                with ZipFile(archive) as backup:
                    [member] = [name for name in backup.namelist() if name.endswith(f"/{info_path}")]
                    metadata = plistlib.loads(backup.read(member))
                    archived_versions.append(metadata["CFBundleShortVersionString"])
            assert "0.1.3" in archived_versions
            assert app_operations()[-3:] == [["-u", str(legacy)], ["-u", str(installed)], ["-f", str(installed)]]

            change_app_metadata(installed, {"CFBundleShortVersionString": "0.1.2"})
            original = (installed / info_path).read_bytes()
            (root / "fail-next-registration").touch()
            wrapper_run("install.command", success=False, args=("--keep-network",))
            assert (installed / info_path).read_bytes() == original, "restore the old launcher after registration fails"
            assert app_operations()[-4:] == [["-u", str(installed)], ["-f", str(installed)],
                                            ["-u", str(installed)], ["-f", str(installed)]]

            previous_icon = icon_path.read_bytes()
            result = wrapper_run("install.command", args=("--keep-network",), TEST_ICON_MODE="invalid-image")
            assert "已保留上次安裝的官方圖示" in result.stdout
            assert icon_path.read_bytes() == previous_icon, "upgrade must retain the verified official icon"
            assert (installed / info_path).read_bytes() != original, "an artwork failure must not block an update"
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(installed)], check=True)

            saved_payload = package / "launcher-payload.saved"
            payload.rename(saved_payload)
            package_app(installed)
            custom_dir = root / "App with Icon"
            (root / "downloads.log").write_text("")
            wrapper_run("install.command", args=("--keep-network", "--app-dir", str(custom_dir)), TEST_ICON_MODE="failed-lookup")
            assert (root / "downloads.log").read_text() == "", "a custom App with an existing icon skips lookup"
            assert (custom_dir / app_name / icon_path.relative_to(installed)).read_bytes() == icon_path.read_bytes()
            wrapper_run("uninstall.command", args=("--keep-network", "--app-dir", str(custom_dir)))
            saved_payload.replace(payload)

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
            metadata["CFBundleIdentifier"] = "local.kimi.mabinogi-crossover-bridge"
            info.write_bytes(plistlib.dumps(metadata))
            original_info = info.read_bytes()
            wrapper_run("install.command", success=False)
            assert info.read_bytes() == original_info and not plist.exists(), "preserve the original working launcher"
            alternate = root / "Separate Apps"
            payload.rename(package / "launcher-payload.saved")
            subprocess.run(["/usr/bin/ditto", str(built_app), str(package / app_name)], check=True)
            payload.write_text("invalid ZIP")
            wrapper_run("install.command", success=False, args=("--app-dir", str(alternate)))
            assert not (alternate / app_name).exists(), "a corrupt package must fail before installation"
            payload.unlink()
            wrapper_run("install.command", args=("--app-dir", str(alternate)), TEST_ICON_MODE="failed-lookup")
            assert (alternate / app_name).is_dir() and info.read_bytes() == original_info
            assert "CFBundleIconFile" not in plistlib.loads((alternate / app_name / info_path).read_bytes())
            wrapper_run("uninstall.command", args=("--app-dir", str(alternate)))
            assert not (alternate / app_name).exists() and info.read_bytes() == original_info
            wrapper_run("install.command", success=False, args=("--app-dir", "relative"))
            wrapper_run("install.command", success=False, args=("--app-dir", str(alternate), "--keep-network"))
            assert not (alternate / app_name).exists() and not plist.exists()
            state = json.loads(state_file.read_text())
            state["value"] = 1500000
            state_file.write_text(json.dumps(state))
            wrapper_run("install.command", args=("--app-dir", str(alternate), "--keep-network"))
            assert (alternate / app_name).is_dir() and not plist.exists()
            wrapper_run("uninstall.command", args=("--app-dir", str(alternate), "--keep-network"))
            assert not (alternate / app_name).exists() and not plist.exists()
            assert json.loads(state_file.read_text())["value"] == 1500000
            assert all(action != "open" for action, _ in app_operations()), "legacy and source installs stay manual"

            modern = package / "Modern Package"
            support = modern / "Support"
            support.mkdir(parents=True)
            entry = modern / "安裝並啟動.command"
            entry.write_text((package / "install.command").read_text())
            (support / "network-settings.sh").write_text(source)
            modern_payload = support / "launcher-payload.zip"
            package_app(built_app, modern_payload)
            destination = root / "Modern Applications"
            modern_app = destination / app_name
            args = ("--app-dir", str(destination))

            before = len(app_operations())
            result = wrapper_run(entry, args=args, TEST_ICON_MODE="failed-conversion")
            assert plist.exists() and modern_app.is_dir()
            assert "暫用 macOS 預設圖示" in result.stdout
            assert app_operations()[before:] == [["-f", str(modern_app)], ["open", str(modern_app)]]

            before = len(app_operations())
            wrapper_run(entry, args=(*args, "--no-launch", "--keep-network"))
            switch_registration = [["-u", str(modern_app)], ["-f", str(modern_app)]]
            assert app_operations()[before:] == switch_registration

            before = len(app_operations())
            result = wrapper_run(entry, args=(*args, "--keep-network"), TEST_OPEN_FAIL="1")
            assert modern_app.is_dir() and "請手動開啟" in result.stderr and str(modern_app) in result.stderr
            assert app_operations()[before:] == [*switch_registration, ["open", str(modern_app)]]

            before = len(app_operations())
            (root / "fail-next-registration").touch()
            wrapper_run(entry, success=False, args=(*args, "--keep-network"))
            assert modern_app.is_dir() and app_operations()[before:] == switch_registration * 2

            before = len(app_operations())
            original_state = state_file.read_bytes()
            modern_payload.rename(modern / "launcher-payload.zip")
            result = wrapper_run(entry, success=False, args=args)
            assert "安裝包不完整" in result.stderr
            assert modern_app.is_dir() and app_operations()[before:] == [] and state_file.read_bytes() == original_state
            print("PASS: App Store refresh, original JPEG retry, nonblocking icon failures, preserving the prior icon, ZIP backups, migration and rollback")
            print("PASS: one-click package layout, launch after registration, no-launch option and manual fallback")
    print("PASS: install, repeated install, removal, original value, later changes, permissions, symlinks, unrelated files, startup failure recovery")


if __name__ == "__main__":
    if sys.platform != "darwin":
        raise SystemExit("These tests use macOS plutil and PlistBuddy; run on macOS.")
    for filename in ("build.sh", "install.command", "uninstall.command", "network-settings.sh"):
        subprocess.run(["/bin/bash", "-n", str(PROJECT / filename)], check=True)
    test_network_script(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None)
