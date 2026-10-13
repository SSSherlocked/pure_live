"""Keeps every settings page at the shared content width (SettingsContentWidth).

CLAUDE.md asks settings bodies to sit in `SettingsContentWidth` (a fixed
content width, the margins beside it scrolling the page). Pages kept missing
it because nothing checked: this fails when a page in the settings tree
builds a `Scaffold` without one. The tree is the settings directories plus
the pages opened from them that live elsewhere; a page that is not a
settings body (a full-screen image viewer) is listed with its reason.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Directories whose pages are all settings pages.
SETTINGS_DIRS = (
    'lib/features/settings/',
    'lib/features/about/',
    'lib/features/backup/',
    'lib/features/web_dav/',
)
# Settings pages that live elsewhere: opened from 设置 but owned by a domain.
SETTINGS_FILES = (
    'lib/domains/recorder/presentation/pages/record_settings/record_settings_page.dart',
    'lib/domains/account/presentation/account/account_page.dart',
    'lib/domains/live/presentation/hot_areas/hot_areas_page.dart',
    'lib/domains/iptv/presentation/iptv_page.dart',
    'lib/features/backup/log_page.dart',
)
# Scaffolds that are not a settings body, with the reason.
ALLOWED = {
    # The help dialog's full-screen image preview.
    'lib/features/web_dav/web_dav_help.dart',
}

SCAFFOLD = re.compile(r'\bScaffold\(')
# The widget, or its width for a sliver layout that pads to the same width
# itself (WebDAV keeps a full-width app bar above the content).
WIDTH = re.compile(r'\bSettingsContentWidth(\(|\.width\b)')


def _in_scope(rel: str) -> bool:
    return rel.startswith(SETTINGS_DIRS) or rel in SETTINGS_FILES


def violations(root: Path = ROOT) -> list[str]:
    found = []
    for path in sorted((root / 'lib').rglob('*.dart')):
        rel = path.relative_to(root).as_posix()
        if not _in_scope(rel) or rel in ALLOWED:
            continue
        code = '\n'.join(line.split('//', 1)[0] for line in path.read_text(encoding='utf-8').splitlines())
        if SCAFFOLD.search(code) and not WIDTH.search(code):
            found.append(f'{rel}: builds a Scaffold without SettingsContentWidth')
    for rel in SETTINGS_FILES:
        if not (root / rel).exists():
            found.append(f'{rel}: listed settings page no longer exists; update SETTINGS_FILES')
    return found


def main() -> int:
    found = violations()
    if found:
        print('Settings pages must hold their body in SettingsContentWidth:')
        for line in found:
            print(f'  {line}')
        return 1
    print('Settings width: every settings page uses SettingsContentWidth.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
