-- Evidence items: one row per (company, asset, signal) with a prior probability that the
-- signal reflects an actionable security need, discounted by attribution certainty.
CREATE OR REPLACE TABLE ev AS
WITH a AS (
  SELECT a.d, a.how, a.w, a.ip_tenants, r.*,
         a.w * CASE WHEN a.ip_tenants = 1 THEN 1.0 WHEN a.ip_tenants <= 3 THEN 0.5 ELSE 0.1 END AS attr_conf
  FROM attr a JOIN rsig r USING (rid)),
items AS (
  SELECT d, ip, port, attr_conf, how, ip_tenants, 'compromise' sig, CASE WHEN on_cloud THEN 0.5 ELSE 0.9 END p, coalesce(product, module) detail FROM a WHERE compromise
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'open_data', 0.60, module FROM a WHERE open_data
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'kev_ransomware', 0.60 * CASE WHEN list_bool_or(list_transform(list_filter(v, lambda x: x.kev AND x.ransomware = 'Known'), lambda x: x.verified)) THEN 1.0 WHEN distro_build THEN 0.3 ELSE 0.6 END,
      array_to_string(list_transform(list_filter(v, lambda x: x.kev AND x.ransomware = 'Known'), lambda x: x.cve), ',')
      FROM a WHERE list_bool_or(list_transform(v, lambda x: x.kev AND x.ransomware = 'Known'))
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'kev', (0.25 + 0.2 * list_max(list_transform(list_filter(v, lambda x: x.kev), lambda x: x.epss)))
         * CASE WHEN list_bool_or(list_transform(list_filter(v, lambda x: x.kev), lambda x: x.verified)) THEN 1.0
                WHEN distro_build THEN 0.3 ELSE 0.6 END,
      array_to_string(list_transform(list_filter(v, lambda x: x.kev), lambda x: x.cve)[1:5], ',')
      FROM a WHERE list_bool_or(list_transform(v, lambda x: x.kev))
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'rdp_exposed', 0.35, 'port ' || port FROM a WHERE rdp
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'smb_exposed', 0.40, 'port ' || port FROM a WHERE smb
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'telnet_exposed', 0.30, 'port ' || port FROM a WHERE telnet
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'vnc_exposed', 0.35, 'port ' || port FROM a WHERE vnc
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'exchange_onprem', 0.30, 'Exchange' FROM a WHERE exchange
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'db_exposed', 0.25, module FROM a WHERE db_exposed AND NOT open_data
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'ot_medical_exposed', 0.40, module FROM a WHERE ot_medical
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'end_of_life', 0.25, coalesce(product, module) FROM a WHERE eol
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'open_directory', 0.25, 'port ' || port FROM a WHERE open_dir
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'expired_cert', 0.10, 'port ' || port FROM a WHERE cert_expired
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'legacy_tls', 0.08, 'port ' || port FROM a WHERE old_tls
  UNION ALL SELECT d, ip, port, attr_conf, how, ip_tenants, 'self_signed_cert', 0.05, 'port ' || port FROM a WHERE cert_selfsigned
)
SELECT *, p * attr_conf AS p_eff FROM items;

-- Company rollup. need = noisy-OR over the strongest item per signal type (so 50 identical
-- expired certs don't outrank one confirmed compromise).
CREATE OR REPLACE TABLE company AS
WITH best AS (
  -- kev and kev_ransomware describe the same exposure: collapse into one group
  SELECT d, arg_max(sig, p_eff) sig, max(p_eff) p_eff, count(DISTINCT (ip, port)) n_assets, arg_max(detail, p_eff) detail
  FROM ev GROUP BY d, CASE WHEN sig LIKE 'kev%' THEN 'kev' ELSE sig END),
fp AS (
  SELECT a.d, count(DISTINCT r.ip) n_ips, count(DISTINCT (r.ip, r.port)) n_services,
         mode(r.country) country, mode(r.org) host_org,
         bool_or(r.has_securitytxt) securitytxt, avg((r.waf OR r.is_cdn)::INT) protected_share,
         max(a.ip_tenants) max_tenants, min(a.ip_tenants) min_tenants
  FROM attr a JOIN rsig r USING (rid) GROUP BY a.d)
SELECT fp.*,
  1 - exp(sum(ln(1 - b.p_eff))) AS need,
  count(b.sig) AS n_signal_types,
  list({'sig': b.sig, 'p': round(b.p_eff, 3), 'assets': b.n_assets, 'detail': b.detail} ORDER BY b.p_eff DESC) AS evidence
FROM fp LEFT JOIN best b USING (d)
GROUP BY ALL;

CREATE OR REPLACE TABLE company_v AS
SELECT c.*, v.suffix,
  CASE
    WHEN regexp_matches(lower(c.d), '\.(edu|ac\.[a-z]{2}|edu\.[a-z]{2})$') OR regexp_matches(lower(c.host_org), 'universi|college|school|institut|academ') THEN 'education'
    WHEN regexp_matches(lower(c.d), '\.(gov|mil|gov\.[a-z]{2}|gob\.[a-z]{2}|go\.[a-z]{2})$') THEN 'government'
    WHEN regexp_matches(lower(v.label), '(net|tel|telecom|host|hosting|server|dedicated|cloud|isp|broadband|fib(er|re)|cable|wifi|wireless|datacent|vps|internet|online|comm)')
      OR regexp_matches(lower(c.host_org), '(telecom|hosting|broadband|internet service|isp|datacenter|data center|communications|wireless|fiber|cable)') AND regexp_matches(lower(c.host_org), lower(v.label))
      THEN 'provider_likely'
    ELSE 'business_or_unknown' END AS segment_rule
FROM company c JOIN dvalid v USING (d)
WHERE v.reg IS NOT NULL;
