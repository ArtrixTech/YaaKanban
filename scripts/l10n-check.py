#!/usr/bin/env python3
"""Check that every localizable string the compiler extracts has a zh-Hans translation.

Usage: l10n-check.py <stringsdata-dir> <Localizable.strings>
Fails on missing keys, unused translations, and placeholder mismatches.
"""
import json, pathlib, plistlib, re, subprocess, sys

data_dir, strings_path = map(pathlib.Path, sys.argv[1:3])
used = {}
for f in sorted(data_dir.glob("*.stringsdata")):
    doc = json.loads(f.read_text())
    for e in doc["tables"].get("Localizable", []):
        # Keys without letters ("·", "%lld") read the same in every language.
        if re.search(r"[^\W\d_]", re.sub(r"%(\d+\$)?(lld|ld|lf|@|d|f)", "", e["key"])):
            used.setdefault(e["key"], f"{pathlib.Path(doc['source']).relative_to(pathlib.Path.cwd(), walk_up=True)}:{e['location']['startingLine']}")

# plutil validates the .strings syntax and converts it to a dictionary.
xml = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(strings_path)],
                     check=True, capture_output=True).stdout
table = plistlib.loads(xml)

def specs(s):
    # Positional specifiers (%1$@) and plain ones (%@) both reduce to their type, in order.
    found = re.findall(r"%(?:(\d+)\$)?(lld|ld|lf|@|d|f)", s.replace("%%", ""))
    if any(p for p, _ in found):
        return sorted((int(p), t) for p, t in found)
    return list(enumerate((t for _, t in found), 1))

errors = []
for key, where in sorted(used.items()):
    if key not in table:
        errors.append(f"missing: {key!r} ({where})")
    elif specs(key) != specs(table[key]):
        errors.append(f"placeholders differ: {key!r} -> {table[key]!r}")
for key in sorted(set(table) - set(used)):
    errors.append(f"unused: {key!r}")

print(f"{len(used)} keys, {len(table)} translations")
for e in errors:
    print(e)
sys.exit(1 if errors else 0)
