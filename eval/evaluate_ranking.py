"""Does the final status/priority agree with independent 'good prospect' judgements?"""
import json, glob, duckdb, collections as C
lab = {r['domain']: r for f in glob.glob('eval/labels_batch*.json') for r in json.load(open(f))}
con = duckdb.connect('pipeline/firmable.duckdb', read_only=True)
p = {d: (s, pr, t) for d, s, pr, t in con.execute("SELECT d, status, priority, tier FROM prospects").fetchall()}
rows = [(lab[d]['good_prospect'], lab[d]['asset_theirs'], *p[d]) for d in lab if d in p]
print("status x label good_prospect:")
tab = C.Counter((s, g) for g, a, s, pr, t in rows)
for s in ['ranked', 'needs_review', 'excluded_provider', 'excluded_not_a_business']:
    print(f"  {s:26s}", {g: tab[(s, g)] for g in ['yes', 'no', 'unsure']})
dec = [(g, s) for g, a, s, pr, t in rows if g in ('yes', 'no')]
ranked = [g for g, s in dec if s == 'ranked']
excl = [g for g, s in dec if s.startswith('excluded')]
print(f"precision of 'ranked' (label yes / decided labels): {ranked.count('yes')}/{len(ranked)} = {ranked.count('yes')/max(1,len(ranked)):.0%}")
print(f"exclusion precision (label no among excluded): {excl.count('no')}/{len(excl)} = {excl.count('no')/max(1,len(excl)):.0%}")
yes = [s for g, s in dec if g == 'yes']
print(f"recall: yes-labelled that we rank {yes.count('ranked')}/{len(yes)}; send to review {yes.count('needs_review')}; wrongly excluded {sum(s.startswith('excluded') for s in yes)}")
asset = C.Counter(a for g, a, s, pr, t in rows if s == 'ranked')
print("asset_theirs among ranked:", dict(asset))
