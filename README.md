# Exposure Radar: which organisations need cybersecurity help right now

A small sales-intelligence platform for a cybersecurity vendor. It turns one month's raw internet-scan file (Shodan banners, 17.6 GB zstd NDJSON, 14.6M records) into a **ranked, explainable account list**. Every score links back to the exact hosts and findings behind it.

**Live app:** https://mouni2095.github.io/firmable-sales-intel/ · **Stack:** DuckDB (SQL), Python, Claude Haiku 5.5, static HTML/JS

## Results at a glance

| | |
|---|---|
| Raw records → organisations resolved | 14,608,407 → 448,322 |
| Organisations with a security need score ≥ 0.3 | 13,474 (all classified by the LLM) |
| Ranked accounts / P1 "act now" | 3,187 / 48 |
| Sent to *needs review* (we abstain) | 5,842 |
| Excluded (ISPs, hosting, SaaS platforms, parked sites) | 4,445 |
| Ranked accounts judged good prospects (held-out labels) | **85%** (23/27; 95% CI ≈ 67–94%) |
| Excluded accounts correctly excluded | **100%** (43/43) |
| LLM cost | **$3.24** for 13,474 accounts ($0.24 / 1k) |

## How a salesperson uses it
Open **Ranked accounts** and filter by tier, industry, country, signal (e.g. *Remote Desktop exposed*), size or regulated data. Click an account to see **why**: each signal with its probability, the affected `ip:port`, how the asset was tied to the organisation, and what the organisation is (with the LLM's confidence and reasoning). Export the filtered list as CSV. Accounts the system isn't sure about are kept apart in **Needs review**, not mixed into the ranked list.

## Approach

```
raw .zst NDJSON ──(1) extract──▶ slim Parquet ──(2) resolve orgs──▶ (3) signals ──▶ (4) need score
                                                                                         │
                                       docs/data.json ◀──(6) rank: need × fit ◀──(5) LLM classify
```

1. **Extract** (`pipeline/sql/01_extract.sql`). This is one streaming DuckDB pass with a typed schema, so only the needed fields are parsed. 17.6 GB becomes 0.74 GB of Parquet in **185 s on a laptop**.
2. **Resolve organisations** (`02_hosts.sql`, `03_tenants.sql`). The `org` field is mostly hosting (Google, Aliyun, AWS, Incapsula, Cloudflare…), so organisations come from **named hostnames and TLS certificates** instead:
   - drop reverse-DNS names (`ec2-3-4-5-6…`, `84-26-87-197.cable…`) and generic server names (`vps123`, `srv01`);
   - drop 25.9k infrastructure domains (>300 IPs, mostly rDNS, or generic-host fleets);
   - validate against the Public Suffix List, including private suffixes (this removed fake "companies" like `com.ru`, `pp.ua`);
   - **tenancy**: an IP serving more than 3 organisations is shared hosting, and its findings are discounted ×0.1 for each tenant;
   - **CDN edges never count as exposures**, because they run the CDN's software, not the customer's;
   - any IP with a honeypot-tagged service is dropped entirely.
3. **Signals** (`05_signals.sql`, `07_company.sql`). Each finding gets a prior probability that it reflects a real, actionable need, multiplied by attribution confidence (named host 1.0, same-IP 0.7, then the tenancy discount):

   | Signal | Prior | Note |
   |---|---|---|
   | Compromise evidence (C2 frameworks, `compromised` tag, "pwn" DBs) | 0.9 (0.5 on cloud) | cloud C2 is more likely attacker-rented |
   | Open data store (unauthenticated Mongo/Redis/Influx, anonymous FTP) | 0.6 | |
   | Known exploited CVE (CISA KEV) with ransomware use | 0.6 | ×1 if Shodan *verified*, ×0.6 if unverified, ×0.3 on distro builds |
   | Known exploited CVE | 0.25 + 0.2·EPSS | same discounts |
   | SMB / RDP / VNC / telnet exposed | 0.40 / 0.35 / 0.35 / 0.30 | |
   | OT / medical (ICS, DICOM) exposed | 0.4 | |
   | On-prem Exchange, EOL software, open directory | 0.30 / 0.25 / 0.25 | |
   | DB port exposed, expired cert, legacy TLS, self-signed cert | 0.25 / 0.10 / 0.08 / 0.05 | hygiene |

   **Need** is a noisy-OR over the *strongest* item of each signal type, with KEV and KEV-ransomware collapsed into one group. This way 50 expired certificates don't outrank one verified SMBGhost.
4. **LLM classification** (`llm/classify.py`). Claude Haiku 5.5 sees only scan evidence (hostnames, page titles, cert org, network owner, country, IP count). It returns organisation type, industry, size, regulated-data flag, an honest confidence and a ≤20-word reason, through a forced tool call with enum-constrained fields. Answers outside the enums are rejected and retried (39 accounts hit such drift; 8 still failed after 5 retries and are recorded as `unknown`). The prompt says *"a wrong label is worse than no label"*.
5. **Rank** (`08_priority.sql`). priority = need × fit, where fit is type (business 1.0, government 0.8, education 0.7, nonprofit 0.6) × size × 1.25 if regulated, capped at 1. Status rules:
   - ISP, hosting and SaaS-platform owners → **excluded**;
   - personal or parked sites → **excluded**;
   - `unknown`, LLM confidence < 0.5, or only seen on shared hosting → **needs review**.

   Tier **P1** = compromise, open data, or a strong KEV finding; **P2** = need ≥ 0.5; **P3** = hygiene.

## Hidden signals and traps (the part a naive pass gets wrong)
- **`*-rat` modules are probe names, not detections.** 72k rows say `darktrack-rat`, `remcos-pro-rat`, … and most have empty banners. Treating them as compromise would flood the list. Real compromise evidence is a few hundred rows.
- **Honeypots.** 250k rows are tagged, and a WebLogic/Struts CVE cluster on AWS (~998 rows per CVE) is 60%+ tagged honeypots. Whole IPs are dropped.
- **Version-inferred CVEs.** Only ~0.04% of CVE matches are verified. The top KEV hits (Apache CVE-2021-40438, CVE-2024-38475) are inferred from version strings on CentOS/Ubuntu builds that backport fixes, so they're discounted. CVE-2023-44487 (HTTP/2 Rapid Reset) appears on 173k rows and is ignored. By contrast **SMBGhost (CVE-2020-0796) is verified on 1,038 hosts**, making it the strongest single signal in the file.
- **CVSS is a poor ranker.** In the first 20k records alone, 3,475 CVE matches score ≥9. KEV + EPSS + verification is used instead.
- **Maturity signals** are kept as context, not need: `security.txt` (only 8.3k services publish one) and WAF/CDN coverage.
- An early bug worth noting: a regex for "RAT" matched *Vi**rat**a* and *Corpo**rat**ion*. It was caught by reading the top of the ranked list.

## How I measured whether it works
- **Held-out set:** 150 accounts, stratified random (75 need ≥ 0.6, 75 need 0.3–0.6), seeded by hash. They were never used to tune prompts or weights (`eval/`).
- **Labels:** independent of the model. Each account was researched on the web (search results about the domain or organisation) and labelled for organisation type, industry, whether the asset is really theirs, and whether it's a good prospect. Labellers never saw the model's output.
  - **Disclosure:** first-pass labels came from LLM research agents using web search, not by hand. 46 of 93 identifiable labels cite a search result; 47 rest on the agent's own knowledge of well-known organisations. 57/150 accounts could not be identified and are excluded from the metrics, not counted as wins.
  - **Human spot-check:** I checked 25 randomly chosen labels myself (site or web search). I agreed with all 21 I could decide; 4 were "can't tell" (`eval/spot_check.xlsx`). That's a small check, so it supports but does not prove label quality.
- **Circularity:** the labeller had *new information* (web results) that the classifier never saw. The ranking check measures the end decision (rank / review / exclude), not just agreement between two models.

| Check (`eval/evaluate.py`, `eval/evaluate_ranking.py`) | Result |
|---|---|
| Ranked → labelled good prospect | 23/27 = 85% |
| Excluded → labelled not a prospect | 43/43 = 100% |
| Labelled good prospects: ranked / review / wrongly excluded | 23 / 6 / 0 |
| Asset really belongs to org (ranked accounts) | 30 yes, 4 unsure, 1 no |
| LLM prospect-vs-excluded type | 92% (n=86); exact type 81%; industry 91% (n=76) |
| LLM accuracy by confidence | ≥0.8 → 92% (n=49); <0.8 → 68% (n=37) |
| Same metrics on search-verified labels only | prospect-vs-excluded 90% (n=40) |

The LLM's main error is letting small ISPs and hosting companies through as "business". The confidence threshold and the shared-hosting rule catch some of these. A next step would be a cheap deterministic ISP check (ASN type / PeeringDB).

**Cost:** 16.8M input + 3.1M output tokens = $3.24 for 13,474 accounts (Haiku 5.5, $0.10/$0.50 per MTok). Prompts are ~1.25k tokens each, mostly the tool schema.

## Scaling to hundreds or thousands of files a month
- **Extract is per-file and embarrassingly parallel.** Each file streams through `pipeline/extract.py` in constant memory, writing ~250 MB Parquet chunks. 17.6 GB took 3 min on one laptop, so 1,000 files is ~50 machine-hours, or about 1 hour on 50 workers.
- **Resolution and scoring are set-based SQL over Parquet.** They can be partitioned by IP hash, since tenancy and attribution are per-IP. The full stage ran in ~10 min on 2 vCPUs.
- **LLM cost follows *new* organisations, not volume.** `classify.py` is resumable and keyed by domain, so each organisation is classified once and only new domains are sent. Cost is about $0.24 per 1,000 new organisations, and the Batch API would halve it.
- **Timing:** monthly files make "newly exposed since last scan" (new RDP, new KEV) the best *right now* signal. Findings are already keyed by `domain, ip, port, signal` in the `ev` table to support that diff.

## Run it
```bash
pip install -r requirements.txt
python pipeline/extract.py <raw_file.zst> data/slim                               # stage 1
python pipeline/run_pipeline.py "data/slim/*.parquet" pipeline/firmable.duckdb   # stages 2–3 (need)
python llm/make_candidates.py pipeline/firmable.duckdb llm/candidates.jsonl
python llm/classify.py llm/candidates.jsonl llm/classified.jsonl anthropic_key.txt 12
python pipeline/run_pipeline.py "data/slim/*.parquet" pipeline/firmable.duckdb llm/classified.jsonl
python pipeline/export_app_data.py && python -m http.server -d docs                # app
python eval/evaluate.py && python eval/evaluate_ranking.py                         # metrics
```
A clean re-run reproduced the reported counts exactly (448,322 organisations, 13,474 candidates).

## Limits and what I'd do next
- Signal priors are expert estimates, checked but not fitted. With outcome data (replies, meetings, deals) they should be learned, e.g. a logistic model over the same evidence items.
- The evaluation set is small (n=27 decided ranked labels). It needs more human labels, especially among ranked accounts.
- Small businesses on shared hosting are under-represented by design: we abstain rather than blame them for their host's servers.
- One snapshot: the timing signal needs the monthly diff above.

## How it was built (AI-native dev loop)
Built with an AI coding agent in the loop: the agent ran queries and drafted the SQL and code, and I reviewed the results and made the calls. The loop was: profile → hypothesise → query → read the top of the output → fix.
- The raw data was explored interactively before any model was involved: field inventory, value counts, sampled banners. The traps above came from inspecting rows, not from handing the file to an LLM.
- Every rule was checked against real rows. Examples: the RAT-module trap (banner emptiness), the CVE backport trap (CPE distribution of the top KEV CVEs), and the regex bug (the top-30 list).
- LLM use is narrow and measured: one classification step with schema validation, cost logging, abstention, and evaluation against independent labels.
