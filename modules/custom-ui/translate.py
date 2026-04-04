#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path


def env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def normalize_target_language(value: str) -> str:
    value = (value or "").strip()
    if not value:
        return ""
    lowered = value.lower().replace("_", "-")
    if lowered.startswith("de"):
        return "DE"
    if lowered.startswith("en-us"):
        return "EN-US"
    if lowered.startswith("en-gb"):
        return "EN-GB"
    if lowered.startswith("en"):
        return "EN-US"
    return value.upper()


def detect_target_language() -> str:
    explicit = normalize_target_language(env("CUSTOM_UI_TRANSLATION_TARGET_LANGUAGE"))
    if explicit:
        return explicit

    for name in ("LC_ALL", "LC_MESSAGES", "LANG"):
        detected = normalize_target_language(env(name))
        if detected:
            return detected

    return ""


def read_auth_key() -> str:
    direct = env("DEEPL_AUTH_KEY")
    if direct:
        return direct

    key_file = env("CUSTOM_UI_TRANSLATION_API_KEY_FILE")
    if not key_file:
        return ""

    path = Path(key_file)
    if not path.exists():
        return ""

    return path.read_text(encoding="utf-8").strip()


def cache_dir() -> Path:
    root = Path(env("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    path = root / "custom-ui-translation" / "deepl"
    path.mkdir(parents=True, exist_ok=True)
    return path


def cache_key(source_language: str, target_language: str, text: str) -> str:
    material = "\n".join([source_language, target_language, text])
    return hashlib.sha256(material.encode("utf-8")).hexdigest()


def load_cached(source_language: str, target_language: str, text: str):
    path = cache_dir() / f"{cache_key(source_language, target_language, text)}.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("translation")
    except Exception:
        return None


def save_cached(source_language: str, target_language: str, original: str, translation: str):
    path = cache_dir() / f"{cache_key(source_language, target_language, original)}.json"
    payload = {
        "source_language": source_language,
        "target_language": target_language,
        "original": original,
        "translation": translation,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def translate_deepl(texts, source_language: str, target_language: str):
    auth_key = read_auth_key()
    if not auth_key or not target_language or target_language.startswith("EN"):
        return texts

    results = list(texts)
    missing = []
    missing_indexes = []

    for index, text in enumerate(texts):
        cached = load_cached(source_language, target_language, text)
        if cached is not None:
            results[index] = cached
        else:
            missing_indexes.append(index)
            missing.append(text)

    if not missing:
        return results

    payload = [
        ("auth_key", auth_key),
        ("source_lang", source_language),
        ("target_lang", target_language),
        ("preserve_formatting", "1"),
    ]
    for text in missing:
        payload.append(("text", text))

    body = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        "https://api-free.deepl.com/v2/translate",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
    except Exception:
        return texts

    translated = data.get("translations", [])
    if len(translated) != len(missing):
        return texts

    for index, entry, original in zip(missing_indexes, translated, missing):
        translated_text = entry.get("text", original)
        results[index] = translated_text
        save_cached(source_language, target_language, original, translated_text)

    return results


def translate_texts(texts):
    if env("CUSTOM_UI_TRANSLATION_ENABLE", "0") != "1":
        return texts

    provider = env("CUSTOM_UI_TRANSLATION_PROVIDER", "deepl").lower()
    source_language = env("CUSTOM_UI_TRANSLATION_SOURCE_LANGUAGE", "EN").upper()
    target_language = detect_target_language()

    if not target_language or target_language.startswith("EN"):
        return texts

    if provider == "deepl":
        return translate_deepl(texts, source_language, target_language)

    return texts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--text")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.json:
        texts = json.loads(sys.stdin.read())
        json.dump(translate_texts(texts), sys.stdout, ensure_ascii=False)
        return

    if args.text is not None:
        translated = translate_texts([args.text])[0]
        sys.stdout.write(translated)
        return

    parser.error("use --text or --json")


if __name__ == "__main__":
    main()
