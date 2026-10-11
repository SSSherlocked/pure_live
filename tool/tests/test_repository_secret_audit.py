"""Secret scanning in the repository audit stays strict."""
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("repository_audit", ROOT / "tool/audit_repository.py")
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)

# Assembled at run time so this file does not itself trip the secret scan.
PRIVATE_KEY = "-----BEGIN " + "PRIVATE KEY-----\nMIIBVQIBADANBgkqhkiG9w0BAQEFAASCAT8wggE7\n-----END " + "PRIVATE KEY-----\n"


class RepositorySecretAuditTest(unittest.TestCase):
    def test_private_keys_are_rejected_anywhere(self):
        for path in ("android/key.pem", "test/fixtures/tls/localhost-key.pem", "lib/foo.dart"):
            with self.subTest(path=path):
                errors, notes = audit.secret_findings(path, PRIVATE_KEY)
                self.assertEqual(errors[0]["rule"], "private_key")
                self.assertEqual(notes, [])

    def test_tokens_are_rejected(self):
        for token, rule in (("ghp_" + "A" * 30, "github_token"), ("AKIA" + "A" * 16, "aws_access_key")):
            with self.subTest(rule=rule):
                errors, _ = audit.secret_findings("lib/config.dart", token)
                self.assertEqual(errors[0]["rule"], rule)

    def test_clean_text_has_no_findings(self):
        errors, notes = audit.secret_findings("lib/main.dart", "void main() {}\n")
        self.assertEqual(errors, [])
        self.assertEqual(notes, [])


if __name__ == "__main__":
    unittest.main()
