#!/usr/bin/env python3
"""Reject source/simulator archives masquerading as an iPhone IPA.

This is structural validation, not signing or real-device acceptance.
"""
import json
import plistlib
import stat
import struct
import sys
import zipfile
from pathlib import PurePosixPath


def verify(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Archive has a corrupt member")
        for member in archive.namelist():
            parts = PurePosixPath(member).parts
            if member.startswith("/") or ".." in parts:
                raise ValueError("Archive contains an unsafe member path")
        plists = [n for n in archive.namelist()
                  if n.startswith("Payload/") and n.endswith(".app/Info.plist")
                  and len(PurePosixPath(n).parts) == 3]
        if len(plists) != 1:
            raise ValueError("Expected exactly one top-level Payload/*.app")
        info = plistlib.loads(archive.read(plists[0]))
        if info.get("CFBundlePackageType") != "APPL":
            raise ValueError("Payload is not an application bundle")
        if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError("Payload was not built for an iOS device")
        if info.get("DTPlatformName") != "iphoneos":
            raise ValueError("Expected an iphoneos SDK build")
        name = info.get("CFBundleExecutable", "")
        if not name or "/" in name or "$" in name:
            raise ValueError("Missing or unresolved executable name")
        member = str(PurePosixPath(plists[0]).parent / name)
        executable = archive.read(member)
        mode = archive.getinfo(member).external_attr >> 16
        if not mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            raise ValueError("Payload executable has lost its execute permission")
        if len(executable) < 32:
            raise ValueError("Payload executable is truncated")
        magic, cpu, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<8I", executable)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or filetype != 2:
            raise ValueError("Expected an arm64 Mach-O executable")
        if 32 + sizeofcmds > len(executable):
            raise ValueError("Mach-O load commands are truncated")
        offset = 32
        device_platform = False
        for _ in range(ncmds):
            if offset + 8 > 32 + sizeofcmds:
                raise ValueError("Malformed Mach-O load commands")
            command, size = struct.unpack_from("<2I", executable, offset)
            if size < 8 or offset + size > 32 + sizeofcmds:
                raise ValueError("Malformed Mach-O load command size")
            if command == 0x32 and size >= 24:  # LC_BUILD_VERSION; PLATFORM_IOS == 2
                device_platform = struct.unpack_from("<I", executable, offset + 8)[0] == 2
            offset += size
        if not device_platform:
            raise ValueError("Mach-O does not identify the physical iOS platform")
        return {"bundle_id": info.get("CFBundleIdentifier"),
                "version": info.get("CFBundleShortVersionString"),
                "minimum_os": info.get("MinimumOSVersion"),
                "platform": "iphoneos", "architecture": "arm64",
                "validation": "structure only; SideStore signing and installation pending"}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: verify-ipa.py PATH")
    try:
        print(json.dumps(verify(sys.argv[1]), indent=2))
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException, struct.error) as error:
        sys.exit(f"IPA verification failed: {error}")
