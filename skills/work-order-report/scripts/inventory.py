#!/usr/bin/env python3
"""Exhaustive static inventory of v1 signal inside v2. Repo-wide by construction:
walks every v2 file rather than whatever a browser happened to navigate to."""
import re,os,collections,json
SRC='/Users/kelashik/codes/db_git/v2/frontend/packages/@databrainhq/frontend/src'
PKGS={
 'frontend':'/Users/kelashik/codes/db_git/v2/frontend/packages/@databrainhq/frontend/src/v2',
}
PAT={
 'core-legacy'  : (re.compile(r"from '@databrainhq/core/components/legacy/([A-Za-z]+)"), 'imports a v1 component from core'),
 'v1-components': (re.compile(r"from 'components/([A-Za-z]+)"), 'imports a v1 product component'),
 'v1-pages'     : (re.compile(r"from 'pages/([A-Za-z]+)"), 'imports from a v1 page'),
 'plugin-comp'  : (re.compile(r"from '@plugin/components"), 'renders the EMBED component set inside the product'),
 'db-class'     : (re.compile(r"[\"'\s](db-[a-z][a-z0-9-]*)"), 'uses a v1 product stylesheet class'),
 'compat-shim'  : (re.compile(r"(v1Compat|legacyAccordionSkin|plugin-portal-dark)"), 'depends on a v1 compatibility shim'),
}
def area(rel):
    p=rel.split('/')
    if len(p)>2 and p[1]=='pages': return 'pages/'+p[2]
    if len(p)>2 and p[1]=='components': return 'components/'+p[2]
    return '/'.join(p[:2])

rows=[]; areas=collections.Counter(); comp=collections.Counter(); kinds=collections.Counter()
files=0
for r,_,fs in os.walk(PKGS['frontend']):
    if 'node_modules' in r or '__tests__' in r: continue
    for f in sorted(fs):
        if not f.endswith(('.ts','.tsx','.css')): continue
        files+=1; p=os.path.join(r,f); rel=os.path.relpath(p,SRC)
        try: lines=open(p,encoding='utf-8',errors='replace').read().splitlines()
        except: continue
        a=area(rel)
        for i,line in enumerate(lines,1):
            for k,(rx,_d) in PAT.items():
                for m in rx.findall(line):
                    rows.append({'area':a,'file':rel,'line':i,'kind':k,'what':m if isinstance(m,str) else ''})
                    areas[a]+=1; kinds[k]+=1
                    if k in ('core-legacy','v1-components'): comp[m]+=1
json.dump({'files':files,'rows':rows,
           'areas':dict(areas.most_common()),'components':dict(comp.most_common()),
           'kinds':dict(kinds.most_common()),
           'descriptions':{k:d for k,(_r,d) in PAT.items()}},
          open('/Users/kelashik/codes/db_git/v2/.v1audit/inventory.json','w'), indent=1)
print(f'{files} v2 files scanned, {len(rows)} v1 signals across {len(areas)} surfaces')
for k,v in kinds.most_common(): print(f'  {v:5} {k}')
