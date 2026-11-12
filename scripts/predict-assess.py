#!/usr/bin/env python3
"""Summarize a prediction assessment dump.

Produce the dump with the build-tagged harness in api/internal/predict/assess_test.go:

    cd api && mkdir -p /tmp/assess && \
      ASSESS_DIR=/tmp/assess go test -tags assess -run TestAssessDump -count=1 ./internal/predict/
    python3 scripts/predict-assess.py /tmp/assess

Tables: walk-forward peak grades (nightly retrain), served 9am/1pm day-level
calls, the pre-open "could keep it closed" warning vs ramps actually shut at
the open, and reopen quotes for closed ramps. Buckets are months, then
two-week windows from 9/15 (King Tide season). Built for the 2026-11-12 fall
review; the numbers in outlook.go comments came from these tables.
"""
import json, sys, collections, datetime as dt
from zoneinfo import ZoneInfo
ET=ZoneInfo('America/New_York')
D=sys.argv[1]
def rd(n): return [json.loads(l) for l in open(f'{D}/{n}.jsonl')]
def T(s): return dt.datetime.fromisoformat(s.replace('Z','+00:00')) if s else None
def bucket(day):
    d=dt.date.fromisoformat(day)
    if d>=dt.date(2026,9,15):  # weekly-ish buckets for king tide season
        start=dt.date(2026,9,15)+dt.timedelta(days=((d-dt.date(2026,9,15)).days//14)*14)
        return start.strftime('%m/%d+')
    return day[:7]
COST={'hit':0,'quiet':0,'covered':0.5,'hedged':0.5,'miss':4,'false_alarm':2}
try:
    from importlib import import_module
except: pass
G=rd('grades')
tal=collections.defaultdict(lambda: collections.Counter())
for r in G:
    o=r['g']['outcome']; b=bucket(r['day'])
    for k in (b,'ALL'):
        tal[k][o]+=1
print('== peak grades (walk-forward, nightly retrain)')
print(f"{'bucket':9} {'n':>5} {'closed':>6} {'miss':>5} {'recall':>6} {'likely':>9} {'prec':>5} {'hedge':>5} {'stale':>5} {'score':>6}")
for k in sorted(tal, key=lambda x:(x=='ALL',x)):
    c=tal[k]; n=sum(v for o,v in c.items() if o!='stale')
    closed=c['hit']+c['covered']+c['miss']; lik=c['hit']+c['false_alarm']
    cost=sum(COST[o]*v for o,v in c.items() if o!='stale')
    print(f"{k:9} {n:5} {closed:6} {c['miss']:5} {1-c['miss']/max(closed,1):6.2f} {c['hit']:4}/{lik:<4} {c['hit']/max(lik,1):5.2f} {c['hedged']:5} {c['stale']:5} {1-cost/(4*max(n,1)):6.3f}")

S=rd('served')
print('\n== served day-level (ramp open at probe; truth = tide closure later that day)')
for probe in ('0900','1300'):
    tal=collections.defaultdict(collections.Counter)
    for r in S:
        if r['probe']!=probe or r.get('stale'): continue
        if r['status'] in ('CLOSED FOR HIGH TIDE','CLOSED','CLOSED - CLEARED FOR TURTLES'): 
            continue
        closed=r['first_close'] is not None
        risk=r['risk']
        o = ('hit' if risk=='likely' else 'covered' if risk=='possible' else 'miss') if closed else ('false_alarm' if risk=='likely' else 'hedged' if risk=='possible' else 'quiet')
        for k in (bucket(r['day']),'ALL'): tal[k][o]+=1
    print(f'-- probe {probe}')
    print(f"{'bucket':9} {'n':>5} {'closed':>6} {'miss':>5} {'recall':>6} {'prec':>5} {'hedge%':>6} {'score':>6}")
    for k in sorted(tal, key=lambda x:(x=='ALL',x)):
        c=tal[k]; n=sum(c.values()); closed=c['hit']+c['covered']+c['miss']; lik=c['hit']+c['false_alarm']
        cost=sum(COST[o]*v for o,v in c.items())
        print(f"{k:9} {n:5} {closed:6} {c['miss']:5} {1-c['miss']/max(closed,1):6.2f} {c['hit']/max(lik,1):5.2f} {c['hedged']/max(n,1):6.2f} {1-cost/(4*max(n,1)):6.3f}")

print('\n== pre-open: flagged "could keep it closed" vs held shut at open')
tal=collections.defaultdict(collections.Counter)
for r in S:
    if r['probe']!='preopen' or r.get('stale'): continue
    held = r.get('status_at_open')=='CLOSED FOR HIGH TIDE'
    flagged = r['open_late'] is not None
    for k in (bucket(r['day']),'ALL'): tal[k][(flagged,held)]+=1
print(f"{'bucket':9} {'held':>5} {'caught':>6} {'flagged':>7} {'flag-held%':>10}")
for k in sorted(tal, key=lambda x:(x=='ALL',x)):
    c=tal[k]; held=c[(True,True)]+c[(False,True)]; fl=c[(True,True)]+c[(True,False)]
    print(f"{k:9} {held:5} {c[(True,True)]:6} {fl:7} {c[(True,True)]/max(fl,1):10.2f}")

st=collections.Counter(bucket(r['day']) for r in rd('stale'))
print('\n== stale ramp-days by bucket', dict(sorted(st.items())))

print('\n== pre-open warning by season (caught = flagged and shut at open; quoted reopen vs actual for caught)')
tal2=collections.defaultdict(lambda: collections.Counter()); perrs=collections.defaultdict(list)
for l in open(f'{D}/served.jsonl'):
    r=json.loads(l)
    if r['probe']!='preopen' or r.get('stale'): continue
    held=r.get('status_at_open')=='CLOSED FOR HIGH TIDE'
    fl=r['open_late'] is not None
    k='summer' if '2026-06'<=r['day']<'2026-09' else ('fall' if r['day']>='2026-09-15' else 'other')
    for kk in (k,'ALL'):
        tal2[kk][(fl,held)]+=1
        if fl and held:
            oa=T(r.get('opened_at')); q=T(r['open_late']); closes=T(r['closes'])
            if oa is None or oa>=closes: perrs[kk].append(None if q<closes else 0)
            else: perrs[kk].append((q-oa).total_seconds()/3600)
for k in ('summer','other','fall','ALL'):
    c=tal2[k]; held=c[(True,True)]+c[(False,True)]; fl=c[(True,True)]+c[(True,False)]
    e=perrs[k]; never=sum(1 for x in e if x is None); ee=[x for x in e if x is not None]
    print(f"{k:7} held {held:4} caught {c[(True,True)]:4} ({c[(True,True)]/max(held,1):.2f})  flagged {fl:4} precision {c[(True,True)]/max(fl,1):.2f}  | quoted reopen vs actual (caught): early>30m {sum(x<-0.5 for x in ee)/max(len(ee),1):.2f} mean {sum(ee)/max(len(ee),1):+.2f}h  promised-but-never {never}")

print('\n== reopen quotes for ramps closed now (served 20 min after posting)')
tal3=collections.defaultdict(collections.Counter); rerrs=collections.defaultdict(list)
for l in open(f'{D}/reopen.jsonl'):
    r=json.loads(l)
    ca=T(r['closed_at']); ra=T(r['reopened_at']); est=T(r['est']); closes=T(r['closes'])
    if closes is None or ca>=closes or est is None: continue
    eod = ra is None or r['next']=='CLOSED' or ra>=closes-dt.timedelta(minutes=20)
    said_day = est>closes
    k='fall' if r['day']>='2026-09-15' else 'spring/summer'
    for kk in (k,'ALL'):
        c=tal3[kk]; c['n']+=1
        if said_day and eod: c['day_right']+=1
        elif said_day: c['day_wrong']+=1; rerrs[kk+'_dw'].append((closes-ra).total_seconds()/3600)
        elif eod: c['promised_never']+=1
        else:
            e=(est-ra).total_seconds()/3600; rerrs[kk].append(e)
for k in ('spring/summer','fall','ALL'):
    c=tal3[k]; e=rerrs[k]; dw=rerrs[k+'_dw']
    print(f"{k:13} n {c['n']:4} | 'for the day' right {c['day_right']:4} wrong {c['day_wrong']:3} (reopened {sum(dw)/max(len(dw),1):.1f}h before close) | promised-never {c['promised_never']:3} | timed {len(e):4} meanAbs {sum(map(abs,e))/max(len(e),1):.2f}h  quoted-too-early>30m {sum(x<-0.5 for x in e)/max(len(e),1):.2f}  too-late>90m {sum(x>1.5 for x in e)/max(len(e),1):.2f}")
