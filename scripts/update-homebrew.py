#!/usr/bin/env python3
"""Update the tap only from a published stable release with verified ZIPs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
from string import Template
import subprocess
import tempfile
import zipfile

REPOSITORY = "MiracleXYZ/AeroTab"
VERSION = r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
TEMPLATE = Path(__file__).with_name("aerotab.rb.template")


def stable_version(release):
    tag = release["tag_name"]
    if release["draft"] or release["prerelease"] or not re.fullmatch("v" + VERSION, tag):
        raise ValueError("Only published stable vX.Y.Z releases can update the tap")
    return tag[1:]


def version_tuple(value):
    return tuple(map(int, value.split(".")))


def render_cask(version, directory):
    expected = {f"AeroTab-{version}-{arch}.zip" for arch in ("arm64", "x86_64")}
    checksums = {}
    for line in (directory / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})\s+\*?([^/\s]+)", line)
        if not match or match[2] in checksums:
            raise ValueError("Invalid or duplicate SHA256SUMS entry")
        checksums[match[2]] = match[1]
    if set(checksums) != expected:
        raise ValueError("Release must contain checksums for both architectures")

    minimum_versions = set()
    for name, checksum in checksums.items():
        archive = directory / name
        if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
            raise ValueError(f"Checksum mismatch: {name}")
        with zipfile.ZipFile(archive) as bundle:
            info = plistlib.loads(bundle.read("AeroTab.app/Contents/Info.plist"))
        if info["CFBundleShortVersionString"] != version or info["CFBundleIdentifier"] != "dev.miraclexyz.AeroTab":
            raise ValueError(f"Unexpected app identity or version: {name}")
        minimum = info["LSMinimumSystemVersion"]
        if not re.fullmatch(r"\d+(?:\.\d+){0,2}", minimum):
            raise ValueError("Invalid minimum macOS version")
        minimum_versions.add(minimum)
    if len(minimum_versions) != 1:
        raise ValueError("Architectures disagree on minimum macOS version")
    return Template(TEMPLATE.read_text()).substitute(
        version=version,
        arm64_sha256=checksums[f"AeroTab-{version}-arm64.zip"],
        x86_64_sha256=checksums[f"AeroTab-{version}-x86_64.zip"],
        minimum_macos=minimum_versions.pop(),
    )


def update_cask(release, directory, destination):
    version = stable_version(release)
    previous = destination.read_text() if destination.exists() else ""
    current = re.search(r'^  version "(' + VERSION + r')"$', previous, re.MULTILINE)
    if current and version_tuple(current[1]) > version_tuple(version):
        print(f"Skipping {version}: tap already contains {current[1]}")
        return False
    content = render_cask(version, directory)
    if content == previous:
        print(f"AeroTab {version} is already up to date")
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content)
    print(f"Updated AeroTab to {version}; both release archives verified")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="", help="Published vX.Y.Z tag; defaults to latest stable release")
    parser.add_argument("--tap", required=True, type=Path, help="Checkout of MiracleXYZ/homebrew-tap")
    args = parser.parse_args()
    if args.tag and not re.fullmatch("v" + VERSION, args.tag):
        parser.error("--tag must be a stable vX.Y.Z version")
    endpoint = f"repos/{REPOSITORY}/releases/" + (f"tags/{args.tag}" if args.tag else "latest")
    release = json.loads(subprocess.check_output(["gh", "api", endpoint], text=True))
    version = stable_version(release)
    with tempfile.TemporaryDirectory(prefix="aerotab-homebrew-") as temporary:
        subprocess.run([
            "gh", "release", "download", release["tag_name"], "--repo", REPOSITORY,
            "--dir", temporary, "--pattern", f"AeroTab-{version}-arm64.zip",
            "--pattern", f"AeroTab-{version}-x86_64.zip", "--pattern", "SHA256SUMS.txt",
        ], check=True)
        update_cask(release, Path(temporary), args.tap / "Casks/aerotab.rb")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            stream.write(f"version={version}\n")


if __name__ == "__main__":
    main()
