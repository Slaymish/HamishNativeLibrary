#!/usr/bin/env python3
"""Archive an app or CLI while preserving symlinks/permissions, then verify required contents."""
import argparse
from datetime import datetime
from pathlib import Path
import stat
import zipfile

def archive(source, destination, expected):
    source = Path(source).resolve()
    if not source.exists():
        raise ValueError('Archive source does not exist')
    paths = [source] + sorted(source.rglob('*')) if source.is_dir() else [source]
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in paths:
            if path.name.startswith('._'):
                continue
            relative = path.relative_to(source)
            name = source.name if relative == Path('.') else f'{source.name}/{relative}'
            directory = path.is_dir() and not path.is_symlink()
            info = zipfile.ZipInfo(name + ('/' if directory else ''))
            info.date_time = datetime.fromtimestamp(path.lstat().st_mtime).timetuple()[:6]
            info.create_system = 3
            info.external_attr = path.lstat().st_mode << 16
            if directory:
                info.external_attr |= 0x10
                zf.writestr(info, b'')
            elif path.is_symlink():
                zf.writestr(info, str(path.readlink()).encode())
            else:
                info.compress_type = zipfile.ZIP_DEFLATED
                zf.writestr(info, path.read_bytes())
    with zipfile.ZipFile(destination) as zf:
        wanted = f'{source.name}/{expected}' if source.is_dir() else source.name
        if wanted not in zf.namelist() or zf.testzip() is not None:
            raise ValueError('Archive is incomplete or corrupt')
        if source.suffix == '.app' and not any(name.startswith(f'{source.name}/Contents/MacOS/') for name in zf.namelist()):
            raise ValueError('App archive has no executable')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--expect', required=True)
    args = parser.parse_args()
    archive(args.source, args.archive, args.expect)
    print(f'{args.archive.name}: verified archive contents')
