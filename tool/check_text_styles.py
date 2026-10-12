"""Keeps UI text on the AppText roles (lib/core/theme/app_text.dart).

Fails when Dart code under lib/ names a font size (`fontSize: 13`) or uses the
retired numbered styles (`AppTextStyles.t13`). Text with its own size setting
(the danmaku, the chat list) passes its setting, not a literal, so it is not
caught. The few files that legitimately hold literal sizes are listed below.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Files allowed to hold a literal size, with the reason.
ALLOWED = {
    # The text role definitions themselves.
    'lib/core/theme/app_text.dart',
    # Danmaku template presets: stored danmaku sizes, not UI text.
    'lib/core/player/presentation/danmaku/danmaku_viewing_preset.dart',
    # Fallbacks for a missing theme slot, never shown in practice.
    'lib/core/widgets/refresh_indicators.dart',
}
# The vendored GetX copy is not app UI.
SKIPPED_DIRS = ('lib/get/',)

LITERAL_SIZE = re.compile(r'\bfontSize:\s*\d')
NUMBERED_STYLE = re.compile(r'\bAppTextStyles\.t\d+')


def violations(root: Path = ROOT) -> list[str]:
    found = []
    for path in sorted((root / 'lib').rglob('*.dart')):
        rel = path.relative_to(root).as_posix()
        if rel in ALLOWED or rel.startswith(SKIPPED_DIRS):
            continue
        for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            code = line.split('//', 1)[0]
            if LITERAL_SIZE.search(code):
                found.append(f'{rel}:{number}: literal font size; use an AppText role')
            if NUMBERED_STYLE.search(code):
                found.append(f'{rel}:{number}: AppTextStyles.tNN; use AppText.of(context)')
    return found


def main() -> int:
    found = violations()
    for item in found:
        print(f'::error::{item}')
    if found:
        print(f'{len(found)} text style violation(s). See lib/core/theme/app_text.dart.')
        return 1
    print('Text styles: every UI text uses an AppText role.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
