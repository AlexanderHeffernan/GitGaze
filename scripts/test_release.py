import tempfile
import unittest
from pathlib import Path
import base64
import hashlib
import os
from release import next_version, verify_feed
import sign_update


class ReleaseTests(unittest.TestCase):
    def test_versions_handle_initial_release_numeric_order_bumps_and_reruns(self):
        self.assertEqual(next_version("1.0.0", [], []), "1.0.0")
        self.assertEqual(next_version("1.0.0", ["v1.0.9", "v1.0.10", "latest", "v2.0.0-beta"], []), "1.0.11")
        self.assertEqual(next_version("1.1.0", ["v1.0.10"], []), "1.1.0")
        self.assertEqual(next_version("1.0.0", ["v2.0.0"], ["v2.0.0"]), "2.0.0")
        with self.assertRaises(ValueError):
            next_version("garbage", [], [])

    def test_feed_requires_signed_pinned_version_and_matching_archive_length(self):
        with tempfile.TemporaryDirectory() as path:
            directory = Path(path)
            (directory / "Stoke.zip").write_bytes(b"archive")
            xml = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
              <sparkle:version>1.2.3</sparkle:version><enclosure length="7" sparkle:edSignature="sample"
              url="https://github.com/AlexanderHeffernan/Stoke/releases/download/v1.2.3/Stoke.zip" />
              </item></channel></rss>'''
            feed = directory / "appcast.xml"
            feed.write_text(xml)
            verify_feed(directory, "1.2.3")
            for wrong in [xml.replace("/v1.2.3/", "/latest/"), xml.replace('sparkle:edSignature="sample"', ''),
                          xml.replace('length="7"', 'length="8"'), xml.replace('>1.2.3<', '>1.2.2<')]:
                feed.write_text(wrong)
                with self.assertRaises(ValueError):
                    verify_feed(directory, "1.2.3")


class SigningTests(unittest.TestCase):
    """The release signer must produce signatures both updaters accept, for every Sparkle key export format."""
    seed = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    public = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")

    def setUp(self):
        self.original = sign_update.SPARKLE_PUBLIC_KEY, os.environ.get("SPARKLE_PRIVATE_KEY")
        sign_update.SPARKLE_PUBLIC_KEY = base64.b64encode(self.public).decode()

    def tearDown(self):
        sign_update.SPARKLE_PUBLIC_KEY = self.original[0]
        if self.original[1] is None:
            os.environ.pop("SPARKLE_PRIVATE_KEY", None)
        else:
            os.environ["SPARKLE_PRIVATE_KEY"] = self.original[1]

    def test_rfc8032_vector_for_seed_and_legacy_key_formats(self):
        expected = bytes.fromhex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        digest = hashlib.sha512(self.seed).digest()
        scalar = (int.from_bytes(digest[:32], "little") & ((1 << 254) - 8) | (1 << 254)).to_bytes(32, "little")
        for key in [self.seed, self.seed + self.public, scalar + digest[32:] + self.public]:
            os.environ["SPARKLE_PRIVATE_KEY"] = base64.b64encode(key).decode()
            self.assertEqual(sign_update.ed25519_sign(b""), expected)
        self.assertTrue(sign_update.ed25519_verify(b"", expected))
        self.assertFalse(sign_update.ed25519_verify(b"x", expected))

    def test_rejects_a_key_that_does_not_match_the_app(self):
        os.environ["SPARKLE_PRIVATE_KEY"] = base64.b64encode(bytes(32)).decode()
        with self.assertRaises(SystemExit):
            sign_update.ed25519_sign(b"")

    def test_minisign_signature_records_version_and_verifies(self):
        os.environ["SPARKLE_PRIVATE_KEY"] = base64.b64encode(self.seed).decode()
        with tempfile.TemporaryDirectory() as directory:
            payload = Path(directory) / "update.bin"
            payload.write_bytes(b"update")
            lines = base64.b64decode(sign_update.minisign_signature(str(payload), "1.2.3")).decode().splitlines()
        self.assertTrue(lines[2].startswith("trusted comment: ") and lines[2].endswith("\tversion:1.2.3"))
        signature = base64.b64decode(lines[1])
        self.assertEqual(signature[:2], b"ED")
        self.assertTrue(sign_update.ed25519_verify(hashlib.blake2b(b"update", digest_size=64).digest(), signature[10:]))
        self.assertTrue(sign_update.ed25519_verify(signature[10:] + lines[2][len("trusted comment: "):].encode(), base64.b64decode(lines[3])))


if __name__ == "__main__":
    unittest.main()
