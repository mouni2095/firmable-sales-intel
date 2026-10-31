"""LLM step: classify candidate company domains (entity type, industry, size, regulated).
The model only sees evidence extracted from the scan (hostnames, page titles, cert org, network owner).
It must abstain ('unknown') rather than guess. Usage + cost are logged per call."""
import json, sys, os, time, concurrent.futures as cf
import anthropic

MODEL = "claude-haiku-5-5"
PRICE_IN, PRICE_OUT = 0.10 / 1e6, 0.50 / 1e6   # USD per token (<=100K-token prompts)

ENTITY = ["business", "isp_telecom", "hosting_cloud", "saas_platform", "education", "government",
          "nonprofit", "personal_or_parked", "unknown"]
INDUSTRY = ["healthcare", "finance_banking", "insurance", "legal", "manufacturing", "retail_ecommerce",
            "technology_software", "media_entertainment", "hospitality_travel", "logistics_transport",
            "energy_utilities", "real_estate_construction", "professional_services", "education",
            "government_public", "nonprofit", "telecom_hosting", "other", "unknown"]

TOOL = {
  "name": "classify",
  "description": "Record the classification of the organisation behind a domain.",
  "input_schema": {
    "type": "object",
    "properties": {
      "company_name": {"type": "string", "description": "Best-guess organisation name, or '' if unknown"},
      "entity_type": {"type": "string", "enum": ENTITY},
      "industry": {"type": "string", "enum": INDUSTRY},
      "size": {"type": "string", "enum": ["micro", "small", "mid", "large", "unknown"]},
      "regulated": {"type": "boolean", "description": "Handles regulated data (health, payments, finance, government, education records)"},
      "confidence": {"type": "number", "description": "0-1 probability that entity_type AND industry are both correct"},
      "reason": {"type": "string", "description": "<=20 words citing the evidence used"}
    },
    "required": ["company_name", "entity_type", "industry", "size", "regulated", "confidence", "reason"]
  }
}

SYSTEM = """You classify the organisation that owns an internet domain, using ONLY the scan evidence given.
Rules:
- Internet/telecom carriers, ISPs and hosting/VPS/cloud providers are NOT 'business' prospects: use isp_telecom or hosting_cloud.
- If the domain looks like a parked page, a personal site, a test/dev throwaway, or evidence is too thin, use personal_or_parked or unknown.
- Prefer 'unknown' over a guess. A wrong label is worse than no label.
- confidence must be an honest probability; use <0.5 when you are mostly inferring from the domain name alone."""

def prompt(r):
    return json.dumps({k: r.get(k) for k in ["domain", "hosts", "titles", "cert_orgs", "net_orgs", "country", "n_ips"]},
                      ensure_ascii=False)

def valid(o):
    return (o.get("entity_type") in ENTITY and o.get("industry") in INDUSTRY
            and o.get("size") in ("micro", "small", "mid", "large", "unknown")
            and isinstance(o.get("confidence"), (int, float)) and 0 <= o["confidence"] <= 1)

def classify_one(client, r, retries=5):
    for i in range(retries):
        try:
            m = client.messages.create(model=MODEL, max_tokens=300, system=SYSTEM, tools=[TOOL],
                                       tool_choice={"type": "tool", "name": "classify"},
                                       messages=[{"role": "user", "content": prompt(r)}])
            out = next(b.input for b in m.content if b.type == "tool_use")
            if not valid(out):            # schema drift (e.g. merged fields) -> retry
                continue
            cost = m.usage.input_tokens * PRICE_IN + m.usage.output_tokens * PRICE_OUT
            return {"domain": r["domain"], **out, "in_tok": m.usage.input_tokens,
                    "out_tok": m.usage.output_tokens, "cost_usd": cost}
        except (anthropic.RateLimitError, anthropic.APIStatusError, anthropic.APIConnectionError) as e:
            time.sleep(2 ** i)
    return {"domain": r["domain"], "entity_type": "unknown", "industry": "unknown", "error": True}

def main(inp, outp, key_file, workers=8):
    client = anthropic.Anthropic(api_key=open(key_file, encoding="utf-8-sig").read().strip())
    rows = [json.loads(l) for l in open(inp)]
    done = set()
    if os.path.exists(outp):   # resume: keep only valid rows, redo the rest
        keep = [json.loads(l) for l in open(outp)]
        keep = [r for r in keep if not r.get("error") and valid(r)]
        with open(outp, "w") as f:
            for r in keep: f.write(json.dumps(r, ensure_ascii=False) + "\n")
        done = {r["domain"] for r in keep}
    todo = [r for r in rows if r["domain"] not in done]
    t0 = time.time()
    with open(outp, "a") as f, cf.ThreadPoolExecutor(workers) as ex:
        for i, res in enumerate(ex.map(lambda r: classify_one(client, r), todo)):
            f.write(json.dumps(res, ensure_ascii=False) + "\n")
            if i % 200 == 0: print(i, len(todo), round(time.time() - t0), "s", flush=True)

if __name__ == "__main__":
    main(*sys.argv[1:4], workers=int(sys.argv[4]) if len(sys.argv) > 4 else 8)
