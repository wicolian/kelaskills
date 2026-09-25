#!/usr/bin/env python3
"""Generate the v1-in-v2 audit report from the lane reports. Re-runnable.

Same shape as the three audit trackers Koushik already reads: per-finding status
control, filters, light/dark, and state seeded from the file so it is not empty
on first open. Screenshots are inlined as data URIs so the file travels alone.
"""
import re,glob,os,json,base64,collections,html as H
ROOT='/Users/kelashik/codes/db_git/v2/.v1audit'
OUT=f'{ROOT}/v1-in-v2-report.html'

FIELDS=('severity','visible','mechanism','where','current','target','fix','donot','verify','blast','v2 has','looks like','shot','themes')
def parse(path):
    lane=os.path.basename(path)[:-3]
    out=[]
    txt=open(path,encoding='utf-8',errors='replace').read()
    # Accept ## or ### — lane A2 used ## for its MECHANISM blocks, which is the
    # better structure. The reliable discriminator is a `severity:` field in the
    # body, not the heading depth, so key off that and never lose a whole lane
    # to a formatting choice again.
    for m in re.finditer(r'^#{2,4}\s+(.+?)\s*$([\s\S]*?)(?=^#{1,4}\s|\Z)', txt, re.M):
        title=m.group(1).strip(); body=m.group(2)
        d={'lane':lane,'title':title}
        for f in FIELDS:
            r=re.search(rf'^{re.escape(f)}:\s*(.+)$', body, re.M|re.I)
            d[f.replace(' ','_')]=r.group(1).strip() if r else ''
        if not d.get('severity'): continue
        sv=d['severity'].lower()
        for k in ('glaring','noticeable','subtle','opportunity'):
            if sv.startswith(k): d['severity']=k; break
        else: d['severity']='subtle'
        out.append(d)
    return out

items=[]
for p in sorted(glob.glob(f'{ROOT}/reports/*.md')):
    if os.path.basename(p).startswith('_'): continue
    items+=parse(p)

def shot_uris(field):
    """Every .png referenced on the shot: line, with the label that precedes it."""
    if not field: return []
    out=[]
    for m in re.finditer(r'([A-Za-z][\w \-]{0,24})?\s*`?((?:shots/)?[\w./-]+\.png)`?', field):
        label=(m.group(1) or '').strip(' -·')
        rel=m.group(2)
        cand=rel if rel.startswith('shots/') else 'shots/'+rel.lstrip('/')
        p=os.path.join(ROOT, cand)
        if not os.path.exists(p):
            hits=[q for q in glob.glob(os.path.join(ROOT,'shots','*',os.path.basename(cand)))]
            if not hits: continue
            p=hits[0]
        if os.path.getsize(p)>3_000_000: continue
        out.append((label, 'data:image/png;base64,'+base64.b64encode(open(p,'rb').read()).decode()))
    return out

SRC_ROOTS=['/Users/kelashik/codes/db_git/v2/frontend/packages/@databrainhq/frontend/src',
           '/Users/kelashik/codes/db_git/v2/frontend/packages/@databrainhq/frontend',
           '/Users/kelashik/codes/db_git/v2/frontend/packages',
           '/Users/kelashik/codes/db_git/v2/frontend']

def code_at(where, ctx=4):
    """Pull the real source around every file:line in `where:`.

    Read from the repo at build time rather than asking a lane to paste it, so the
    excerpt can never be stale or mistyped, and the v1 import is shown as evidence
    rather than described."""
    out=[]
    for m in re.finditer(r'([\w@./\-]+\.(?:tsx?|css))(?::(\d+))?', where or ''):
        rel,ln=m.group(1),m.group(2)
        path=None
        for r in SRC_ROOTS:
            c=os.path.join(r,rel)
            if os.path.exists(c): path=c; break
        if not path: continue
        try: lines=open(path,encoding='utf-8',errors='replace').read().splitlines()
        except Exception: continue
        if ln:
            i=int(ln); a=max(0,i-1-ctx); b=min(len(lines),i+ctx)
            snippet=[(n+1, lines[n], (n+1)==i) for n in range(a,b)]
        else:
            # no line given: show the v1 imports in the file, which is the evidence
            snippet=[(n+1,l,True) for n,l in enumerate(lines)
                     if re.search(r"components/legacy/|from 'components/|from 'pages/|@plugin/components", l)][:8]
        if snippet: out.append((rel, ln, snippet))
    return out

SEV={'glaring':0,'noticeable':1,'subtle':2}
items.sort(key=lambda d:(SEV.get(d['severity'].lower(),3), d['lane']))
counts=collections.Counter(d['severity'].lower() for d in items)
vis=collections.Counter('visible' if d.get('visible','').lower().startswith('y') else 'structural' for d in items)
lanes=collections.Counter(d['lane'] for d in items)

cards=[]
for i,d in enumerate(items):
    uris=shot_uris(d.get('shot',''))
    _blocks=code_at(d.get('where',''))
    code_html=''
    if _blocks:
        parts=[]
        for rel,ln,snip in _blocks[:2]:
            rows=''.join(
              f'<tr class="{"hl" if hit else ""}"><td class="ln">{n}</td><td>{H.escape(txt)}</td></tr>'
              for n,txt,hit in snip)
            parts.append(f'<div class="src"><div class="srchead"><code>{H.escape(rel)}'
                         + (f':{ln}' if ln else '') + '</code></div><table>'+rows+'</table></div>')
        code_html='<details class="code" open><summary>the code</summary>'+''.join(parts)+'</details>' 
    key=f"{d['lane']}:{i}"
    img=('<div class="shots">'+''.join(
        f'<figure><img loading="lazy" src="{u}" alt="{H.escape(d["title"])[:70]}">'
        + (f'<figcaption>{H.escape(lbl)}</figcaption>' if lbl else '')
        + '</figure>' for lbl,u in uris)+'</div>') if uris else ''

    cards.append(f'''<article class="card" data-key="{key}" data-sev="{H.escape(d['severity'].lower())}"
 data-vis="{'visible' if d.get('visible','').lower().startswith('y') else 'structural'}" data-lane="{d['lane']}"
 data-text="{H.escape((d['title']+' '+d.get('where','')+' '+d.get('looks_like','')).lower())}" data-trk="open">
<header><span class="sev s-{H.escape(d['severity'].lower())}">{H.escape(d['severity'])}</span>
<span class="lane">{d['lane']}</span>
<span class="vis">{'visible' if d.get('visible','').lower().startswith('y') else 'structural'}</span>
<span class="themes">{H.escape(d.get('themes',''))}</span>
{f'<span class="mech">{H.escape(d.get("mechanism",""))}</span>' if d.get('mechanism') and d.get('mechanism').lower()!='local' else ''}
<h3>{H.escape(d['title'])}</h3></header>
{img}
<dl>
<dt>where</dt><dd><code>{H.escape(d.get('where',''))}</code></dd>
{f"<dt>current</dt><dd>{H.escape(d.get('current',''))}</dd>" if d.get('current') else ""}
{f"<dt>target</dt><dd>{H.escape(d.get('target',''))}</dd>" if d.get('target') else ""}
{f"<dt>fix</dt><dd>{H.escape(d.get('fix',''))}</dd>" if d.get('fix') else ""}
{f"<dt class=no>do NOT</dt><dd class=no>{H.escape(d.get('donot',''))}</dd>" if d.get('donot') else ""}
{f"<dt>verify</dt><dd>{H.escape(d.get('verify',''))}</dd>" if d.get('verify') else ""}
{f"<dt class=blast>blast</dt><dd class=blast>{H.escape(d.get('blast',''))}</dd>" if d.get('blast') else ""}
{f"<dt>v2 has</dt><dd>{H.escape(d.get('v2_has',''))}</dd>" if d.get('v2_has') else ""}
{f"<dt>looks like</dt><dd>{H.escape(d.get('looks_like',''))}</dd>" if d.get('looks_like') else ""}
</dl>
{code_html}
<details class="task"><summary>copy as a task</summary><pre>{H.escape(
 "FIX: "+d['title']+chr(10)+
 "file:    "+d.get('where','')+chr(10)+
 "current: "+d.get('current','')+chr(10)+
 "target:  "+d.get('target','')+chr(10)+
 "do:      "+d.get('fix','')+chr(10)+
 "do NOT:  "+d.get('donot','')+chr(10)+
 "verify:  "+d.get('verify','')+chr(10)+
 "affects: "+d.get('blast','this one only'))}</pre></details>
<footer><div class="trk" role="group">
<button data-s="open">Open</button><button data-s="doing">Fixing</button>
<button data-s="fixed">Fixed</button><button data-s="wont">Won't fix</button></div></footer>
</article>''')

seed=json.dumps({f"{d['lane']}:{i}":"open" for i,d in enumerate(items)})

# ---- static inventory section -------------------------------------------------
# The lane findings above are what agents LOOKED AT. This is what EXISTS, from
# walking all 921 v2 files. Reported separately and honestly: a surface with
# inventory rows but no finding was not audited, and the report must say so
# rather than let silence read as clean.
inv={}
try: inv=json.load(open(f'{ROOT}/inventory.json'))
except Exception: pass
covered={d['lane'] for d in items}
inv_rows=inv.get('rows',[])
by_area=collections.Counter(r['area'] for r in inv_rows)
by_kind=collections.Counter(r['kind'] for r in inv_rows)
by_comp=collections.Counter(r['what'] for r in inv_rows if r['what'] and r['kind'] in ('core-legacy','v1-components'))
areas_with_findings={ (d.get('where','').split(':')[0]) for d in items }
def audited(area):
    return any(area.split('/')[-1].lower() in (d.get('where','')+d['title']).lower() for d in items)
inv_html=[]
inv_html.append('<h2 id="inv">Static inventory — what exists, from all %d v2 files</h2>' % inv.get('files',0))
inv_html.append('<p class="sub">The findings above are what agents <b>looked at</b>. This is what <b>exists</b>. '
  'A surface with signals but no finding was not reached — that is stated, not hidden.</p>')
inv_html.append('<table class="inv"><thead><tr><th>surface</th><th>signals</th><th>audited?</th></tr></thead><tbody>')
for a,n in by_area.most_common():
    ok='yes' if audited(a) else '<b class="gap">not reached</b>'
    inv_html.append(f'<tr><td><code>{H.escape(a)}</code></td><td>{n}</td><td>{ok}</td></tr>')
inv_html.append('</tbody></table>')
inv_html.append('<h3>By kind</h3><table class="inv"><tbody>'+''.join(
    f'<tr><td><code>{H.escape(k)}</code></td><td>{v}</td><td>{H.escape(inv.get("descriptions",{}).get(k,""))}</td></tr>'
    for k,v in by_kind.most_common())+'</tbody></table>')
inv_html.append('<h3>Most-leaked components</h3><table class="inv"><tbody>'+''.join(
    f'<tr><td><code>{H.escape(c)}</code></td><td>{v} imports</td></tr>' for c,v in by_comp.most_common(20))+'</tbody></table>')
INV=''.join(inv_html)
html=f'''<title>v1 chrome inside v2 — audit</title>
<style>
:root{{--bg:#fafafa;--panel:#fff;--ink:#111114;--dim:#6b6b76;--line:#e6e6e3;--accent:#3b5bdb;
--glaring:#c92a2a;--noticeable:#e8590c;--subtle:#5c7cfa;--ok:#2b8a3e;--mono:ui-monospace,SFMono-Regular,Menlo,monospace}}
:root[data-theme=dark]{{--bg:#0f0f12;--panel:#17171b;--ink:#ececef;--dim:#9a9aa5;--line:#2a2a31;
--glaring:#ff6b6b;--noticeable:#ffa94d;--subtle:#91a7ff;--ok:#69db7c}}
@media(prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#0f0f12;--panel:#17171b;--ink:#ececef;--dim:#9a9aa5;--line:#2a2a31;--glaring:#ff6b6b;--noticeable:#ffa94d;--subtle:#91a7ff;--ok:#69db7c}}}}
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
.s-glaring{{background:var(--glaring)}}.s-noticeable{{background:var(--noticeable)}}.s-subtle{{background:var(--subtle)}}
.mech{{font:600 10.5px var(--mono);color:#fff;background:var(--accent);padding:2px 7px;border-radius:999px}}
dt.no,dd.no{{color:var(--glaring)}}
dt.blast,dd.blast{{color:var(--noticeable)}}
details.code{{margin-top:11px}}
details.code summary{{cursor:pointer;font-size:11.5px;color:var(--dim);text-transform:uppercase;letter-spacing:.05em}}
.src{{margin:8px 0 0;border:1px solid var(--line);border-radius:8px;overflow:hidden}}
.srchead{{background:var(--bg);border-bottom:1px solid var(--line);padding:5px 9px;font-size:11px;color:var(--dim)}}
.src table{{width:100%;border-collapse:collapse;font:12px/1.6 var(--mono)}}
.src td{{padding:0 9px;white-space:pre;overflow-x:auto}}
.src td.ln{{width:44px;text-align:right;color:var(--dim);user-select:none;border-right:1px solid var(--line);padding-right:8px}}
.src tr.hl{{background:color-mix(in srgb,var(--noticeable) 16%,transparent)}}
details.task{{margin-top:10px}}
details.task summary{{cursor:pointer;font-size:11.5px;color:var(--dim);text-transform:uppercase;letter-spacing:.05em}}
details.task pre{{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:11px;
font:12px/1.5 var(--mono);white-space:pre-wrap;margin:7px 0 0}}
.lane,.vis,.themes{{font:600 10.5px var(--mono);color:var(--dim);border:1px solid var(--line);padding:2px 7px;border-radius:999px}}
.shots{{display:grid;gap:9px;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));margin:11px 0}}
.shots figure{{margin:0;border:1px solid var(--line);border-radius:9px;overflow:hidden;background:var(--bg)}}
.shots img{{display:block;max-width:100%;height:auto;cursor:zoom-in}}
.shots figcaption{{font-size:11px;color:var(--dim);padding:5px 8px;border-top:1px solid var(--line)}}
.shots img:target,.shots img.zoom{{cursor:zoom-out;position:fixed;inset:12px;z-index:99;max-width:calc(100vw - 24px);
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
.gap{{color:var(--glaring)}}
h2{{font-size:16px;margin:30px 0 6px;letter-spacing:-.01em}}
h3{{font-size:13px;margin:22px 0 4px;color:var(--dim);text-transform:uppercase;letter-spacing:.06em}}
</style>
<div class="wrap">
<h1>v1 chrome inside v2</h1>
<p class="sub">Every place the old product still shows through the redesign. <b>Visible</b> means it
renders and looks different from its v2 equivalent — that is the list to act on. <b>Structural</b>
means a v1 module is imported but renders no chrome of its own; it is debt, not a visual defect.
The plugin's <code>dbn-*</code> classes and the v2 <code>sr-*</code> vocabulary are deliberately
not v1 and are not reported. Status is kept in this browser.</p>
<div class="stats">
<div class="stat"><b>{len(items)}</b><span>findings</span></div>
<div class="stat"><b style="color:var(--glaring)">{counts.get('glaring',0)}</b><span>glaring</span></div>
<div class="stat"><b style="color:var(--noticeable)">{counts.get('noticeable',0)}</b><span>noticeable</span></div>
<div class="stat"><b style="color:var(--subtle)">{counts.get('subtle',0)}</b><span>subtle</span></div>
<div class="stat"><b>{vis.get('visible',0)}</b><span>visible</span></div>
<div class="stat"><b>{vis.get('structural',0)}</b><span>structural</span></div>
</div>
<div class="bar">
<button data-f="sev" data-v="glaring">glaring</button>
<button data-f="sev" data-v="noticeable">noticeable</button>
<button data-f="sev" data-v="subtle">subtle</button>
<button data-f="vis" data-v="visible">visible only</button>
{''.join(f'<button data-f="lane" data-v="{l}">{l}</button>' for l in sorted(lanes))}
<button data-f="trk" data-v="open">not fixed</button>
<input id="q" placeholder="search…" size="18">
<span class="count" id="cnt"></span>
</div>
<div id="list">
{''.join(cards)}
</div>
<hr style="margin:38px 0;border:0;border-top:1px solid var(--line)">
{INV}
</div>
<script>
const KEY='v1-in-v2::2026-08-27';
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
// click any screenshot to blow it up - a 260px thumbnail cannot show a 4px radius difference
document.addEventListener('click',e=>{{if(e.target.tagName==='IMG'&&e.target.closest('.shots'))
  e.target.classList.toggle('zoom');}});
</script>'''
open(OUT,'w',encoding='utf-8').write(html)
print(f'{len(items)} findings -> {OUT}  ({os.path.getsize(OUT)//1024} KB)')
print(' severity:',dict(counts),' | ',dict(vis),' | lanes:',dict(lanes))
