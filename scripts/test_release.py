import tempfile
import unittest
from pathlib import Path
from release import next_version, verify_feed


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
            (directory / "GitGaze.zip").write_bytes(b"archive")
            xml = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
              <sparkle:version>1.2.3</sparkle:version><enclosure length="7" sparkle:edSignature="sample"
              url="https://github.com/AlexanderHeffernan/GitGaze/releases/download/v1.2.3/GitGaze.zip" />
              </item></channel></rss>'''
            feed = directory / "appcast.xml"
            feed.write_text(xml)
            verify_feed(directory, "1.2.3")
            for wrong in [xml.replace("/v1.2.3/", "/latest/"), xml.replace('sparkle:edSignature="sample"', ''),
                          xml.replace('length="7"', 'length="8"'), xml.replace('>1.2.3<', '>1.2.2<')]:
                feed.write_text(wrong)
                with self.assertRaises(ValueError):
                    verify_feed(directory, "1.2.3")


if __name__ == "__main__":
    unittest.main()
