import base64
import pathlib
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
import appcast

class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.app = self.root / 'Example.app'
        (self.app / 'Contents').mkdir(parents=True)
        self.info = {
            'CFBundleName': 'Example & Friends', 'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '7',
            'SUPublicEDKey': base64.b64encode(bytes(32)).decode(),
            'SUFeedURL': 'https://github.com/owner/repo/releases/latest/download/appcast.xml',
            'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True, 'LSMinimumSystemVersion': '13.0',
        }
        self.write_info()

    def write_info(self):
        with (self.app / 'Contents/Info.plist').open('wb') as handle:
            plistlib.dump(self.info, handle)

    def test_xml_escaping_versions_and_immutable_asset_url(self):
        archive = self.root / 'Example-v0.1.0.zip'
        archive.write_bytes(b'fictional-archive')
        output = self.root / 'appcast.xml'
        appcast.generate(self.app, 'owner/repo', '0.1.0', archive, base64.b64encode(bytes(64)).decode(), output)
        tree = ET.parse(output)
        self.assertEqual(tree.findtext('channel/title'), 'Example & Friends')
        enclosure = tree.find('channel/item/enclosure')
        self.assertEqual(enclosure.get('url'), 'https://github.com/owner/repo/releases/download/v0.1.0/Example-v0.1.0.zip')
        self.assertEqual(enclosure.get(f'{{{appcast.SPARKLE}}}version'), '7')
        self.assertEqual(int(enclosure.get('length')), archive.stat().st_size)

    def test_configuration_mismatch_fails_closed(self):
        for key, value in [('SURequireSignedFeed', False), ('SUVerifyUpdateBeforeExtraction', False),
                           ('SUPublicEDKey', 'invalid'), ('CFBundleVersion', '1.2'), ('LSMinimumSystemVersion', ''),
                           ('SUFeedURL', 'http://untrusted/feed')]:
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                self.write_info()
                with self.assertRaises(ValueError):
                    appcast.metadata(self.app, 'owner/repo', '0.1.0')
                self.info[key] = original
        self.write_info()
        with self.assertRaises(ValueError):
            appcast.metadata(self.app, 'owner/repo', '0.2.0')
        with self.assertRaises(ValueError):
            appcast.metadata(self.app, 'owner/repo?inject=true', '0.1.0')

if __name__ == '__main__':
    unittest.main()
