#!/usr/bin/env python3
"""Download pinned offline speech dependencies. Requires macOS curl and ditto."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FRAMEWORK_URL = 'https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.3/whisper-v1.8.3-xcframework.zip'
FRAMEWORK_SHA = 'a970006f256c8e689bc79e73f7fa7ddb8c1ed2703ad43ee48eb545b5bb6de6af'
MODEL_URL = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin'
MODEL_SHA = '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe'


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def download(url, destination, expected):
    subprocess.run(['curl', '--fail', '--location', '--retry', '3',
                    '--connect-timeout', '30', '--proto', '=https',
                    '--output', str(destination), url], check=True)
    if digest(destination) != expected:
        raise RuntimeError('SHA-256 mismatch: refusing to install ' + destination.name)


def main():
    model = ROOT / 'MoneyBotik/Resources/ggml-base.bin'
    vendor = ROOT / 'Vendor'
    vendor.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='moneybotik-', dir=ROOT) as temporary:
        staging = Path(temporary)
        if not model.exists() or digest(model) != MODEL_SHA:
            print('Downloading multilingual Whisper base model...', flush=True)
            downloaded = staging / model.name
            download(MODEL_URL, downloaded, MODEL_SHA)
            model.parent.mkdir(parents=True, exist_ok=True)
            downloaded.replace(model)
        # Always verify the upstream archive before extracting the framework.
        print('Downloading whisper.cpp 1.8.3 XCFramework...', flush=True)
        archive = staging / 'whisper.zip'
        download(FRAMEWORK_URL, archive, FRAMEWORK_SHA)
        subprocess.run(['ditto', '-x', '-k', str(archive), str(vendor)], check=True)
    framework = vendor / 'build-apple/whisper.xcframework'
    if not (framework / 'Info.plist').is_file():
        raise RuntimeError('Unexpected framework layout')
    print('Dependencies verified. Open MoneyBotik.xcodeproj in Xcode.')


if __name__ == '__main__':
    main()
