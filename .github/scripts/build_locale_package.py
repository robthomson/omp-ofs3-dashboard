#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[2]
SOURCE_APP_DIR = ROOT / "src" / "ofs3"
I18N_BUILDER = ROOT / "bin" / "i18n" / "build-single-json.py"
I18N_RESOLVER = ROOT / ".vscode" / "scripts" / "resolve_i18n_tags.py"
SOUNDPACK_ROOT = ROOT / "bin" / "sound-generator" / "soundpack"


def update_version_suffix(main_lua_path: Path, version: str) -> None:
    text = main_lua_path.read_text(encoding="utf-8")
    updated_text, replacements = re.subn(
        r'(version\s*=\s*\{[^}]*?suffix\s*=\s*")[^"]*(")',
        lambda match: f'{match.group(1)}{version}{match.group(2)}',
        text,
        count=1,
        flags=re.DOTALL,
    )
    if replacements != 1:
        raise RuntimeError(f"Could not update version suffix in {main_lua_path}")
    main_lua_path.write_text(updated_text, encoding="utf-8")


def copy_soundpack(lang: str, stage_app_dir: Path) -> None:
    source_dir = SOUNDPACK_ROOT / lang
    if not source_dir.is_dir():
        fallback_dir = SOUNDPACK_ROOT / "en"
        print(f"[AUDIO] {source_dir} not found; falling back to {fallback_dir}")
        source_dir = fallback_dir

    if not source_dir.is_dir():
        print(f"[AUDIO] No sound pack found for {lang} or fallback locale en. Skipping.")
        return

    dest_dir = stage_app_dir / "audio" / lang
    shutil.copytree(source_dir, dest_dir, dirs_exist_ok=True)
    print(f"[AUDIO] Copied {source_dir} -> {dest_dir}")


def create_zip(zip_path: Path, lang_root: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()

    with ZipFile(zip_path, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(lang_root.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(lang_root))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build a per-locale OFS3 package from src/ofs3")
    parser.add_argument("--lang", required=True, help="Locale code to package, e.g. en or de")
    parser.add_argument("--version", required=True, help="Version suffix to inject into main.lua")
    parser.add_argument("--artifact", required=True, help="Output zip path, relative to repo root or absolute")
    parser.add_argument("--build-root", default="build", help="Directory used for staging package contents")
    args = parser.parse_args(argv)

    if not SOURCE_APP_DIR.is_dir():
        print(f"ERROR: source app directory not found: {SOURCE_APP_DIR}", file=sys.stderr)
        return 1

    lang_root = (ROOT / args.build_root / args.lang).resolve()
    stage_root = lang_root / "scripts"
    stage_app_dir = stage_root / "ofs3"
    artifact_path = Path(args.artifact)
    if not artifact_path.is_absolute():
        artifact_path = (ROOT / artifact_path).resolve()

    if lang_root.exists():
        shutil.rmtree(lang_root)

    shutil.copytree(SOURCE_APP_DIR, stage_app_dir)
    print(f"[BUILD] Staged {SOURCE_APP_DIR} -> {stage_app_dir}")

    i18n_dir = stage_app_dir / "i18n"
    i18n_dir.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        [
            sys.executable,
            str(I18N_BUILDER),
            "--only",
            args.lang,
            "--out-dir",
            str(i18n_dir),
        ],
        check=True,
        cwd=ROOT,
    )

    locale_json = i18n_dir / f"{args.lang}.json"
    if not locale_json.is_file():
        print(f"ERROR: expected locale bundle was not created: {locale_json}", file=sys.stderr)
        return 1

    subprocess.run(
        [
            sys.executable,
            str(I18N_RESOLVER),
            "--json",
            str(locale_json),
            "--root",
            str(stage_root),
        ],
        check=True,
        cwd=ROOT,
    )

    copy_soundpack(args.lang, stage_app_dir)
    update_version_suffix(stage_app_dir / "main.lua", args.version)
    create_zip(artifact_path, lang_root)
    print(f"[BUILD] Created {artifact_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
