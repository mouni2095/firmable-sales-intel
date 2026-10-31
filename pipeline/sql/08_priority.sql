-- Combine need (scan evidence) with fit (LLM classification) into a ranked prospect list.
-- __CLS__ = path to classified.jsonl produced by llm/classify.py
CREATE OR REPLACE TABLE cls AS
SELECT domain AS d, company_name, entity_type, industry, size, regulated, confidence AS cls_conf, reason AS cls_reason
FROM read_json('__CLS__', format = 'newline_delimited', columns = {
  domain: 'VARCHAR', company_name: 'VARCHAR', entity_type: 'VARCHAR', industry: 'VARCHAR', size: 'VARCHAR',
  regulated: 'BOOLEAN', confidence: 'DOUBLE', reason: 'VARCHAR'});

CREATE OR REPLACE TABLE prospects AS
WITH j AS (
  SELECT c.*, k.* EXCLUDE (d),
    CASE k.entity_type WHEN 'business' THEN 1.0 WHEN 'government' THEN 0.8 WHEN 'education' THEN 0.7
                       WHEN 'nonprofit' THEN 0.6 ELSE 0 END AS type_fit,
    CASE k.size WHEN 'large' THEN 1.0 WHEN 'mid' THEN 1.0 WHEN 'small' THEN 0.75 WHEN 'micro' THEN 0.4 ELSE 0.6 END AS size_fit
  FROM company_v c JOIN cls k USING (d))
SELECT *,
  least(1.0, type_fit * size_fit * CASE WHEN regulated THEN 1.25 ELSE 1.0 END) AS fit,
  need * least(1.0, type_fit * size_fit * CASE WHEN regulated THEN 1.25 ELSE 1.0 END) AS priority,
  -- status: abstain rather than mislabel
  CASE WHEN entity_type IN ('isp_telecom','hosting_cloud','saas_platform') THEN 'excluded_provider'
       WHEN entity_type IN ('personal_or_parked') THEN 'excluded_not_a_business'
       WHEN entity_type = 'unknown' OR cls_conf < 0.5 THEN 'needs_review'
       WHEN max_tenants > 3 AND n_ips <= 2 THEN 'needs_review'        -- only seen on shared hosting
       ELSE 'ranked' END AS status,
  CASE WHEN list_bool_or(list_transform(evidence, lambda e: e.sig IN ('compromise','open_data') OR (e.sig LIKE 'kev%' AND e.p >= 0.4))) THEN 'P1 act now'
       WHEN need >= 0.5 THEN 'P2 strong need' ELSE 'P3 hygiene' END AS tier
FROM j;
