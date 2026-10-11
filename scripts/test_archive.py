import importlib.util
import pathlib
import stat
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('make_archive', pathlib.Path(__file__).with_name('make-archive.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ArchiveTests(unittest.TestCase):
    def test_spaces_symlink_directories_and_executable_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            app = root / 'Fictional App.app'
            binary = app / 'Contents/MacOS/Fictional'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'fictional executable')
            binary.chmod(0o755)
            link = app / 'Current'
            link.symlink_to('Contents', target_is_directory=True)
            output = root / 'app.zip'
            module.archive(app, output, 'Contents/MacOS/Fictional')
            with zipfile.ZipFile(output) as zf:
                self.assertEqual(zf.read('Fictional App.app/Contents/MacOS/Fictional'), b'fictional executable')
                symlink = zf.getinfo('Fictional App.app/Current')
                self.assertTrue(stat.S_ISLNK(symlink.external_attr >> 16))
                self.assertEqual(zf.read(symlink), b'Contents')
                self.assertEqual(stat.S_IMODE(zf.getinfo('Fictional App.app/Contents/MacOS/Fictional').external_attr >> 16), 0o755)
