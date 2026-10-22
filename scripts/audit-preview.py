#!/usr/bin/env python3
"""Render without showing a window, and audit the exact child's desktop footprint."""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import time
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
aerospace = shutil.which('aerospace')


def query(*args):
    return json.loads(subprocess.check_output([aerospace, *args, '--json'], text=True, timeout=5))


def desktop():
    return {
        'visible': query('list-workspaces', '--monitor', 'all', '--visible'),
        'focused': query('list-workspaces', '--focused'),
        'windows': query('list-windows', '--all', '--format', '%{window-id} %{app-pid} %{workspace}'),
    }


def audit(binary, output_dir, live=False, diagnose=False):
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('live-layout.png' if live else 'preview.png')
    before = desktop()
    args = [str(binary), '--config', str(output_dir / 'settings.json'),
            '--render-live-layout' if live else '--render-preview', str(output), '--audit-wait']
    if diagnose:
        args = [str(binary), '--config', str(output_dir / 'settings.json'),
                '--diagnose', '--check-previews', '--audit-wait']
    child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    report = {'pid': child.pid, 'executable': str(binary), 'arguments': args[1:], 'before': before, 'samples': []}
    try:
        deadline = time.monotonic() + 20
        while child.poll() is None and time.monotonic() < deadline:
            windows = query('list-windows', '--monitor', 'all', '--pid', str(child.pid))
            report['samples'].append({'running': child.poll() is None, 'windows': windows})
            time.sleep(0.4)
        stdout, stderr = child.communicate(timeout=5)
        report.update(returncode=child.returncode, stdout=stdout, stderr=stderr, after=desktop())
        report['visible_unchanged'] = before['visible'] == report['after']['visible']
        report['focused_unchanged'] = before['focused'] == report['after']['focused']
        report['window_set_unchanged'] = before['windows'] == report['after']['windows']
        report['child_exited'] = child.poll() is not None
        report['no_test_windows'] = all(not sample['windows'] for sample in report['samples'])
        report_path = output_dir / ('diagnostic-audit.json' if diagnose else 'live-layout-audit.json' if live else 'preview-audit.json')
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(json.dumps({key: report[key] for key in ['pid', 'returncode', 'child_exited', 'no_test_windows', 'visible_unchanged', 'focused_unchanged', 'window_set_unchanged']}, indent=2))
        print(stdout)
        if stderr:
            print(stderr, file=sys.stderr)
        if child.returncode or not report['no_test_windows']:
            sys.exit(1)
    finally:
        if child.poll() is None:
            child.terminate()
            child.wait(timeout=5)


def main():
    if aerospace is None:
        sys.exit('AeroSpace CLI not found. Add aerospace to PATH before running the desktop audit.')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', nargs='?', type=pathlib.Path, default=root / '.build/debug/AeroTab')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--live', action='store_true', help='Render real window metadata without capturing contents')
    mode.add_argument('--diagnose', action='store_true', help='Check the connection and existing preview permission')
    parser.add_argument('--output-dir', type=pathlib.Path,
                        help='Explicit inspection directory; caller must remove it after visual review. Defaults to an automatically cleaned temporary directory.')
    args = parser.parse_args()
    binary = args.binary.resolve()
    if args.output_dir:
        audit(binary, args.output_dir.resolve(), args.live, args.diagnose)
    else:
        with tempfile.TemporaryDirectory(prefix='aerotab-qa-') as directory:
            audit(binary, pathlib.Path(directory), args.live, args.diagnose)
        print('Temporary preview images and audit files removed.')


if __name__ == '__main__':
    main()
