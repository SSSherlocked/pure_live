"""The app's version: one input, everything else derived.

The release workflow's `version` input (e.g. 3.2.2) is the single source:

  stamp   Writes it into pubspec.yaml (`version: 3.2.2+<build>`) before a
          build, so Flutter, fastforge, the installers and the artifact names
          all read the same value. The build number rises by one whenever the
          version changes and stays for a rebuild of the same version, so
          every job of one run arrives at the same number. Without an input
          the pubspec version is used as it is.
  notes   Prints the `# Pure Live v<version>` section of RELEASE_NOTES.md,
          the release body and the update dialog's text. Fails when the
          section is missing.
  feed    Regenerates assets/version.json (the in-app update feed) for a
          published release: the version, build, notes and download link once
          at the top; a platform the release did not build keeps its previous
          entry, so it is not offered a package that does not exist.
  check   CI: the feed never advertises a version ahead of pubspec.yaml, and
          the pubspec version has a RELEASE_NOTES.md section once the feed
          has caught up with it.

Outputs for GitHub Actions are written to $GITHUB_OUTPUT when it is set.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = 'pubspec.yaml'
FEED = 'assets/version.json'
NOTES = 'RELEASE_NOTES.md'
REPOSITORY = 'SSSherlocked/pure_live'
PLATFORMS = ('android', 'windows', 'linux', 'macos', 'ios')

_VERSION_LINE = re.compile(r'(?m)^version:[ \t]*([0-9A-Za-z.+\-]+)[ \t]*$')
_SEMVER = re.compile(r'^\d+\.\d+\.\d+$')


def parse_version(text: str) -> tuple[int, ...]:
    if not _SEMVER.match(text):
        raise ValueError(f'version must look like 1.2.3, got {text!r}')
    return tuple(int(part) for part in text.split('.'))


def normalize_input(raw: str | None) -> str | None:
    value = (raw or '').strip()
    if value.lower().startswith('v'):
        value = value[1:]
    if not value:
        return None
    parse_version(value)
    return value


def read_pubspec(root: Path = ROOT) -> tuple[str, int]:
    match = _VERSION_LINE.search((root / PUBSPEC).read_text(encoding='utf-8'))
    if not match:
        raise ValueError('pubspec.yaml has no version line')
    full = match.group(1)
    name, _, build = full.partition('+')
    parse_version(name)
    return name, int(build or 0)


def stamped(current: tuple[str, int], requested: str | None) -> tuple[str, int]:
    """The version and build a run builds."""
    name, build = current
    if requested is None or requested == name:
        return name, build
    if parse_version(requested) < parse_version(name):
        raise ValueError(f'{requested} is older than the current {name}')
    return requested, build + 1


def write_pubspec(root: Path, name: str, build: int) -> None:
    path = root / PUBSPEC
    text = path.read_text(encoding='utf-8')
    path.write_text(_VERSION_LINE.sub(f'version: {name}+{build}', text, count=1), encoding='utf-8')


def release_notes(root: Path, name: str) -> str:
    text = (root / NOTES).read_text(encoding='utf-8')
    match = re.search(rf'(?m)^# Pure Live v{re.escape(name)}\s*$', text)
    if not match:
        raise ValueError(f'{NOTES} has no "# Pure Live v{name}" section')
    rest = text[match.end():]
    end = re.search(r'(?m)^---\s*$|^# Pure Live v', rest)
    body = (rest[: end.start()] if end else rest).strip()
    if not body:
        raise ValueError(f'the v{name} section of {NOTES} is empty')
    # The release body puts these under its own "### 📝 本次更新".
    return re.sub(r'(?m)^## ', '#### ', body)


def build_feed(previous: dict, name: str, build: int, notes: str, built: set[str]) -> dict:
    url = f'https://github.com/{REPOSITORY}/releases/tag/v{name}'
    abis = previous.get('android_abis') or ['arm64-v8a']
    feed: dict = {
        'version': name,
        'build_number': build,
        'android_abis': abis,
        'version_desc': notes,
        'prerelease': False,
        'download_url': url,
    }
    old_platforms = previous.get('platforms') if isinstance(previous.get('platforms'), dict) else {}
    kept = {}
    for platform in PLATFORMS:
        if platform in built:
            continue
        old = old_platforms.get(platform)
        if isinstance(old, dict) and old.get('version'):
            entry = {key: value for key, value in old.items() if key != 'version_num'}
        elif previous.get('version'):
            entry = {key: previous[key] for key in ('version', 'build_number', 'version_desc', 'prerelease', 'download_url') if key in previous}
        else:
            continue
        kept[platform] = entry
    if kept:
        feed['platforms'] = kept
    return feed


def check(root: Path = ROOT) -> list[str]:
    problems = []
    name, build = read_pubspec(root)
    feed = json.loads((root / FEED).read_text(encoding='utf-8'))
    feed_version = str(feed.get('version', ''))
    try:
        ahead = parse_version(feed_version) > parse_version(name)
    except ValueError:
        problems.append(f'{FEED} has no valid version')
        return problems
    if ahead or (feed_version == name and int(feed.get('build_number', 0)) > build):
        problems.append(f'{FEED} offers {feed_version}+{feed.get("build_number")} but {PUBSPEC} is {name}+{build}')
    if feed_version == name:
        try:
            release_notes(root, name)
        except ValueError as error:
            problems.append(str(error))
    return problems


def _output(**values: object) -> None:
    for key, value in values.items():
        print(f'{key}={value}')
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            for key, value in values.items():
                handle.write(f'{key}={value}\n')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--root', type=Path, default=ROOT, help='repository root (tests)')
    commands = parser.add_subparsers(dest='command', required=True)
    stamp = commands.add_parser('stamp')
    stamp.add_argument('--version', default='')
    notes = commands.add_parser('notes')
    notes.add_argument('--version', required=True)
    notes.add_argument('--out')
    feed = commands.add_parser('feed')
    feed.add_argument('--built', default=','.join(PLATFORMS), help='comma-separated platforms in the release')
    commands.add_parser('check')
    args = parser.parse_args(argv)
    root = args.root

    try:
        if args.command == 'stamp':
            name, build = stamped(read_pubspec(root), normalize_input(args.version))
            write_pubspec(root, name, build)
            _output(version=name, build_number=build, artifact_version=f'{name}-{build}', tag=f'v{name}')
        elif args.command == 'notes':
            text = release_notes(root, normalize_input(args.version) or '')
            if args.out:
                Path(args.out).write_text(text + '\n', encoding='utf-8')
            else:
                print(text)
        elif args.command == 'feed':
            name, build = read_pubspec(root)
            path = root / FEED
            previous = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
            built = {item.strip() for item in args.built.split(',') if item.strip()}
            data = build_feed(previous, name, build, release_notes(root, name), built)
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            print(f'{FEED}: {name}+{build}')
        elif args.command == 'check':
            problems = check(root)
            for problem in problems:
                print(f'::error::{problem}')
            if problems:
                return 1
            print('Version: pubspec.yaml, the update feed and RELEASE_NOTES.md agree.')
    except ValueError as error:
        print(f'::error::{error}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
