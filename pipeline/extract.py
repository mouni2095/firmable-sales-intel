"""Stage 1: stream one raw Shodan zstd NDJSON file into slim Parquet (one pass, constant memory).
Usage: python pipeline/extract.py <raw_file> <out_dir> [memory_limit]
Each monthly file is independent, so N files can run in parallel (one process per file)."""
import sys, pathlib, duckdb
src, out = sys.argv[1], sys.argv[2]
mem = sys.argv[3] if len(sys.argv) > 3 else "3GB"
sql = (pathlib.Path(__file__).parent / "sql" / "01_extract.sql").read_text()
pathlib.Path(out).mkdir(parents=True, exist_ok=True)
duckdb.connect().execute(sql.replace("__SRC__", src).replace("__OUT__", out).replace("__MEM__", mem))
print("done:", out)
