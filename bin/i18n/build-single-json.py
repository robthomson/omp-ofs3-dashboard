# i18n/build-single-json.py
#!/usr/bin/env python3
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

# Source root: i18n/json/**/<locale>.json
JSON_ROOT = Path(__file__).parent / "json"

# Default output root: scripts/ofs3/i18n/<locale>.json
DEFAULT_OUT_DIR = (Path(__file__).parent / ".." / ".." / "scripts" / "ofs3" / "i18n").resolve()


def insert_nested(root: dict, rel_dir: str, leaf: dict) -> None:
    """Place the leaf dict under nested keys derived from rel_dir (e.g. 'widgets/dashboard')."""
    cur = root
    if rel_dir and rel_dir != ".":
        for part in rel_dir.replace("\\", "/").split("/"):
            if not part:
                continue
            cur = cur.setdefault(part, {})
    # shallow-merge at this level
    for key, value in leaf.items():
        if isinstance(value, dict) and isinstance(cur.get(key), dict):
            cur[key] = {**cur[key], **value}
        else:
            cur[key] = value


def discover_locale_files():
    """Yield tuples (locale, file_path, rel_dir) for every i18n/json/**/<locale>.json."""
    for dirpath, _, files in os.walk(JSON_ROOT):
        rel_dir = os.path.relpath(dirpath, JSON_ROOT)
        for filename in files:
            if not filename.lower().endswith(".json"):
                continue
            locale = filename[:-5]
            if not locale:
                continue
            yield (locale, Path(dirpath) / filename, rel_dir)


def main(argv=None):
    if not JSON_ROOT.exists():
        print(f"ERROR: source directory not found: {JSON_ROOT}", file=sys.stderr)
        return 1

    import argparse

    parser = argparse.ArgumentParser(
        description="Build merged per-locale JSON files from i18n/json/**/<locale>.json"
    )
    parser.add_argument("--only", nargs="*", help="Limit to specific locales (e.g. --only en de fr)")
    parser.add_argument("--out-dir", help="Optional output directory for generated <locale>.json files")
    args = parser.parse_args(argv)

    merged_per_locale: dict[str, dict] = defaultdict(dict)
    counts_per_locale: dict[str, int] = defaultdict(int)
    requested_locales = list(dict.fromkeys(args.only or []))
    discovered_locales: set[str] = set()
    errors = []

    for locale, file_path, rel_dir in discover_locale_files():
        if args.only and locale not in args.only:
            continue
        discovered_locales.add(locale)
        try:
            with file_path.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
        except Exception as exc:
            errors.append(f"{file_path}: {exc}")
            continue
        insert_nested(merged_per_locale[locale], rel_dir, data)
        counts_per_locale[locale] += 1

    out_dir = Path(args.out_dir).resolve() if args.out_dir else DEFAULT_OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    written = 0
    for locale in sorted(merged_per_locale.keys()):
        out_path = out_dir / f"{locale}.json"
        with out_path.open("w", encoding="utf-8") as handle:
            json.dump(merged_per_locale[locale], handle, ensure_ascii=False, indent=2, sort_keys=True)
        written += 1
        print(f"✔ Wrote {out_path}  (from {counts_per_locale[locale]} source file(s))")

    if errors:
        print("\nSome files could not be read/parsed:", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)
        return 1

    if requested_locales:
        missing_locales = [locale for locale in requested_locales if locale not in discovered_locales]
        if missing_locales:
            print(
                "ERROR: Missing locale source JSON for: " + ", ".join(sorted(missing_locales)),
                file=sys.stderr,
            )
            return 1

    if written == 0:
        if requested_locales:
            print(
                "ERROR: No locale files were generated for requested locale(s): "
                + ", ".join(requested_locales),
                file=sys.stderr,
            )
        else:
            print("ERROR: No locale files found under " + str(JSON_ROOT), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
