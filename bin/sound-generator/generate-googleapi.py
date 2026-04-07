#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import csv
import codecs
import hashlib
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

try:
    import sox
except ImportError:
    sox = None
try:
    from google.cloud import texttospeech
except ImportError:
    texttospeech = None


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "src" / "ofs3"
SOUNDPACK_ROOT = REPO_ROOT / "bin" / "sound-generator" / "soundpack"
PLAY_FILE_RE = re.compile(
    r"""playFile\(\s*(['"])(?P<pkg>[^'"]+)\1\s*,\s*(['"])(?P<file>[^'"]+)\3\s*\)""",
    flags=re.DOTALL,
)


def discover_used_prompts(source_root=SOURCE_ROOT):
    prompts = set()
    for path in sorted(source_root.rglob("*.lua")):
        source = path.read_text(encoding="utf-8", errors="ignore")
        for match in PLAY_FILE_RE.finditer(source):
            pkg = match.group("pkg").strip().strip("/")
            file_name = match.group("file").strip().lstrip("/")
            if pkg and file_name:
                prompts.add(f"{pkg}/{file_name}")
    return sorted(prompts)


def extract_csv(path, base_dir, variant, used_prompts=None):
    result = []
    selected_prompts = set(used_prompts or [])
    with codecs.open(path, "r", "utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or not any(cell.strip() for cell in row):
                continue
            rel_path = row[0].strip()
            if not rel_path or rel_path.startswith("#"):
                continue

            text = row[1].strip() if len(row) > 1 else ""
            options_text = row[2].strip() if len(row) > 2 else ""
            description = row[3].strip() if len(row) > 3 else ""

            if selected_prompts and rel_path not in selected_prompts:
                continue

            output_path = SOUNDPACK_ROOT / base_dir / variant / rel_path
            options = {}
            for part in options_text.split(";"):
                if part:
                    key, value = part.split("=")
                    options[key] = value
            result.append((str(output_path), rel_path, text, options, description))
    return result


def prune_unused_audio(base_dir, variant, used_prompts):
    if not used_prompts:
        return

    target_root = SOUNDPACK_ROOT / base_dir / variant
    if not target_root.is_dir():
        return

    keep = set(used_prompts)
    removed = 0

    for path in sorted(target_root.rglob("*.wav")):
        rel_path = path.relative_to(target_root).as_posix()
        if rel_path not in keep:
            path.unlink()
            removed += 1

    for path in sorted(target_root.rglob("*"), reverse=True):
        if path.is_dir():
            try:
                path.rmdir()
            except OSError:
                pass

    if removed:
        print(f"[AUDIO] Removed {removed} stale prompt file(s) from {target_root}")


class NullCache:
    def get(self, *args, **kwargs):
        return False
    def push(self, *args, **kwargs):
        pass


class PromptsCache:
    def __init__(self, directory):
        self.directory = directory
        if not os.path.exists(directory):
            os.makedirs(directory)

    def path(self, text, options):
        text_hash = hashlib.md5((text + str(options)).encode()).hexdigest()
        return os.path.join(self.directory, text_hash)

    def get(self, filename, text, options):
        cache = self.path(text, options)
        if not os.path.exists(cache):
            return False
        shutil.copy(cache, filename)
        return True

    def push(self, filename, text, options):
        shutil.copy(filename, self.path(text, options))


class BaseGenerator:
    @staticmethod
    def sox(input, output, tempo=None, norm=False, silence=False):
        if sox is None:
            raise RuntimeError("You need sox for python: python -m pip install sox")
        tfm = sox.Transformer()
        tfm.set_output_format(channels=1, rate=16000, encoding="a-law")
        extra_args = []
        if tempo:
            extra_args.extend(["tempo", str(tempo)])
        if norm:
            extra_args.append("norm")
        if silence:
            extra_args.extend(["reverse", "silence", "1", "0.1", "0.1%", "reverse"])
        tfm.build(input, output, extra_args=extra_args)


class GoogleCloudTextToSpeechGenerator(BaseGenerator):
    def __init__(self, voice, speed):
        if texttospeech is None:
            raise RuntimeError(
                "You need google text to speech for python: python -m pip install google-cloud-texttospeech"
            )
        self.voice_code = voice
        self.speed = speed
        self.client = texttospeech.TextToSpeechClient()
        self.voice = texttospeech.VoiceSelectionParams(
            language_code="-".join(voice.split("-")[:2]),
            name=voice
        )

    def cache_prefix(self):
        return "google-%s" % self.voice_code

    def build(self, path, text, options):
        print(path, repr(text), options)
        response = self.client.synthesize_speech(
            input=texttospeech.SynthesisInput(text=text),
            voice=self.voice,
            audio_config=texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.LINEAR16,
                sample_rate_hertz=16000,
                speaking_rate=self.speed * float(options.get("speed", 1.0))
            )
        )
        temp_path = tempfile.mkdtemp()
        tts_output = os.path.join(temp_path, "output.wav")
        with open(tts_output, "wb") as out:
            out.write(response.audio_content)

        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.sox(tts_output, path, silence=True)
        shutil.rmtree(temp_path)


def build(
    engine,
    voice,
    speed,
    csv,
    cache,
    base_dir,
    variant,
    only_missing=False,
    recreate_cache=False,
    all_prompts=False,
    keep_stale_files=False,
):
    if not SOURCE_ROOT.exists():
        print(f"Error: Source tree not found: {SOURCE_ROOT}")
        return 1

    if engine == "google":
        try:
            generator = GoogleCloudTextToSpeechGenerator(voice, speed)
        except RuntimeError as exc:
            print(exc)
            return 1
    else:
        print("Unknown engine %s" % engine)
        return 1

    used_prompts = [] if all_prompts else discover_used_prompts()
    if not all_prompts:
        if not used_prompts:
            print(f"Error: No sound prompts discovered in {SOURCE_ROOT}")
            return 1
        print(f"[AUDIO] Using {len(used_prompts)} prompt(s) referenced by {SOURCE_ROOT}")
        for prompt in used_prompts:
            print(f"[AUDIO]   {prompt}")

    prompts = extract_csv(csv, base_dir, variant, used_prompts=used_prompts)
    prompt_paths = {rel_path for _, rel_path, _, _, _ in prompts}

    if used_prompts:
        missing_prompts = [prompt for prompt in used_prompts if prompt not in prompt_paths]
        if missing_prompts:
            print("Error: CSV is missing prompt(s):")
            for prompt in missing_prompts:
                print(f"  - {prompt}")
            return 1

    if used_prompts and not keep_stale_files:
        prune_unused_audio(base_dir, variant, used_prompts)

    cache = PromptsCache(os.path.join(cache, generator.cache_prefix())) if cache else NullCache()

    for path, _, text, options, _ in prompts:
        if only_missing and os.path.exists(path):
            continue
        elif cache and not recreate_cache and cache.get(path, text, options):
            continue
        else:
            generator.build(path, text, options)
            cache.push(path, text, options)

    return 0


def main():
    if sys.version_info < (3, 0, 0):
        print("%s requires Python 3. Terminating." % __file__)
        return 1

    parser = argparse.ArgumentParser(description="Builder for Ethos audio files")
    parser.add_argument('--csv', action="store", help="CSV input file", required=True)
    parser.add_argument('--engine', action="store", help="TTS engine", default="gtts")
    parser.add_argument('--voice', action="store", help="TTS language", required=True)
    parser.add_argument('--cache', action="store", help="TTS files cache")
    parser.add_argument('--recreate-cache', action="store_true", help="Recreate files cache")
    parser.add_argument('--only-missing', action="store_true", help="Generate only missing files")
    parser.add_argument('--speed', type=float, help="Voice speed", default=1.0)
    parser.add_argument('--base-dir', action="store", required=True, help="i18n folder name (e.g., en, es)")
    parser.add_argument('--variant', action="store", required=True, help="i18n variant (e.g., male, female)")
    parser.add_argument('--all-prompts', action="store_true", help="Generate every CSV row instead of only the prompts used by src/ofs3")
    parser.add_argument('--keep-stale-files', action="store_true", help="Keep unused generated .wav files in the target soundpack variant")
    parser.add_argument('--list-used', action="store_true", help="List the prompts referenced by src/ofs3 and exit")
    args = parser.parse_args()

    if args.list_used:
        for prompt in discover_used_prompts():
            print(prompt)
        return 0

    return build(
        args.engine, args.voice, args.speed, args.csv, args.cache,
        args.base_dir, args.variant, args.only_missing, args.recreate_cache,
        args.all_prompts, args.keep_stale_files
    )


if __name__ == "__main__":
    exit(main())
