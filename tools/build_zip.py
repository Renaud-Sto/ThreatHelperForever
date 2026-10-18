"""Builds dist/ThreatHelperForever-<version>.zip by hand (no packager): one top folder ThreatHelperForever/
holding the TOC and only the files it lists, then checks the archive.

Run from the repo root: python tools/build_zip.py
"""
import os
import sys
import zipfile

ADDON = "ThreatHelperForever"


def main():
    toc_path = os.path.join(ADDON, ADDON + ".toc")
    with open(toc_path, encoding="utf-8") as f:
        toc = f.read().splitlines()
    files = [line.strip() for line in toc if line.strip() and not line.startswith("#")]
    # Textures the code loads by path (not listed in the TOC).
    media = os.path.join(ADDON, "Media")
    if os.path.isdir(media):
        files += sorted("Media/" + n for n in os.listdir(media))
    version = [line.split(":", 1)[1].strip() for line in toc if line.startswith("## Version")][0]

    os.makedirs("dist", exist_ok=True)
    out = os.path.join("dist", "%s-%s.zip" % (ADDON, version))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(toc_path, ADDON + "/" + ADDON + ".toc")
        for name in files:
            z.write(os.path.join(ADDON, *name.split("/")), ADDON + "/" + name)

    on_disk = set()
    for root, _, names in os.walk(ADDON):
        for name in names:
            on_disk.add(os.path.relpath(os.path.join(root, name)).replace(os.sep, "/"))
    with zipfile.ZipFile(out) as z:
        packed = z.namelist()
    missing = sorted(on_disk - set(packed))
    print("%s: %d bytes, %d entries, version %s" % (out, os.path.getsize(out), len(packed), version))
    for name in packed:
        print("  " + name)
    if missing:
        print("on disk but not in the TOC (not shipped): %s" % ", ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
