"""Build the LLM input: evidence context for every company with need >= 0.3.
Usage: python llm/make_candidates.py pipeline/firmable.duckdb llm/candidates.jsonl"""
import sys, json, duckdb
con = duckdb.connect(sys.argv[1])
con.execute("""CREATE OR REPLACE TABLE ctx AS
WITH cand AS (SELECT d FROM company_v WHERE need >= 0.3),
t AS (SELECT t.d, b.hostnames, b.http_title, b.cert_o, b.org FROM tenant t JOIN base b USING (rid) WHERE t.d IN (SELECT d FROM cand))
SELECT d, list(DISTINCT h)[1:6] hosts,
  list(DISTINCT http_title) FILTER (WHERE http_title IS NOT NULL AND length(trim(http_title)) > 2
                                     AND NOT regexp_matches(http_title, '^\\d{3}( |$)'))[1:4] titles,
  list(DISTINCT cert_o) FILTER (WHERE cert_o IS NOT NULL)[1:3] cert_orgs,
  list(DISTINCT org)[1:3] net_orgs
FROM (SELECT t.*, unnest(t.hostnames) h FROM t) WHERE h = d OR h LIKE '%.' || d GROUP BY d""")
rows = con.execute("""SELECT x.d, x.hosts, x.titles, x.cert_orgs, x.net_orgs, c.country, c.n_ips
  FROM ctx x JOIN company_v c USING (d) ORDER BY c.need DESC""").fetchall()
with open(sys.argv[2], "w") as f:
    for d, h, t, co, no, cc, n in rows:
        f.write(json.dumps({"domain": d, "hosts": h, "titles": t, "cert_orgs": co, "net_orgs": no, "country": cc, "n_ips": n}, ensure_ascii=False) + "\n")
print(len(rows), "candidates")
