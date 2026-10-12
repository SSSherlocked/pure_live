import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import check_text_styles  # noqa: E402


class CheckTextStylesTest(unittest.TestCase):
    def _root(self, files: dict[str, str]) -> Path:
        root = Path(tempfile.mkdtemp())
        for rel, text in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        return root

    def test_flags_literal_sizes_and_numbered_styles(self):
        root = self._root({
            'lib/a.dart': 'final s = TextStyle(fontSize: 13);\nfinal t = AppTextStyles.t12;\n',
        })
        found = check_text_styles.violations(root)
        self.assertEqual(len(found), 2)
        self.assertIn('lib/a.dart:1', found[0])
        self.assertIn('lib/a.dart:2', found[1])

    def test_roles_settings_and_comments_pass(self):
        root = self._root({
            'lib/a.dart': (
                'final s = AppText.of(context).body;\n'
                'final d = TextStyle(fontSize: settings.chatListFontSize.v);\n'
                '// fontSize: 13 in a comment\n'
            ),
        })
        self.assertEqual(check_text_styles.violations(root), [])

    def test_allowed_files_and_vendored_getx_are_skipped(self):
        root = self._root({
            'lib/core/theme/app_text.dart': 'fontSize: 13',
            'lib/get/x.dart': 'fontSize: 13',
        })
        self.assertEqual(check_text_styles.violations(root), [])

    def test_the_repository_passes(self):
        self.assertEqual(check_text_styles.violations(), [])


if __name__ == '__main__':
    unittest.main()
