"""Verify all four release APKs use the pinned certificate and intended version codes."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys


def verify_certificate(output, expected):
    # New apksigner versions prefix labels with the signature scheme (V2 Signer:).
    # Inspect certificate digests only (never public-key or source-stamp hashes).
    lines = [line.strip() for line in output.splitlines()
             if re.match(r'^(?:Signer |V\d+(?:\.\d+)? Signer:)', line.strip())
             and ' certificate SHA-256 digest:' in line]
    certificates = [line.rsplit(':', 1)[-1].strip().lower() for line in lines]
    if not certificates or any(cert != expected for cert in certificates):
        raise ValueError(f'signing certificate mismatch: expected {expected}, got {certificates}')


EXPECTED_APPLICATION_ID = 'com.flutify.music.flutify_app.fork'


def verify_application_id(metadata, expected=EXPECTED_APPLICATION_ID):
    match = re.search(r"^package: name='([^']+)'", metadata, re.MULTILINE)
    if match is None or match[1] != expected:
        actual = match[1] if match is not None else 'missing'
        raise ValueError(f'applicationId mismatch: expected {expected}, got {actual}')


def verify(directory, build_number):
    expected = os.environ['ANDROID_SIGNING_CERT_SHA256'].replace(':', '').lower()
    if not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('Missing or invalid pinned Android certificate SHA-256')
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ['ANDROID_SDK_ROOT'])
    versions = sorted((sdk / 'build-tools').iterdir(),
                      key=lambda path: [int(n) for n in re.findall(r'\d+', path.name)])
    build_tools = versions[-1]
    suffix = '.bat' if os.name == 'nt' else ''
    apks = {
        'app-release.apk': 0,
        'app-armeabi-v7a-release.apk': 1000,
        'app-arm64-v8a-release.apk': 2000,
        'app-x86_64-release.apk': 4000,
    }
    for name, abi_offset in apks.items():
        apk = directory / name
        output = subprocess.check_output(
            [str(build_tools / ('apksigner' + suffix)), 'verify', '--verbose', '--print-certs', str(apk)],
            text=True)
        try:
            verify_certificate(output, expected)
        except ValueError as error:
            raise ValueError(f'{name}: {error}; verifier output: {output}') from error
        metadata = subprocess.check_output(
            [str(build_tools / ('aapt.exe' if os.name == 'nt' else 'aapt')), 'dump', 'badging', str(apk)], text=True)
        try:
            verify_application_id(metadata)
        except ValueError as error:
            raise ValueError(f'{name}: {error}') from error
        code = re.search(r"versionCode='(\d+)'", metadata)
        if code is None or int(code[1]) != build_number + abi_offset:
            raise ValueError(f'{name}: unexpected versionCode')
        resources = subprocess.check_output(
            [str(build_tools / ('aapt.exe' if os.name == 'nt' else 'aapt')), 'dump', 'resources', str(apk)], text=True)
        for icon in ('ic_stat_music', 'audio_service_play_arrow', 'audio_service_pause',
                     'audio_service_skip_previous', 'audio_service_skip_next', 'audio_service_stop'):
            if f'drawable/{icon}' not in resources:
                raise ValueError(f'{name}: missing media notification icon {icon}')
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        print(f'{name}: signature verified, versionCode={code[1]}, SHA256={digest}')
    print('All four APKs use the pinned signing certificate.')


if __name__ == '__main__':
    verify(Path(sys.argv[1]), int(sys.argv[2]))
