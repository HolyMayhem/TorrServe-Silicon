#!/usr/bin/env python3
"""Validate announcement content before it is copied into a release bundle."""
import json
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def validate(manifest_path, info_path):
    data = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    with Path(info_path).open("rb") as stream:
        info = plistlib.load(stream)
    assert type(data["schemaVersion"]) is int and data["schemaVersion"] == 1, "schemaVersion must be 1"
    assert isinstance(data["id"], str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,119}", data["id"]), "invalid id"
    assert type(data["enabled"]) is bool, "enabled must be true or false"
    assert type(data["build"]) is int and data["build"] > 0, "build must be a positive integer"
    if data["enabled"]:
        assert str(data["build"]) == info["CFBundleVersion"], "enabled announcement build must match CFBundleVersion"
    url = data.get("detailsURL")
    if url is not None:
        assert isinstance(url, str), "detailsURL must be an HTTPS URL or null"
        parsed = urlparse(url)
        assert parsed.scheme.lower() == "https" and parsed.hostname, "detailsURL must use HTTPS"
    localizations = data["localizations"]
    assert isinstance(localizations, dict) and "en" in localizations, "English fallback is required"
    for content in localizations.values():
        for label in ("title", "continueTitle", "detailsTitle"):
            value = content[label]
            assert isinstance(value, str) and value.strip() and len(value) <= 120, f"invalid {label}"
        features = content["features"]
        assert isinstance(features, list) and 1 <= len(features) <= 6, "use 1 to 6 features"
        for feature in features:
            for key, limit in (("symbol", 100), ("title", 120), ("body", 600)):
                value = feature[key]
                assert isinstance(value, str) and value.strip() and len(value) <= limit, f"invalid feature {key}"
    return data["enabled"]


if __name__ == "__main__":
    try:
        enabled = validate(sys.argv[1], sys.argv[2])
    except (AssertionError, KeyError, ValueError, OSError, TypeError, IndexError) as error:
        raise SystemExit(f"WhatsNew validation failed: {error}")
    print(f"WhatsNew content valid; automatic presentation {'enabled' if enabled else 'disabled'}")
