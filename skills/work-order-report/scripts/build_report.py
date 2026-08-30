#!/usr/bin/env python3
"""Build one self-contained HTML work order out of per-lane markdown findings.

Re-runnable. The markdown is the source, the HTML is the artifact, and a
hand-edit to the artifact is lost on the next build.

The output carries what a tracker needs to be used rather than skimmed:
per-finding status, filters, light and dark, screenshots inlined as data URIs so
the file travels alone, real source pulled from the repo at build time, and
state seeded from the file so it is populated on first open.

Layout it expects under --findings:

    <findings>/reports/*.md      one markdown file per lane, leading _ ignored
    <findings>/shots/**/*.png    screenshots named on a `shot:` line
    <findings>/inventory.json    output of inventory.py, optional
"""
import argparse, base64, collections, datetime, glob, html as H, json, os, re, sys

# Fields read out of every finding block. The first ten are the documented field
# shape. The rest are optional and render only when a lane fills them in.
FIELDS = ('severity', 'visible', 'mechanism', 'where', 'current', 'target', 'fix',
          'donot', 'verify', 'blast', 'replacement', 'looks like', 'shot', 'themes')
SEVERITIES = ('blocker', 'major', 'minor', 'opportunity')
SEV_ORDER = {s: i for i, s in enumerate(SEVERITIES)}
CFG = {}


def die(msg, code=2):
    print(f'build_report: {msg}', file=sys.stderr)
    sys.exit(code)


def parse(path):
    """Read one lane report into finding dicts.

    Accept `##` through `####`. The reliable discriminator is a `severity:`
    field in the body, never the heading depth: keying off `###` alone once
    dropped a whole lane's report in a real run, and the result looked exactly
    like a lane that had found nothing.
    """
    lane = os.path.basename(path)[:-3]
    out = []
    txt = open(path, encoding='utf-8', errors='replace').read()
    for m in re.finditer(r'^#{2,4}\s+(.+?)\s*$([\s\S]*?)(?=^#{1,4}\s|\Z)', txt, re.M):
        title = m.group(1).strip()
        body = m.group(2)
        d = {'lane': lane, 'title': title}
        for f in FIELDS:
            r = re.search(rf'^\**{re.escape(f)}:\**\s*(.+)$', body, re.M | re.I)
            d[f.replace(' ', '_')] = r.group(1).strip() if r else ''
        if not d.get('severity'):
            continue
        sv = d['severity'].lower().lstrip('* ')
        for k in SEVERITIES:                      # fold `minor (see below)` to `minor`
            if sv.startswith(k):
                d['severity'] = k
                break
        else:
            d['severity'] = SEVERITIES[-2]
        out.append(d)
    return out


def shot_uris(field):
    """Every .png named on the `shot:` line, with the label in front of it.

    Take them all, not the first. A lane writes `a.png` dark, `b.png` light,
    closeup `c.png`, and the closeup and the comparison pair are usually the
    most useful frames. A parser that keeps only the first throws them away.
    """
    if not field:
        return []
    root, cap = CFG['findings'], CFG['max_image']
    out = []
    for m in re.finditer(r'([A-Za-z][\w \-]{0,24})?\s*`?((?:shots/)?[\w./-]+\.png)`?', field):
        label = (m.group(1) or '').strip(' -*')
        rel = m.group(2)
        cand = rel if rel.startswith('shots/') else 'shots/' + rel.lstrip('/')
        p = os.path.join(root, cand)
        if not os.path.exists(p):
            hits = glob.glob(os.path.join(root, 'shots', '*', os.path.basename(cand)))
            if not hits:
                continue
            p = hits[0]
        if os.path.getsize(p) > cap:             # one screenshot must not bloat the file
            continue
        out.append((label, 'data:image/png;base64,'
                    + base64.b64encode(open(p, 'rb').read()).decode()))
    return out


def code_at(where):
    """Pull the real source around every file:line named in `where:`.

    Read the repo at build time rather than asking a lane to paste an excerpt,
    so the code can never be stale or mistyped, and the offending line is shown
    as evidence rather than described. A `where:` that resolves against none of
    the --src-root candidates renders nothing, which is visible, and that is the
    pressure that keeps `where:` exact.
    """
    ctx, roots, hl = CFG['context'], CFG['src_roots'], CFG['highlight']
    # longest extension first, so `.tsx` is never truncated to `.ts`, and refuse
    # a trailing word character so `.ts` cannot swallow the head of `.tsx`
    exts = '|'.join(sorted((e.lstrip('.') for e in CFG['code_ext']), key=len, reverse=True))
    out = []
    for m in re.finditer(rf'([\w@./\-]+\.(?:{exts}))(?![\w])(?::(\d+))?', where or ''):
        rel, ln = m.group(1), m.group(2)
        path = None
        for r in roots:
            c = os.path.join(r, rel)
            if os.path.exists(c):
                path = c
                break
        if not path:
            continue
        try:
            lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
        except OSError:
            continue
        if ln:
            i = int(ln)
            a, b = max(0, i - 1 - ctx), min(len(lines), i + ctx)
            snippet = [(n + 1, lines[n], (n + 1) == i) for n in range(a, b)]
        elif hl:
            snippet = [(n + 1, l, True) for n, l in enumerate(lines) if hl.search(l)][:8]
        else:
            snippet = [(n + 1, l, False) for n, l in enumerate(lines[:ctx * 3])]
        if snippet:
            out.append((rel, ln, snippet))
    return out


def main():
    ap = argparse.ArgumentParser(description='Build a self-contained HTML work order.')
    ap.add_argument('--findings', required=True,
                    help='directory holding reports/, shots/ and inventory.json')
    ap.add_argument('--out', default=None, help='output HTML (default: <findings>/work-order.html)')
    ap.add_argument('--src-root', action='append', default=[], dest='src_roots',
                    help='repeatable. A `where:` path is resolved against each root in order.')
    ap.add_argument('--highlight', default=None,
                    help='regex marking which lines of a pulled file are the evidence, '
                         'used only when `where:` gives no line number. Default: no highlighting.')
    ap.add_argument('--title', default='Work order', help='page title and heading')
    ap.add_argument('--storage-key', default=None,
                    help='localStorage key. Version it. Default: <slug>::<today>')
    ap.add_argument('--context', type=int, default=4, help='lines of context around a hit')
    ap.add_argument('--code-ext', default='.ts,.tsx,.js,.jsx,.mjs,.css,.scss,.vue,.svelte,'
                                          '.py,.rb,.go,.java,.kt,.swift,.cs,.php,.html',
                    help='extensions recognised inside a `where:` field')
    ap.add_argument('--max-image', type=int, default=3_000_000,
                    help='skip any screenshot larger than this many bytes')
    a = ap.parse_args()

    root = os.path.abspath(a.findings)
    if not os.path.isdir(root):
        die(f'findings root does not exist: {root}')
    rdir = os.path.join(root, 'reports')
    if not os.path.isdir(rdir):
        die(f'no reports/ directory under {root}. Put one markdown file per lane in it.')
    hl = None
    if a.highlight:
        try:
            hl = re.compile(a.highlight)
        except re.error as e:
            die(f'--highlight is not a valid regex: {e}')
    slug = re.sub(r'[^a-z0-9]+', '-', a.title.lower()).strip('-') or 'work-order'
    CFG.update(findings=root, src_roots=[os.path.abspath(r) for r in a.src_roots],
               highlight=hl, context=a.context, max_image=a.max_image,
               code_ext=[e.strip() for e in a.code_ext.split(',') if e.strip()])
    for r in CFG['src_roots']:
        if not os.path.isdir(r):
            print(f'build_report: warning: --src-root {r} does not exist', file=sys.stderr)
    OUT = a.out or os.path.join(root, 'work-order.html')
    KEY = a.storage_key or f'{slug}::{datetime.date.today().isoformat()}'

    paths = [p for p in sorted(glob.glob(os.path.join(rdir, '*.md')))
             if not os.path.basename(p).startswith('_')]
    if not paths:
        die(f'no lane reports matched {rdir}/*.md')
    items = []
    for p in paths:
        items += parse(p)
    if not items:
        die(f'{len(paths)} lane reports read, 0 findings parsed. Every finding needs a '
            f'`severity:` field under a ## to #### heading. This is a parse failure, '
            f'not a clean audit.')

    items.sort(key=lambda d: (SEV_ORDER.get(d['severity'], 9), d['lane']))
    counts = collections.Counter(d['severity'] for d in items)
    vis = collections.Counter('visible' if d.get('visible', '').lower().startswith('y')
                              else 'structural' for d in items)
    lanes = collections.Counter(d['lane'] for d in items)

    cards = []
    for i, d in enumerate(items):
        uris = shot_uris(d.get('shot', ''))
        _blocks = code_at(d.get('where', ''))
        code_html = ''
        if _blocks:
            parts = []
            for rel, ln, snip in _blocks[:2]:
                rows = ''.join(
                    f'<tr class="{"hl" if hit else ""}"><td class="ln">{n}</td>'
                    f'<td>{H.escape(txt)}</td></tr>' for n, txt, hit in snip)
                parts.append(f'<div class="src"><div class="srchead"><code>{H.escape(rel)}'
                             + (f':{ln}' if ln else '') + '</code></div><table>' + rows
                             + '</table></div>')
            code_html = ('<details class="code" open><summary>the code</summary>'
                         + ''.join(parts) + '</details>')
        key = f"{d['lane']}:{i}"
        img = ('<div class="shots">' + ''.join(
            f'<figure><img loading="lazy" src="{u}" alt="{H.escape(d["title"])[:70]}">'
            + (f'<figcaption>{H.escape(lbl)}</figcaption>' if lbl else '')
            + '</figure>' for lbl, u in uris) + '</div>') if uris else ''
        seen = 'visible' if d.get('visible', '').lower().startswith('y') else 'structural'

        cards.append(f'''<article class="card" data-key="{key}" data-sev="{H.escape(d['severity'])}"
 data-vis="{seen}" data-lane="{H.escape(d['lane'])}"
 data-text="{H.escape((d['title'] + ' ' + d.get('where', '') + ' ' + d.get('looks_like', '')).lower())}" data-trk="open">
<header><span class="sev s-{H.escape(d['severity'])}">{H.escape(d['severity'])}</span>
<span class="lane">{H.escape(d['lane'])}</span>
<span class="vis">{seen}</span>
<span class="themes">{H.escape(d.get('themes', ''))}</span>
{f'<span class="mech">{H.escape(d.get("mechanism", ""))}</span>' if d.get('mechanism') and d.get('mechanism').lower() != 'local' else ''}
<h3>{H.escape(d['title'])}</h3></header>
{img}
<dl>
<dt>where</dt><dd><code>{H.escape(d.get('where', ''))}</code></dd>
{f"<dt>current</dt><dd>{H.escape(d.get('current', ''))}</dd>" if d.get('current') else ""}
{f"<dt>target</dt><dd>{H.escape(d.get('target', ''))}</dd>" if d.get('target') else ""}
{f"<dt>fix</dt><dd>{H.escape(d.get('fix', ''))}</dd>" if d.get('fix') else ""}
{f"<dt class=no>do NOT</dt><dd class=no>{H.escape(d.get('donot', ''))}</dd>" if d.get('donot') else ""}
{f"<dt>verify</dt><dd>{H.escape(d.get('verify', ''))}</dd>" if d.get('verify') else ""}
{f"<dt class=blast>blast</dt><dd class=blast>{H.escape(d.get('blast', ''))}</dd>" if d.get('blast') else ""}
{f"<dt>replacement</dt><dd>{H.escape(d.get('replacement', ''))}</dd>" if d.get('replacement') else ""}
{f"<dt>looks like</dt><dd>{H.escape(d.get('looks_like', ''))}</dd>" if d.get('looks_like') else ""}
</dl>
{code_html}
<details class="task"><summary>copy as a task</summary><pre>{H.escape(
 "FIX: " + d['title'] + chr(10) +
 "file:    " + d.get('where', '') + chr(10) +
 "current: " + d.get('current', '') + chr(10) +
 "target:  " + d.get('target', '') + chr(10) +
 "do:      " + d.get('fix', '') + chr(10) +
 "do NOT:  " + d.get('donot', '') + chr(10) +
 "verify:  " + d.get('verify', '') + chr(10) +
 "affects: " + (d.get('blast') or 'this one only'))}</pre></details>
<footer><div class="trk" role="group">
<button data-s="open">Open</button><button data-s="doing">Fixing</button>
<button data-s="fixed">Fixed</button><button data-s="wont">Won't fix</button></div></footer>
</article>''')

    # Seed objects or strings to match what the paint code reads. This reads
    # state[k] directly, so seed strings.
    seed = json.dumps({f"{d['lane']}:{i}": "open" for i, d in enumerate(items)})

    # ---- static inventory section --------------------------------------------
    # The findings above are what agents LOOKED AT. This is what EXISTS, from
    # walking the whole tree. Reported separately and honestly: a surface with
    # inventory rows but no finding was not audited, and the report has to say so
    # rather than let silence read as clean.
    inv = {}
    inv_path = os.path.join(root, 'inventory.json')
    try:
        inv = json.load(open(inv_path, encoding='utf-8'))
    except Exception:
        print(f'build_report: warning: no usable {inv_path}, '
              f'the report will make no coverage claim', file=sys.stderr)
    inv_rows = inv.get('rows', [])
    by_area = collections.Counter(r['area'] for r in inv_rows)
    by_kind = collections.Counter(r['kind'] for r in inv_rows)
    by_what = collections.Counter(r['what'] for r in inv_rows if r.get('what'))

    def audited(surface):
        needle = surface.split('/')[-1].lower()
        return any(needle in (d.get('where', '') + d['title']).lower() for d in items)

    INV = ''
    if inv_rows:
        h = [f'<h2 id="inv">Static inventory: what exists, from all {inv.get("files", 0)} '
             f'files scanned</h2>',
             '<p class="sub">The findings above are what agents <b>looked at</b>. This is what '
             '<b>exists</b>. A surface with signal but no finding was not reached, and that is '
             'stated here rather than hidden.</p>',
             '<table class="inv"><thead><tr><th>surface</th><th>signals</th>'
             '<th>audited?</th></tr></thead><tbody>']
        for s, n in by_area.most_common():
            ok = 'yes' if audited(s) else '<b class="gap">not reached</b>'
            h.append(f'<tr><td><code>{H.escape(s)}</code></td><td>{n}</td><td>{ok}</td></tr>')
        h.append('</tbody></table>')
        h.append('<h3>By kind</h3><table class="inv"><tbody>' + ''.join(
            f'<tr><td><code>{H.escape(k)}</code></td><td>{v}</td>'
            f'<td>{H.escape(inv.get("descriptions", {}).get(k, ""))}</td></tr>'
            for k, v in by_kind.most_common()) + '</tbody></table>')
        if by_what:
            h.append('<h3>Most-leaked</h3><table class="inv"><tbody>' + ''.join(
                f'<tr><td><code>{H.escape(c)}</code></td><td>{v} hits</td></tr>'
                for c, v in by_what.most_common(20)) + '</tbody></table>')
        INV = ''.join(h)

    html = f'''<title>{H.escape(a.title)}</title>
<style>
:root{{--bg:#fafafa;--panel:#fff;--ink:#111114;--dim:#6b6b76;--line:#e6e6e3;--accent:#3b5bdb;
--blocker:#c92a2a;--major:#e8590c;--minor:#5c7cfa;--opportunity:#868e96;--ok:#2b8a3e;
--mono:ui-monospace,SFMono-Regular,Menlo,monospace}}
:root[data-theme=dark]{{--bg:#0f0f12;--panel:#17171b;--ink:#ececef;--dim:#9a9aa5;--line:#2a2a31;
--blocker:#ff6b6b;--major:#ffa94d;--minor:#91a7ff;--opportunity:#adb5bd;--ok:#69db7c}}
@media(prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#0f0f12;--panel:#17171b;--ink:#ececef;--dim:#9a9aa5;--line:#2a2a31;--blocker:#ff6b6b;--major:#ffa94d;--minor:#91a7ff;--opportunity:#adb5bd;--ok:#69db7c}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 ui-sans-serif,-apple-system,Segoe UI,sans-serif}}
.wrap{{max-width:1180px;margin:0 auto;padding:28px 22px 90px}}
h1{{font-size:25px;margin:0 0 4px;letter-spacing:-.02em}}
.sub{{color:var(--dim);font-size:13.5px;margin-bottom:22px;max-width:74ch}}
.stats{{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:18px}}
.stat{{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:9px 14px;min-width:86px}}
.stat b{{display:block;font:640 21px/1.15 var(--mono);letter-spacing:-.02em}}
.stat span{{font-size:10.5px;color:var(--dim);text-transform:uppercase;letter-spacing:.06em}}
.bar{{display:flex;gap:7px;flex-wrap:wrap;align-items:center;position:sticky;top:0;background:var(--bg);
padding:11px 0;z-index:5;border-bottom:1px solid var(--line);margin-bottom:16px}}
.bar button,.bar select,.bar input{{background:var(--panel);color:var(--ink);border:1px solid var(--line);
border-radius:7px;padding:5px 10px;font:inherit;font-size:12.5px;cursor:pointer}}
.bar button[aria-pressed=true]{{background:var(--accent);border-color:var(--accent);color:#fff}}
.bar .count{{margin-left:auto;color:var(--dim);font-size:12.5px}}
.card{{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:15px;margin-bottom:13px}}
.card[data-trk=fixed]{{opacity:.5}}
.card header{{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:9px}}
.card h3{{margin:5px 0 0;font-size:15.5px;flex-basis:100%;letter-spacing:-.01em}}
.sev{{font:600 10.5px var(--mono);text-transform:uppercase;letter-spacing:.05em;padding:2px 7px;border-radius:999px;color:#fff}}
.s-blocker{{background:var(--blocker)}}.s-major{{background:var(--major)}}
.s-minor{{background:var(--minor)}}.s-opportunity{{background:var(--opportunity)}}
.mech{{font:600 10.5px var(--mono);color:#fff;background:var(--accent);padding:2px 7px;border-radius:999px}}
dt.no,dd.no{{color:var(--blocker)}}
dt.blast,dd.blast{{color:var(--major)}}
details.code{{margin-top:11px}}
details.code summary{{cursor:pointer;font-size:11.5px;color:var(--dim);text-transform:uppercase;letter-spacing:.05em}}
.src{{margin:8px 0 0;border:1px solid var(--line);border-radius:8px;overflow:hidden}}
.srchead{{background:var(--bg);border-bottom:1px solid var(--line);padding:5px 9px;font-size:11px;color:var(--dim)}}
.src table{{width:100%;border-collapse:collapse;font:12px/1.6 var(--mono)}}
.src td{{padding:0 9px;white-space:pre;overflow-x:auto}}
.src td.ln{{width:44px;text-align:right;color:var(--dim);user-select:none;border-right:1px solid var(--line);padding-right:8px}}
.src tr.hl{{background:color-mix(in srgb,var(--major) 16%,transparent)}}
details.task{{margin-top:10px}}
details.task summary{{cursor:pointer;font-size:11.5px;color:var(--dim);text-transform:uppercase;letter-spacing:.05em}}
details.task pre{{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:11px;
font:12px/1.5 var(--mono);white-space:pre-wrap;margin:7px 0 0}}
.lane,.vis,.themes{{font:600 10.5px var(--mono);color:var(--dim);border:1px solid var(--line);padding:2px 7px;border-radius:999px}}
.shots{{display:grid;gap:9px;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));margin:11px 0}}
.shots figure{{margin:0;border:1px solid var(--line);border-radius:9px;overflow:hidden;background:var(--bg)}}
.shots img{{display:block;max-width:100%;height:auto;cursor:zoom-in}}
.shots figcaption{{font-size:11px;color:var(--dim);padding:5px 8px;border-top:1px solid var(--line)}}
.shots img.zoom{{cursor:zoom-out;position:fixed;inset:12px;z-index:99;max-width:calc(100vw - 24px);
max-height:calc(100vh - 24px);object-fit:contain;background:var(--panel);box-shadow:0 8px 60px rgba(0,0,0,.55)}}
dl{{display:grid;grid-template-columns:92px 1fr;gap:5px 12px;margin:9px 0 0;font-size:13.5px}}
dt{{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.05em;padding-top:2px}}
dd{{margin:0}}
code{{font-family:var(--mono);font-size:.88em;background:color-mix(in srgb,var(--ink) 8%,transparent);padding:1px 5px;border-radius:4px;word-break:break-all}}
footer{{margin-top:11px;padding-top:10px;border-top:1px solid var(--line)}}
.trk{{display:flex;gap:5px}}
.trk button{{background:var(--bg);color:var(--dim);border:1px solid var(--line);border-radius:7px;
padding:3px 9px;font:inherit;font-size:11.5px;cursor:pointer}}
.trk button[aria-pressed=true]{{background:var(--ok);border-color:var(--ok);color:#fff}}
table.inv{{border-collapse:collapse;width:100%;font-size:13px;margin:10px 0 20px}}
table.inv td,table.inv th{{border-bottom:1px solid var(--line);padding:6px 9px;text-align:left}}
table.inv th{{color:var(--dim);font-size:10.5px;text-transform:uppercase;letter-spacing:.05em}}
.gap{{color:var(--blocker)}}
h2{{font-size:16px;margin:30px 0 6px;letter-spacing:-.01em}}
h3{{font-size:13px;margin:22px 0 4px;color:var(--dim);text-transform:uppercase;letter-spacing:.06em}}
</style>
<div class="wrap">
<h1>{H.escape(a.title)}</h1>
<p class="sub">Every finding below is a work order: where it is, what it should be, what not to do
instead, and how to know it worked. <b>Visible</b> means it renders and a user can see it, which
is the list to act on first. <b>Structural</b> means the old code is wired in but paints nothing of
its own, so it is debt rather than a defect. Any vocabulary that is deliberately not legacy is
excluded by the pattern config, not by hand, so it never reaches this page. Status is kept in this
browser.</p>
<div class="stats">
<div class="stat"><b>{len(items)}</b><span>findings</span></div>
<div class="stat"><b style="color:var(--blocker)">{counts.get('blocker', 0)}</b><span>blocker</span></div>
<div class="stat"><b style="color:var(--major)">{counts.get('major', 0)}</b><span>major</span></div>
<div class="stat"><b style="color:var(--minor)">{counts.get('minor', 0)}</b><span>minor</span></div>
<div class="stat"><b>{counts.get('opportunity', 0)}</b><span>opportunity</span></div>
<div class="stat"><b>{vis.get('visible', 0)}</b><span>visible</span></div>
<div class="stat"><b>{vis.get('structural', 0)}</b><span>structural</span></div>
</div>
<div class="bar">
<button data-f="sev" data-v="blocker">blocker</button>
<button data-f="sev" data-v="major">major</button>
<button data-f="sev" data-v="minor">minor</button>
<button data-f="sev" data-v="opportunity">opportunity</button>
<button data-f="vis" data-v="visible">visible only</button>
{''.join(f'<button data-f="lane" data-v="{H.escape(l)}">{H.escape(l)}</button>' for l in sorted(lanes))}
<button data-f="trk" data-v="open">not fixed</button>
<input id="q" placeholder="search" size="18">
<span class="count" id="cnt"></span>
</div>
<div id="list">
{''.join(cards)}
</div>
<hr style="margin:38px 0;border:0;border-top:1px solid var(--line)">
{INV}
</div>
<script>
const KEY={json.dumps(KEY)};
const SEED={seed};
let state={{}}; try{{state=JSON.parse(localStorage.getItem(KEY)||'null')||SEED}}catch{{state=SEED}}
state=Object.assign({{}},SEED,state);
const save=()=>{{try{{localStorage.setItem(KEY,JSON.stringify(state))}}catch{{}}}};
const $$=s=>[...document.querySelectorAll(s)];
$$('.card').forEach(c=>{{
  const k=c.dataset.key;
  const paint=()=>{{const v=state[k]||'open';c.dataset.trk=v;
    c.querySelectorAll('.trk button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.s===v)));}};
  c.querySelectorAll('.trk button').forEach(b=>b.onclick=()=>{{
    state[k]=state[k]===b.dataset.s?'open':b.dataset.s;save();paint();apply();}});
  paint();
}});
const active={{sev:new Set(),vis:new Set(),lane:new Set(),trk:new Set()}};
$$('.bar button[data-f]').forEach(b=>b.onclick=()=>{{
  const s=active[b.dataset.f];s.has(b.dataset.v)?s.delete(b.dataset.v):s.add(b.dataset.v);
  b.setAttribute('aria-pressed',String(s.has(b.dataset.v)));apply();}});
document.getElementById('q').oninput=apply;
function apply(){{
  const q=document.getElementById('q').value.toLowerCase();let n=0;
  $$('.card').forEach(c=>{{
    const ok=(!active.sev.size||active.sev.has(c.dataset.sev))
      &&(!active.vis.size||active.vis.has(c.dataset.vis))
      &&(!active.lane.size||active.lane.has(c.dataset.lane))
      &&(!active.trk.size||active.trk.has(state[c.dataset.key]||'open'))
      &&(!q||c.dataset.text.includes(q));
    c.style.display=ok?'':'none';if(ok)n++;}});
  document.getElementById('cnt').textContent=n+' shown';
}}
apply();
// click any screenshot to blow it up: a 260px thumbnail cannot show a 4px radius difference
document.addEventListener('click',e=>{{if(e.target.tagName==='IMG'&&e.target.closest('.shots'))
  e.target.classList.toggle('zoom');}});
</script>'''

    d = os.path.dirname(os.path.abspath(OUT))
    if d:
        os.makedirs(d, exist_ok=True)
    open(OUT, 'w', encoding='utf-8').write(html)
    print(f'{len(items)} findings -> {OUT}  ({os.path.getsize(OUT) // 1024} KB)')
    print(' severity:', dict(counts), '|', dict(vis), '| lanes:', dict(lanes))
    print(' storage key:', KEY)


if __name__ == '__main__':
    main()
