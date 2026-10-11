"""Integration test with an ad-hoc dummy app and a disposable key; never accesses login Keychain."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
BIN = ROOT / 'Examples/MacUpdater/.build/artifacts/sparkle/Sparkle/bin'

@unittest.skipUnless((BIN / 'sign_update').exists(), 'Build Examples/MacUpdater first for release integration checks')
class ReleaseIntegrationTests(unittest.TestCase):
    def test_signed_package_and_wrong_key_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = pathlib.Path(directory)
            generator = temporary / 'key.swift'
            generator.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try key.rawRepresentation.base64EncodedString().write(to: root.appendingPathComponent("seed"), atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(to: root.appendingPathComponent("public"), atomically: true, encoding: .utf8)
''')
            env = dict(os.environ)
            subprocess.run(['swift', str(generator), str(temporary)], check=True, capture_output=True)
            (temporary / 'seed').chmod(0o600)
            original_public = (temporary / 'public').read_text()
            old_seed = temporary / 'old-seed'
            old_seed.write_bytes((temporary / 'seed').read_bytes())
            old_seed.chmod(0o600)
            app = temporary / 'Fictional.app'
            executable = app / 'Contents/MacOS'
            executable.mkdir(parents=True)
            shutil.copy('/usr/bin/true', executable / 'Fictional')
            info = {
                'CFBundleIdentifier': 'nz.hamish.test-release', 'CFBundleName': 'Fictional',
                'CFBundlePackageType': 'APPL', 'CFBundleExecutable': 'Fictional',
                'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.1.0', 'LSMinimumSystemVersion': '13.0',
                'SUPublicEDKey': (temporary / 'public').read_text(),
                'SUFeedURL': 'https://github.com/fictional/demo/releases/latest/download/appcast.xml',
                'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
            }
            def save_sign():
                with (app / 'Contents/Info.plist').open('wb') as handle:
                    plistlib.dump(info, handle)
                subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
            save_sign()
            env['SPARKLE_BIN'] = str(BIN)
            env['SPARKLE_KEY_FILE'] = str(temporary / 'seed')
            output = temporary / 'dist'
            command = [str(ROOT / 'scripts/package-macos.sh'), str(app), 'fictional/demo', '0.1.0', str(output), 'self-signed']
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({p.name for p in output.iterdir()}, {'Fictional-v0.1.0.zip', 'appcast.xml', 'SHA256SUMS'})
            self.assertIn('sparkle-signatures:', (output / 'appcast.xml').read_text())
            self.assertIsNotNone(ET.parse(output / 'appcast.xml').find('channel/item/enclosure'))
            subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd=output, check=True, capture_output=True)
            # A different embedded key must fail without leaving a published-looking output directory.
            subprocess.run(['swift', str(generator), str(temporary)], check=True, capture_output=True)
            info['SUPublicEDKey'] = (temporary / 'public').read_text()
            save_sign()
            env['SPARKLE_KEY_FILE'] = str(old_seed)
            command[4] = str(temporary / 'wrong-key-dist')
            failed_package = subprocess.run(command, env=env, capture_output=True)
            self.assertNotEqual(failed_package.returncode, 0)
            self.assertFalse((temporary / 'wrong-key-dist').exists())
            # Extracting its signature and asking the verifier to use the new public key must reject it.
            signature = ET.parse(output / 'appcast.xml').find('channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
            verification = subprocess.run(['swift', str(ROOT / 'scripts/verify-update.swift'),
                str(output / 'Fictional-v0.1.0.zip'), info['SUPublicEDKey'], signature], capture_output=True)
            self.assertNotEqual(verification.returncode, 0)
            # Tampering with the archive fails verification against the original signature/public key too.
            archive = output / 'Fictional-v0.1.0.zip'
            archive.write_bytes(archive.read_bytes() + b'tampered')
            tampered = subprocess.run(['swift', str(ROOT / 'scripts/verify-update.swift'), str(archive),
                original_public, signature], capture_output=True)
            self.assertNotEqual(tampered.returncode, 0)
            feed = output / 'appcast.xml'
            feed.write_text(feed.read_text().replace('Version 0.1.0', 'Version 9.9.9'))
            tampered_feed = subprocess.run([str(BIN / 'sign_update'), '--ed-key-file', str(old_seed), '--verify', str(feed)], capture_output=True)
            self.assertNotEqual(tampered_feed.returncode, 0)

if __name__ == '__main__':
    unittest.main()
