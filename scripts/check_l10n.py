#!/usr/bin/env python3
"""Checks that every user-facing string used in the code exists in the string catalog with en and pt-BR.

Usage: python3 -I scripts/check_l10n.py <repo root>
Exits 1 when a string is missing a translation or is used but absent from the catalog.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
catalog = json.loads((root / "Sources/GDocker/Resources/Localizable.xcstrings").read_text())["strings"]


def key(text):
    # `String(localized: "Port \(String(n)) is busy")` is stored in the catalog as "Port %@ is busy".
    # Interpolate Strings, never Ints: an Int is locale-formatted ("7.391" in pt-BR).
    return re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "%@", text)


used = set()
for path in (root / "Sources/GDocker").rglob("*.swift"):
    source = path.read_text()
    used |= set(re.findall(r'Text\("([^"]+)",\s*bundle:\s*\.l10n', source))
    used |= set(re.findall(r'case \.\w+: "([^"]+)"', source))  # LocalizedStringKey enum titles
    used |= set(re.findall(r'prompt:\s*Text\("([^"]+)"', source))
    used |= {key(match) for match in re.findall(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"', source)}

# Tool titles are shown in the permissions screen, so they must be translated too.
catalog_source = (root / "Sources/GDockerCore/Access/ToolCatalog.swift").read_text()
used |= set(re.findall(r'title: "([^"]+)"', catalog_source))

missing_pt = sorted(k for k, v in catalog.items() if "pt-BR" not in v.get("localizations", {}))
missing_en = sorted(k for k, v in catalog.items() if "en" not in v.get("localizations", {}))
unknown = sorted(used - set(catalog))
unused = sorted(set(catalog) - used)
print("used keys:", len(used), "catalog keys:", len(catalog))
print("missing pt-BR:", missing_pt)
print("missing en:", missing_en)
print("used but not in catalog:", unknown)
print("in catalog but unused:", unused)
sys.exit(1 if (missing_pt or missing_en or unknown) else 0)
