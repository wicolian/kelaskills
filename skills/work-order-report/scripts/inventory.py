#!/usr/bin/env python3
"""Static inventory of legacy signal across a source tree.

Repo-wide by construction: it walks every file under the scan root, rather than
whatever a reviewer or a browser happened to reach. That is what lets a report
say "this surface has signal and nobody looked at it", instead of leaving silence
to be read as clean.

What counts as legacy signal is yours to define. Supply it as JSON:

    {"<key>": {"regex":   "<python regex>",
               "means":   "<what one hit means, in one line>",
               "collect": true}}

"collect" is optional. When it is true, the first capture group of every hit is
counted into the "captures" table, which answers "which old thing leaks most".

See patterns.example.json beside this skill for the shape.
"""
import argparse, collections, json, os, re, sys


def die(msg, code=2):
    print(f'inventory: {msg}', file=sys.stderr)
    sys.exit(code)


def load_patterns(path):
    if not os.path.exists(path):
        die(f'no patterns file at {path}. Copy patterns.example.json and edit it.')
    try:
        raw = json.load(open(path, encoding='utf-8'))
    except OSError as e:
        die(f'cannot read {path}: {e}')
    except json.JSONDecodeError as e:
        die(f'{path} is not valid JSON: line {e.lineno} column {e.colno}: {e.msg}')
    if not isinstance(raw, dict) or not raw:
        die(f'{path} must be a non-empty object of key -> {{"regex":..., "means":...}}')
    pats = {}
    for key, spec in raw.items():
        if not isinstance(spec, dict) or 'regex' not in spec:
            die(f'pattern "{key}" needs a "regex" field')
        try:
            rx = re.compile(spec['regex'])
        except re.error as e:
            die(f'pattern "{key}" has a bad regex: {e}')
        pats[key] = (rx, spec.get('means', ''), bool(spec.get('collect')))
    return pats


def area(rel, depth, deepen):
    """Group a file into a surface. Depth is a flag because repos do not all
    nest the same way. A segment named in --deepen gets one extra level, which
    is how a flat "pages" or "modules" directory stops collapsing into one row."""
    p = rel.replace(os.sep, '/').split('/')
    if len(p) > depth and depth >= 1 and p[depth - 1] in deepen:
        return '/'.join(p[:depth + 1])
    return '/'.join(p[:depth]) if len(p) > depth else '/'.join(p)


def main():
    ap = argparse.ArgumentParser(
        description='Count legacy-signal pattern hits across a source tree and write JSON.')
    ap.add_argument('--root', required=True,
                    help='directory to walk. No default: a wrong guess scans nothing silently.')
    ap.add_argument('--patterns', required=True,
                    help='JSON pattern config. See patterns.example.json.')
    ap.add_argument('--out', default='inventory.json', help='output JSON path')
    ap.add_argument('--rel-to', default=None,
                    help='report paths relative to this directory (default: --root)')
    ap.add_argument('--depth', type=int, default=2,
                    help='path segments used to name a surface (default: 2)')
    ap.add_argument('--deepen', default='',
                    help='comma-separated segment names that get one extra level of depth')
    ap.add_argument('--ext', default='.ts,.tsx,.js,.jsx,.mjs,.css,.scss,.vue,.svelte,'
                                     '.py,.rb,.go,.java,.kt,.swift,.cs,.php,.html',
                    help='comma-separated file extensions to read')
    ap.add_argument('--exclude', default='node_modules,__tests__,.git,dist,build,out,'
                                         'vendor,__pycache__,.venv,coverage,.next',
                    help='comma-separated directory names to skip')
    a = ap.parse_args()

    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        die(f'scan root does not exist or is not a directory: {root}')
    rel_to = os.path.abspath(a.rel_to) if a.rel_to else root
    pats = load_patterns(a.patterns)
    exts = tuple(e.strip() for e in a.ext.split(',') if e.strip())
    skip = {d.strip() for d in a.exclude.split(',') if d.strip()}
    deepen = {d.strip() for d in a.deepen.split(',') if d.strip()}

    rows = []
    areas, caps, kinds = collections.Counter(), collections.Counter(), collections.Counter()
    files = seen = 0
    for r, dirs, fs in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip]
        for f in sorted(fs):
            seen += 1
            if not f.endswith(exts):
                continue
            files += 1
            p = os.path.join(r, f)
            rel = os.path.relpath(p, rel_to)
            try:
                lines = open(p, encoding='utf-8', errors='replace').read().splitlines()
            except OSError:
                continue
            g = area(rel, a.depth, deepen)
            for i, line in enumerate(lines, 1):
                for k, (rx, _means, collect) in pats.items():
                    for m in rx.findall(line):
                        what = m if isinstance(m, str) else (m[0] if m else '')
                        rows.append({'area': g, 'file': rel, 'line': i,
                                     'kind': k, 'what': what})
                        areas[g] += 1
                        kinds[k] += 1
                        if collect and what:
                            caps[what] += 1

    if files == 0:
        die(f'0 of {seen} files under {root} matched --ext {a.ext}. '
            f'Nothing was scanned, so this is NOT a clean result. '
            f'Fix --root or --ext and run again.')

    out = {'files': files, 'rows': rows,
           'areas': dict(areas.most_common()),
           'captures': dict(caps.most_common()),
           'kinds': dict(kinds.most_common()),
           'descriptions': {k: v[1] for k, v in pats.items()}}
    d = os.path.dirname(os.path.abspath(a.out))
    if d:
        os.makedirs(d, exist_ok=True)
    try:
        json.dump(out, open(a.out, 'w', encoding='utf-8'), indent=1)
    except OSError as e:
        die(f'cannot write {a.out}: {e}')

    print(f'{files} files scanned, {len(rows)} signals across {len(areas)} surfaces -> {a.out}')
    if not rows:
        print('  0 signals, and the scan DID read files: this tree is clean by these patterns.')
    for k, v in kinds.most_common():
        print(f'  {v:5} {k}')


if __name__ == '__main__':
    main()
