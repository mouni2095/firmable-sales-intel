"""Stage 2+: resolve companies, build signals, score. Input: slim Parquet produced by sql/01_extract.sql.
Usage: python run_pipeline.py "<parquet glob>" <duckdb file> [llm/classified.jsonl]
Without the classification file it stops after need scoring (company_v); with it, it builds the ranked prospects table."""
import sys, pathlib, duckdb, tldextract

SQL = pathlib.Path(__file__).parent / "sql"

def domain_validity(con):
    """Registrable-domain check against the Public Suffix List (incl. private suffixes like pp.ua)."""
    ext = tldextract.TLDExtract(suffix_list_urls=(), cache_dir=None, include_psl_private_domains=True)
    rows = []
    for (d,) in con.execute("SELECT DISTINCT d FROM tenant").fetchall():
        e = ext(d.lower())
        rows.append((d, e.top_domain_under_public_suffix or None, e.suffix or None, e.domain or None))
    con.execute("CREATE OR REPLACE TABLE dvalid (d VARCHAR, reg VARCHAR, suffix VARCHAR, label VARCHAR)")
    con.executemany("INSERT INTO dvalid VALUES (?, ?, ?, ?)", rows)

def main(parquet_glob, db, classified=None):
    con = duckdb.connect(db)
    con.execute("SET memory_limit='5GB'; SET preserve_insertion_order=false")
    con.execute(f"CREATE OR REPLACE VIEW s AS SELECT * FROM read_parquet('{parquet_glob}')")
    for f in ["02_hosts.sql", "03_tenants.sql", "04_ipstat.sql"]:
        print("running", f, flush=True); con.execute((SQL / f).read_text())
    domain_validity(con)
    for f in ["05_signals.sql", "06_attribute.sql", "07_company.sql"]:
        print("running", f, flush=True); con.execute((SQL / f).read_text())
    print(con.execute("SELECT count(*), count(*) FILTER (WHERE need >= 0.3) FROM company_v").fetchall())
    if classified:
        con.execute((SQL / "08_priority.sql").read_text().replace("__CLS__", classified))
        print(con.execute("SELECT status, count(*) FROM prospects GROUP BY 1 ORDER BY 1").fetchall())

if __name__ == "__main__":
    main(*sys.argv[1:4])
