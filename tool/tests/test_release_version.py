import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import release_version as rv  # noqa: E402

NOTES = """# 版本说明

intro

# Pure Live v3.2.1

old notes

---

# Pure Live v3.2.2

## 新功能

- a thing

---
"""


class ReleaseVersionTest(unittest.TestCase):
    def _root(self, version='3.2.1+4110', feed=None) -> Path:
        root = Path(tempfile.mkdtemp())
        (root / 'pubspec.yaml').write_text(f'name: x\nversion: {version}\n\nenvironment:\n', encoding='utf-8')
        (root / 'RELEASE_NOTES.md').write_text(NOTES, encoding='utf-8')
        (root / 'assets').mkdir()
        (root / 'assets/version.json').write_text(json.dumps(feed or {'version': '3.2.1', 'build_number': 4110}))
        return root

    def test_a_new_version_raises_the_build_and_a_rebuild_keeps_it(self):
        self.assertEqual(rv.stamped(('3.2.1', 4110), '3.2.2'), ('3.2.2', 4111))
        self.assertEqual(rv.stamped(('3.2.1', 4110), '3.2.1'), ('3.2.1', 4110))
        self.assertEqual(rv.stamped(('3.2.1', 4110), None), ('3.2.1', 4110))

    def test_a_republish_keeps_the_version_and_raises_the_build(self):
        self.assertEqual(rv.stamped(('3.2.1', 4110), '3.2.1', republish=True), ('3.2.1', 4111))
        for requested in ('3.2.2', None):
            with self.subTest(requested=requested), self.assertRaises(ValueError):
                rv.stamped(('3.2.1', 4110), requested, republish=True)

    def test_an_older_or_malformed_version_is_refused(self):
        with self.assertRaises(ValueError):
            rv.stamped(('3.2.1', 4110), '3.1.9')
        with self.assertRaises(ValueError):
            rv.normalize_input('3.2')
        self.assertEqual(rv.normalize_input(' v3.2.2 '), '3.2.2')
        self.assertIsNone(rv.normalize_input(''))

    def test_stamping_touches_only_the_version_line(self):
        root = self._root()
        rv.write_pubspec(root, '3.2.2', 4111)
        self.assertEqual(
            (root / 'pubspec.yaml').read_text(encoding='utf-8'),
            'name: x\nversion: 3.2.2+4111\n\nenvironment:\n',
        )

    def test_notes_come_from_the_versions_own_section(self):
        root = self._root()
        notes = rv.release_notes(root, '3.2.2')
        self.assertIn('#### 新功能', notes)
        self.assertNotIn('old notes', notes)
        with self.assertRaises(ValueError):
            rv.release_notes(root, '9.9.9')

    def test_the_feed_keeps_platforms_the_release_did_not_build(self):
        previous = {
            'version': '3.2.1', 'build_number': 4110, 'version_num': 1,
            'download_url': 'u1', 'version_desc': 'n1',
            'platforms': {'ios': {'version': '3.1.0', 'build_number': 4000, 'version_num': 2}},
        }
        feed = rv.build_feed(previous, '3.2.2', 4111, 'notes', {'android', 'windows', 'linux', 'macos'})
        self.assertEqual(feed['version'], '3.2.2')
        self.assertEqual(feed['download_url'], 'https://github.com/SSSherlocked/pure_live/releases/tag/v3.2.2')
        self.assertNotIn('version_num', feed)
        self.assertEqual(list(feed['platforms']), ['ios'])
        self.assertEqual(feed['platforms']['ios']['version'], '3.1.0')
        self.assertNotIn('version_num', feed['platforms']['ios'])
        everything = rv.build_feed(previous, '3.2.2', 4111, 'notes', set(rv.PLATFORMS))
        self.assertNotIn('platforms', everything)

    def test_check_flags_a_feed_ahead_of_pubspec(self):
        self.assertEqual(rv.check(self._root()), [])
        ahead = self._root(feed={'version': '3.2.2', 'build_number': 4111})
        self.assertTrue(rv.check(ahead))

    def _history(self, notes: str) -> Path:
        root = Path(tempfile.mkdtemp())
        (root / 'RELEASE_NOTES.md').write_text(notes, encoding='utf-8')

        def git(*args):
            subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)

        git('init', '-q')
        git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'feat: old feature')
        git('tag', 'v3.2.1')
        for subject in (
            'feat(room): a new panel',
            'fix: no crash',
            'style(player): bolder title',
            'chore: release v3.2.2 (3.2.2+4111) [skip ci]',
            'ci: faster checks',
            'docs: notes',
            'Merge branch x',
        ):
            git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', subject)
        return root

    def test_a_missing_section_is_generated_from_the_commits_since_the_last_release(self):
        root = self._history('# 版本说明\n\nintro\n\n# Pure Live v3.2.1\n\nold\n\n---\n')
        self.assertTrue(rv.ensure_release_notes(root, '3.2.2'))
        text = (root / 'RELEASE_NOTES.md').read_text(encoding='utf-8')
        # Above the previous release, below the intro.
        self.assertLess(text.index('# Pure Live v3.2.2'), text.index('# Pure Live v3.2.1'))
        self.assertLess(text.index('intro'), text.index('# Pure Live v3.2.2'))
        notes = rv.release_notes(root, '3.2.2')
        self.assertIn('- room：a new panel', notes)
        self.assertIn('- no crash', notes)
        self.assertIn('- player：bolder title', notes)
        for left_out in ('old feature', 'release v3.2.2', 'faster checks', 'docs: notes', 'Merge'):
            self.assertNotIn(left_out, notes)
        self.assertLess(notes.index('新功能'), notes.index('修复'))

    def test_a_hand_written_section_is_kept(self):
        root = self._history('# Pure Live v3.2.2\n\n- 手写的说明\n\n---\n')
        self.assertFalse(rv.ensure_release_notes(root, '3.2.2'))
        self.assertEqual(rv.release_notes(root, '3.2.2'), '- 手写的说明')

    def test_the_repository_agrees(self):
        self.assertEqual(rv.check(), [])


if __name__ == '__main__':
    unittest.main()
