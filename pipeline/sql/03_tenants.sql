-- generic machine-name hosts under a provider domain (vps123.x, srv01.x, node-5.x, s123.x)
CREATE OR REPLACE MACRO is_generic(h, d) AS
  regexp_matches(split_part(h, '.', 1), '^(vps|vds|srv|server|node|host|hosting|vm|cloud|static|s|web|cp|mx|ns|dedi|dedicated|box|compute|instance|ded)[-_]?\d+')
  OR regexp_matches(split_part(h, '.', 1), '^[a-z]{0,4}\d{3,}[a-z0-9-]*$');

CREATE OR REPLACE TABLE dstat2 AS
SELECT d, count(DISTINCT ip) n_ips, count(DISTINCT h) n_hosts,
       avg(rdns::INT) rdns_frac, avg(is_generic(h,d)::INT) generic_frac
FROM rh WHERE d IS NOT NULL GROUP BY d;

CREATE OR REPLACE TABLE infra_domain AS
SELECT d, CASE WHEN n_ips > 300 THEN 'many_ips' WHEN rdns_frac > 0.5 THEN 'rdns'
               WHEN generic_frac > 0.5 AND n_ips >= 5 THEN 'generic_hosts' END AS why
FROM dstat2
WHERE n_ips > 300 OR rdns_frac > 0.5 OR (generic_frac > 0.5 AND n_ips >= 5)
UNION ALL SELECT unnest(['hotmail.com','live.net','office365.com','outlook.com','certfallback.com','default.com',
  'park-my-domain.net','cloudflare.net','cloudflare.com','herokuapp.com','azurewebsites.net','github.io','wpengine.com',
  'shopify.com','myshopify.com','squarespace.com','wixsite.com','netlify.app','vercel.app','googlehosted.com']), 'saas_shared';

-- named (non-rDNS) hosts that belong to a non-infra domain = tenant evidence
CREATE OR REPLACE TABLE tenant AS
SELECT DISTINCT r.rid, r.ip, r.d
FROM rh r LEFT JOIN infra_domain i USING (d)
WHERE r.d IS NOT NULL AND i.d IS NULL AND NOT r.rdns;

-- how many distinct tenant domains share each IP (shared hosting dilutes attribution)
CREATE OR REPLACE TABLE ip_tenancy AS SELECT ip, count(DISTINCT d) n_tenants FROM tenant GROUP BY ip;
