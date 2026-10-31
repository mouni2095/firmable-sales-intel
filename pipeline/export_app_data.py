"""Export ranked + needs-review accounts (with evidence and assets) to app/data.json."""
import json, duckdb, sys
db = sys.argv[1] if len(sys.argv) > 1 else 'pipeline/firmable.duckdb'
out = sys.argv[2] if len(sys.argv) > 2 else 'app/data.json'
con = duckdb.connect(db, read_only=True)
rows = con.execute("""
WITH assets AS (
  SELECT d, list({'ip': ip, 'port': port, 'sig': sig, 'detail': detail, 'how': how, 'shared': ip_tenants}
                 ORDER BY p_eff DESC)[1:12] AS assets
  FROM ev GROUP BY d)
SELECT p.d, p.company_name, p.entity_type, p.industry, p.size, p.regulated, round(p.cls_conf, 2), p.cls_reason,
       p.country, p.n_ips, p.n_services, p.host_org, p.securitytxt, round(p.protected_share, 2),
       round(p.need, 3), round(p.fit, 2), round(p.priority, 3), p.tier, p.status, p.evidence, a.assets
FROM prospects p LEFT JOIN assets a USING (d)
WHERE p.status IN ('ranked', 'needs_review')
ORDER BY p.status, p.priority DESC""").fetchall()
keys = ['d','name','type','industry','size','regulated','cls_conf','cls_reason','country','n_ips','n_services',
        'host_org','securitytxt','protected','need','fit','priority','tier','status','evidence','assets']
stats = dict(con.execute("SELECT status, count(*) FROM prospects GROUP BY 1").fetchall())
data = {"meta": {"scan_window": "2026-10-25 18:13 → 2026-10-26 13:06 UTC", "raw_rows": 14608407,
                 "companies_resolved": con.execute("SELECT count(*) FROM company_v").fetchone()[0],
                 "candidates_classified": con.execute("SELECT count(*) FROM prospects").fetchone()[0],
                 "status_counts": stats},
        "accounts": [dict(zip(keys, r)) for r in rows]}
json.dump(data, open(out, 'w'), ensure_ascii=False, separators=(',', ':'), default=float)
print(len(rows), 'accounts')
