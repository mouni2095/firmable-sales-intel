"""Compare LLM classifications with independent labels (held-out stratified sample of 150)."""
import json, glob, collections as C, sys
lab = {r['domain']: r for f in sorted(glob.glob('eval/labels_batch*.json')) for r in json.load(open(f))}
pred = {r['domain']: r for r in map(json.loads, open(sys.argv[1] if len(sys.argv) > 1 else 'llm/classified.jsonl'))}
PROSPECT = {'business', 'government', 'education', 'nonprofit'}
def bucket(t): return 'prospect_type' if t in PROSPECT else ('excluded' if t not in ('unknown', None) else 'unknown')
ent = [(lab[d], pred[d]) for d in lab if d in pred]
known = [(l, p) for l, p in ent if l['entity_type'] != 'unknown']
print(f"labelled {len(ent)}  | label known {len(known)}  | label unknown {len(ent)-len(known)}")
# 1) entity type, exact and at decision level (prospect vs excluded), on rows where both are non-unknown
both = [(l, p) for l, p in known if p['entity_type'] != 'unknown']
abst = [(l, p) for l, p in known if p['entity_type'] == 'unknown']
print(f"LLM abstained on {len(abst)}/{len(known)} known rows")
acc = sum(l['entity_type'] == p['entity_type'] for l, p in both) / len(both)
dec = sum(bucket(l['entity_type']) == bucket(p['entity_type']) for l, p in both) / len(both)
print(f"entity_type exact acc {acc:.2%}  | prospect-vs-excluded acc {dec:.2%}  (n={len(both)})")
fp = [(l['domain'], l['entity_type'], p['entity_type']) for l, p in both if bucket(p['entity_type']) == 'prospect_type' and bucket(l['entity_type']) != 'prospect_type']
fn = [(l['domain'], l['entity_type'], p['entity_type']) for l, p in both if bucket(p['entity_type']) != 'prospect_type' and bucket(l['entity_type']) == 'prospect_type']
print("  LLM says prospect, label says not:", fp); print("  LLM excludes, label says prospect:", fn)
ind = [(l, p) for l, p in both if l['industry'] not in ('unknown',) and p['industry'] != 'unknown']
print(f"industry exact acc {sum(l['industry']==p['industry'] for l,p in ind)/max(1,len(ind)):.2%} (n={len(ind)})")
# 2) calibration: LLM confidence vs correctness of entity_type
bins = C.defaultdict(list)
for l, p in both:
    b = min(int(p['confidence'] * 5), 4) / 5
    bins[b].append(l['entity_type'] == p['entity_type'])
print("calibration (conf bin -> n, accuracy):", {f"{k:.1f}-{k+.2:.1f}": (len(v), round(sum(v)/len(v), 2)) for k, v in sorted(bins.items())})
# 3) cost
print(f"cost for {len(pred)} calls: ${sum(p.get('cost_usd',0) for p in pred.values()):.4f}  -> per 1k: ${1000*sum(p.get('cost_usd',0) for p in pred.values())/len(pred):.3f}")
# 4) how labels were obtained
print("label verification:", C.Counter('search' if 'search' in (l.get('verified_by') or '').lower() else 'knowledge/other' for l, _ in known))
