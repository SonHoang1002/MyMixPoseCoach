"""Freeze the actual Android working tree without modifying it (stdlib only)."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path


def freeze(source, output):
    source = source.resolve()
    def git(*args):
        return subprocess.check_output(['git', '-C', str(source), *args]).decode('utf-8').strip()
    names = subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z', '--cached', '--others', '--exclude-standard']).decode('utf-8').split('\0')
    selected = []
    for name in sorted(set(filter(None, names))):
        p = Path(name)
        if any(part in {'build', '.gradle', '.idea', 'node_modules'} for part in p.parts):
            continue
        if name.endswith(('local.properties', '.keystore', '.jks')):
            continue
        if '/src/' in name or p.suffix in {'.kt', '.kts', '.toml', '.md'} or p.name in {'gradle.properties', 'gradle-wrapper.properties'}:
            if (source / p).is_file():
                selected.append(name)
    output.mkdir(parents=True, exist_ok=True)
    manifest = {'branch': git('branch', '--show-current'), 'commit': git('rev-parse', 'HEAD'),
                'status': git('status', '--porcelain'), 'files': {}, 'excluded': ['build outputs', 'local.properties', 'keystores']}
    with zipfile.ZipFile(output / 'source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in selected:
            data = (source / name).read_bytes()
            manifest['files'][name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            archive.writestr(name, data)
    manifest['archive_sha256'] = hashlib.sha256((output / 'source.zip').read_bytes()).hexdigest()
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Frozen {len(selected)} files at {manifest["commit"]}; local changes included.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    freeze(args.source, args.output)
