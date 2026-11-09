"""Warm Maven's local repository with checksum-verified Kotlin compiler files.

Gradle reuses local Maven artifacts after comparing the remote checksum:
https://docs.gradle.org/current/userguide/dependency_caching.html
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from urllib.request import Request, urlopen

HOSTS = ('https://repo.maven.apache.org/maven2', 'https://repo1.maven.org/maven2')
PINS = json.loads(Path(__file__).with_name('kotlin_compiler_checksums.json').read_text())


def fetch(url):
    return urlopen(Request(url, headers={'User-Agent': 'SMT-FAI-CI'}), timeout=180)


def checksum_file(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def prefetch(version, root):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Expected a stable Kotlin version')
    relative = f'org/jetbrains/kotlin/kotlin-compiler-embeddable/{version}'
    folder = root / relative
    folder.mkdir(parents=True, exist_ok=True)
    for extension in ('jar', 'pom'):
        expected = PINS[version][extension]
        if not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError('Invalid pinned SHA-256')
        name = f'kotlin-compiler-embeddable-{version}.{extension}'
        target = folder / name
        last_error = None
        for host in HOSTS:
            for attempt in range(3):
                temporary = None
                try:
                    if target.exists() and checksum_file(target) == expected:
                        print(f'Verified cached {name}', flush=True)
                        break
                    digest = hashlib.sha256()
                    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as output:
                        temporary = Path(output.name)
                        with fetch(f'{host}/{relative}/{name}') as response:
                            while chunk := response.read(1024 * 1024):
                                digest.update(chunk)
                                output.write(chunk)
                    if digest.hexdigest() != expected:
                        raise ValueError(f'SHA-256 mismatch for {name}')
                    temporary.replace(target)
                    print(f'Verified {name}: {expected}', flush=True)
                    break
                except Exception as error:
                    last_error = error
                    print(f'Download attempt {attempt + 1} on {host}: {error}', flush=True)
                    if temporary is not None:
                        temporary.unlink(missing_ok=True)
                    if attempt < 2:
                        time.sleep(5)
            else:
                continue
            break
        else:
            raise RuntimeError(f'Cannot fetch verified {name}') from last_error


if __name__ == '__main__':
    cache_root = Path(os.environ.get('MAVEN_PREFETCH_ROOT', str(Path.home() / '.m2' / 'repository')))
    for kotlin_version in sys.argv[1:]:
        prefetch(kotlin_version, cache_root)
