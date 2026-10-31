-- Attribute rows to companies.
--  direct  : the row itself names a tenant domain (cert/hostname)            weight 1/n_domains_on_row
--  same_ip : row has no name, but its IP serves exactly one tenant domain  weight 0.7
-- Shared hosting (IP with >3 tenants) and CDN edges do NOT carry exposure to the tenant.
CREATE OR REPLACE TABLE attr AS
WITH direct AS (
  SELECT t.rid, t.d, 'direct' AS how, 1.0 / count(*) OVER (PARTITION BY t.rid) AS w
  FROM tenant t),
single AS (SELECT ip, any_value(d) d FROM tenant GROUP BY ip HAVING count(DISTINCT d) = 1),
same_ip AS (
  SELECT r.rid, s.d, 'same_ip' AS how, 0.7 AS w
  FROM rsig r JOIN single s USING (ip)
  WHERE r.rid NOT IN (SELECT rid FROM tenant) AND NOT r.is_cdn)
SELECT a.*, coalesce(it.n_tenants, 1) AS ip_tenants
FROM (SELECT * FROM direct UNION ALL SELECT * FROM same_ip) a
JOIN rsig r USING (rid)
LEFT JOIN ip_tenancy it ON it.ip = r.ip;
