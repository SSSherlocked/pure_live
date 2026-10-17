import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import check_settings_width  # noqa: E402


class CheckSettingsWidthTest(unittest.TestCase):
    def _root(self, files: dict[str, str], with_listed: bool = True) -> Path:
        root = Path(tempfile.mkdtemp())
        if with_listed:
            for rel in check_settings_width.SETTINGS_FILES:
                files.setdefault(rel, 'final x = SettingsContentWidth(child: list);\nScaffold(body: x);\n')
        for rel, text in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        return root

    def test_flags_a_settings_page_without_the_width(self):
        root = self._root({'lib/features/settings/pages/a.dart': 'return Scaffold(body: ListView());\n'})
        found = check_settings_width.violations(root)
        self.assertEqual(len(found), 1)
        self.assertIn('lib/features/settings/pages/a.dart', found[0])

    def test_flags_a_row_value_written_by_hand(self):
        root = self._root({
            'lib/features/settings/pages/a.dart': (
                'return Scaffold(body: SettingsContentWidth(child: x));\n'
                'buildTile(trailing: Text(label, style: s));\n'
                'buildTile(trailing: context.buildTileValue(label));\n'
            ),
        })
        found = check_settings_width.violations(root)
        self.assertEqual(len(found), 1)
        self.assertIn('a.dart:2', found[0])

    def test_widget_or_shared_width_passes(self):
        root = self._root({
            'lib/features/settings/pages/a.dart': 'return Scaffold(body: SettingsContentWidth(child: ListView()));\n',
            'lib/features/web_dav/b.dart': 'final w = SettingsContentWidth.width;\nreturn Scaffold();\n',
        })
        self.assertEqual(check_settings_width.violations(root), [])

    def test_out_of_scope_and_allowed_files_are_skipped(self):
        root = self._root({
            'lib/domains/live/a.dart': 'return Scaffold(body: ListView());\n',
            'lib/features/web_dav/web_dav_help.dart': 'return Scaffold(body: image);\n',
            'lib/features/settings/pages/c.dart': '// Scaffold( in a comment\nfinal x = 1;\n',
        })
        self.assertEqual(check_settings_width.violations(root), [])

    def test_a_listed_page_that_moved_is_reported(self):
        root = self._root({}, with_listed=False)
        found = check_settings_width.violations(root)
        self.assertEqual(len(found), len(check_settings_width.SETTINGS_FILES))


if __name__ == '__main__':
    unittest.main()
