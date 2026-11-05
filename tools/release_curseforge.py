"""Uploads dist/ThreatHelperForever-<version>.zip to CurseForge (Upload API), no packager.

Reads from the TOC: Version, Interface (16001 -> game version "1.60.1"), X-Curse-Project-ID.
Changelog: docs/curseforge/changelog-<version>.md. Token: env CF_API_KEY (a GitHub secret,
never in the repo). Release type: "alpha"/"beta" when the version says so, else "release".

Run from the repo root after tools/build_zip.py:
  python tools/release_curseforge.py            upload
  python tools/release_curseforge.py --dry-run  print the metadata, no network
"""
import json
import os
import sys
import urllib.request
import uuid

ADDON = "ThreatHelperForever"
API = "https://wow.curseforge.com/api"


def toc_fields():
    fields = {}
    with open(os.path.join(ADDON, ADDON + ".toc"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("## ") and ":" in line:
                key, value = line[3:].split(":", 1)
                fields[key.strip()] = value.strip()
    return fields


def game_version(interface):
    # 16001 -> 1.60.1 (major, two-digit minor, two-digit patch), like the BigWigs packager.
    s = str(int(interface))
    return "%d.%d.%d" % (int(s[:-4]), int(s[-4:-2]), int(s[-2:]))


def release_type(version):
    low = version.lower()
    if "alpha" in low:
        return "alpha"
    if "beta" in low:
        return "beta"
    return "release"


def request(url, token, data=None, content_type=None):
    req = urllib.request.Request(url, data=data, headers={"X-Api-Token": token})
    if content_type:
        req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def main():
    dry = "--dry-run" in sys.argv
    toc = toc_fields()
    version, project = toc["Version"], toc["X-Curse-Project-ID"]
    gv = game_version(toc["Interface"])
    zip_path = os.path.join("dist", "%s-%s.zip" % (ADDON, version))
    with open(os.path.join("docs", "curseforge", "changelog-%s.md" % version), encoding="utf-8") as f:
        changelog = f.read()
    meta = {"changelog": changelog, "changelogType": "markdown", "displayName": "%s-%s" % (ADDON, version),
            "releaseType": release_type(version)}
    if not os.path.isfile(zip_path):
        print("missing %s: run tools/build_zip.py first" % zip_path)
        return 1
    if dry:
        print("project %s, game version %s, file %s" % (project, gv, zip_path))
        print(json.dumps(meta, indent=2))
        return 0

    token = os.environ.get("CF_API_KEY")
    if not token:
        print("CF_API_KEY is not set")
        return 1
    ids = [v["id"] for v in request(API + "/game/versions", token) if v.get("name") == gv]
    if len(ids) != 1:
        print("game version %s: %d matches on CurseForge, expected 1" % (gv, len(ids)))
        return 1
    meta["gameVersions"] = ids

    boundary = uuid.uuid4().hex
    with open(zip_path, "rb") as f:
        payload = f.read()
    body = b"".join([
        ("--%s\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n" % boundary).encode(),
        json.dumps(meta).encode("utf-8"), b"\r\n",
        ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
         "Content-Type: application/zip\r\n\r\n" % (boundary, os.path.basename(zip_path))).encode(),
        payload, ("\r\n--%s--\r\n" % boundary).encode(),
    ])
    res = request("%s/projects/%s/upload-file" % (API, project), token, body,
                  "multipart/form-data; boundary=" + boundary)
    print("uploaded %s to CurseForge project %s (file id %s, game version %s)" % (zip_path, project, res.get("id"), gv))
    return 0


if __name__ == "__main__":
    sys.exit(main())
