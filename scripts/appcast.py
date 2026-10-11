#!/usr/bin/env python3
"""Write one full update. Signing happens AFTER XML generation; never modify a signed feed."""
import argparse
import base64
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)

def metadata(app, repo, version):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Expected GitHub OWNER/REPO')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Expected a stable semantic version')
    with (pathlib.Path(app) / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    if info.get('CFBundleShortVersionString') != version:
        raise ValueError('App version does not match the release version')
    build = str(info.get('CFBundleVersion', ''))
    if not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Build number must be a positive increasing integer')
    public = info.get('SUPublicEDKey', '')
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError('App needs a valid SUPublicEDKey')
    if info.get('SUFeedURL') != f'https://github.com/{repo}/releases/latest/download/appcast.xml':
        raise ValueError('App feed URL does not match this repository')
    if info.get('SURequireSignedFeed') is not True or info.get('SUVerifyUpdateBeforeExtraction') is not True:
        raise ValueError('Require signed feeds and pre-extraction verification in the app')
    minimum = info.get('LSMinimumSystemVersion', '')
    if not re.fullmatch(r'\d+\.\d+(\.\d+)?', minimum):
        raise ValueError('App needs LSMinimumSystemVersion')
    return info, build, public, minimum

def generate(app, repo, version, archive, signature, output):
    info, build, _, minimum = metadata(app, repo, version)
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid Ed25519 signature')
    archive = pathlib.Path(archive)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = info.get('CFBundleName', pathlib.Path(app).stem)
    ET.SubElement(channel, 'link').text = f'https://github.com/{repo}'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Version {version}'
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = minimum
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{repo}/releases/download/v{version}/{archive.name}',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}version': build, f'{{{SPARKLE}}}shortVersionString': version,
        f'{{{SPARKLE}}}edSignature': signature,
    })
    ET.indent(rss)
    ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--archive')
    parser.add_argument('--signature')
    parser.add_argument('--output')
    args = parser.parse_args()
    if args.output:
        generate(args.app, args.repo, args.version, args.archive, args.signature, args.output)
    else:
        _, build, public, _ = metadata(args.app, args.repo, args.version)
        print(build)
        print(public)
