#!/usr/bin/env python3
"""Deterministic release versions and checks on the generated public appcast."""
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def semver(value):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise ValueError(f"Not a stable semantic version: {value}")
    return tuple(map(int, value.split(".")))


def next_version(base, tags, head_tags):
    def versions(values):
        return [semver(tag[1:]) for tag in values if re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag)]
    at_head = versions(head_tags)
    if at_head:
        return ".".join(map(str, max(at_head)))  # A rerun reuses its own tag.
    version = semver(base)
    previous = versions(tags)
    if previous and max(previous) >= version:
        major, minor, patch = max(previous)
        version = (major, minor, patch + 1)
    return ".".join(map(str, version))


def verify_feed(directory, version):
    ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    item = ET.parse(directory / "appcast.xml").find("channel/item")
    if item is None:
        raise ValueError("No update in appcast")
    enclosure = item.find("enclosure")
    expected = f"https://github.com/AlexanderHeffernan/GitGaze/releases/download/v{version}/GitGaze.zip"
    if enclosure is None or enclosure.get("url") != expected:
        raise ValueError("Update URL is not pinned to this release")
    if item.findtext(ns + "version") != version or not enclosure.get(ns + "edSignature"):
        raise ValueError("Missing update version or Ed25519 archive signature")
    if int(enclosure.get("length", "0")) != (directory / "GitGaze.zip").stat().st_size:
        raise ValueError("Archive length mismatch")


if __name__ == "__main__":
    if sys.argv[1:] == ["version"]:
        base = plistlib.loads(Path("Info.plist").read_bytes())["CFBundleShortVersionString"]
        git_tags = lambda *args: subprocess.check_output(["git", "tag", *args], text=True).splitlines()
        print(next_version(base, git_tags("--merged", "HEAD"), git_tags("--points-at", "HEAD")))
    elif len(sys.argv) == 4 and sys.argv[1] == "verify":
        verify_feed(Path(sys.argv[2]), sys.argv[3])
    else:
        sys.exit("Usage: release.py version | verify DIRECTORY VERSION")
