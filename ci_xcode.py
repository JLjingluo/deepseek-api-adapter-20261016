"""Discover installed stable Xcode versions; do not install or alter the host."""
import os
import pathlib
import plistlib


def installed_toolchains():
    candidates = []
    for app in pathlib.Path('/Applications').glob('Xcode*.app'):
        if 'beta' in app.name.lower():
            continue
        try:
            info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
            version = tuple(int(x) for x in info['CFBundleShortVersionString'].split('.'))
            candidates.append((version, app/'Contents/Developer'))
        except (OSError, ValueError, KeyError):
            continue
    return sorted(candidates, reverse=True)


if __name__ == '__main__':
    choices = [(version, path) for version, path in installed_toolchains() if version >= (26, 0)]
    if not choices:
        raise SystemExit('No installed stable Xcode 26 or newer')
    _, developer = choices[0]
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write('DEVELOPER_DIR='+str(developer)+'\n')
    print('Selected', developer)
