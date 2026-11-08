#!/usr/bin/env python3
"""Install a reviewed release on the named 12 mini, with verified backups."""
import argparse
import datetime
import getpass
import hashlib
import json
import pathlib
import plistlib
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=pathlib.Path)
    parser.add_argument("--host", required=True)
    parser.add_argument("--evidence", required=True, type=pathlib.Path)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    password = getpass.getpass("12 mini sudo password: ")
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6",
           "mobile@" + args.host]

    def read(command):
        return subprocess.run(ssh + [command], capture_output=True, check=True,
                              timeout=30).stdout

    def root(command):
        result = subprocess.run(
            ssh + ['sudo -S -p "" /bin/sh -c ' + shlex.quote(command)],
            input=(password + "\n").encode(), capture_output=True, timeout=60)
        output = (result.stdout + result.stderr).decode(errors="replace")
        output = output.replace(password, "[REDACTED_SECRET]")
        print(output)
        result.check_returncode()
        return output

    def check_identity():
        identity = read("uname -a; sw_vers; id").decode()
        if not all(value in identity for value in ["iPhone13,1", "16.3.1", "20D67"]):
            raise RuntimeError("Target identity differs; no installation")
        return identity

    identity = check_identity()
    policies = {name: read("cat /var/mobile/Library/RootHide/" + name) for name in [
        "RootHideConfig.plist", "cn.zqbb.inject.plist",
        "cn.zqbb.inject.system.plist", "cn.zqbb.inject.wantsblacklist.plist"]}
    names = [module + suffix for module in ["HideDoubaoPiP", "DoubaoNoJump"]
             for suffix in [".dylib", ".plist"]]
    library = "/Library/MobileSubstrate/DynamicLibraries/"
    original = {name: read("cat " + library + name) for name in names}
    with tempfile.TemporaryDirectory() as temp:
        subprocess.run(["dpkg-deb", "-x", str(args.package), temp], check=True)
        payloads = {name: (pathlib.Path(temp) / library.lstrip("/") / name).read_bytes()
                    for name in names}
        for name in names:
            if name.endswith(".plist"):
                if not payloads[name].startswith(b"bplist"):
                    raise RuntimeError("Filter serialization differs")
                if plistlib.loads(payloads[name]) != plistlib.loads(original[name]):
                    raise RuntimeError("Filter scope differs")
            else:
                file = pathlib.Path(temp) / library.lstrip("/") / name
                arch = subprocess.check_output(["xcrun", "lipo", "-archs", str(file)])
                if arch.strip() != b"arm64e":
                    raise RuntimeError("Wrong package CPU architecture")
                deps = subprocess.check_output(["xcrun", "otool", "-L", str(file)])
                if b"@loader_path/.jbroot/usr/lib/libsubstrate.dylib" not in deps:
                    raise RuntimeError("Missing RootHide substrate dependency")
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = "/var/mobile/Documents/doubao-before-" + stamp
        root("umask 077; mkdir " + backup + "; chown mobile:mobile " + backup)
        for name, raw in original.items():
            (args.evidence / (name + ".before")).write_bytes(raw)
            metadata = read('stat -c "%u:%g %a" ' + library + name)
            (args.evidence / (name + ".metadata.before")).write_bytes(metadata)
            root("cp -p " + library + name + " " + backup + "/" + name)
            if read("cat " + backup + "/" + name) != raw:
                raise RuntimeError("Device backup differs")
        status = read("dpkg-query -s ayao.hidedoubaopip")
        (args.evidence / "package-control.before").write_bytes(status)
        root("dpkg-query -s ayao.hidedoubaopip > " + backup + "/package-control")
        data = args.package.read_bytes()
        remote_package = backup + "/install.deb"
        subprocess.run(ssh + ["umask 077; cat > " + remote_package], input=data,
                       capture_output=True, check=True, timeout=30)
        if read("cat " + remote_package) != data:
            raise RuntimeError("Uploaded archive differs")
        check_identity()
        for name, raw in policies.items():
            if read("cat /var/mobile/Library/RootHide/" + name) != raw:
                raise RuntimeError("Concurrent policy change before install")
        output = root("dpkg -i " + remote_package)
        (args.evidence / "installation.log").write_text(output)
        for name, raw in payloads.items():
            if read("cat " + library + name) != raw:
                raise RuntimeError("Installed file differs: " + name)
        for name, raw in policies.items():
            if read("cat /var/mobile/Library/RootHide/" + name) != raw:
                raise RuntimeError("Non-target policy changed: " + name)
        result = {"identity": identity, "package": str(args.package),
                  "sha256": hashlib.sha256(data).hexdigest(), "backup": backup,
                  "installed_files_match": len(names), "policies_unchanged": len(policies),
                  "gui_acceptance": "not_run"}
        (args.evidence / "installation-result.json").write_text(json.dumps(result, indent=2))
        root("sbreload")
        print("Installed readback verified; reload requested; GUI acceptance not claimed")


if __name__ == "__main__":
    main()
