#!/usr/bin/env python3

import json, os, re, sys, urllib.request

ENV_PATH = sys.argv[1] if len(sys.argv) > 1 else ".env"
if not os.path.isfile(ENV_PATH):
    sys.stderr.write(f"Error: {ENV_PATH} not found\n")
    sys.exit(1)

req = urllib.request.Request(
    "https://api.github.com/repos/semaphoreui/semaphore/releases/latest",
    headers={
        "Accept": "application/vnd.github+json",
        **({"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}"} if os.environ.get("GITHUB_TOKEN") else {})
    },
)
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.loads(r.read().decode("utf-8"))
        tag = data.get("tag_name", "")
except Exception as e:
    sys.stderr.write(f"Error fetching latest release: {e}\n")
    sys.exit(1)

if not tag:
    sys.stderr.write("Error: Could not find tag_name in GitHub response\n")
    sys.exit(1)

version = tag[1:] if tag.startswith("v") else tag
print(f"Latest Semaphore version: {version}")

with open(ENV_PATH, "r", encoding="utf-8") as f:
    contents = f.read()

# Backup
with open(ENV_PATH + ".bak", "w", encoding="utf-8") as f:
    f.write(contents)

# Replace or append, preserving trailing comment
pattern = re.compile(r'^(SEMAPHORE_VERSION=)[^ #]+(.*)$', re.MULTILINE)
if pattern.search(contents):
    # USE \g<1> and \g<2> to avoid accidental \12-style backrefs
    updated = pattern.sub(rf"\g<1>{version}\g<2>", contents)
else:
    suffix = "\n" if contents and not contents.endswith("\n") else ""
    updated = contents + f"{suffix}SEMAPHORE_VERSION={version} # set by update script\n"

with open(ENV_PATH, "w", encoding="utf-8") as f:
    f.write(updated)

print(f"Updated {ENV_PATH} (backup at {ENV_PATH}.bak)")
