CREATE OR REPLACE MACRO is_rdns(h) AS
  regexp_matches(h, '(\d{1,3}[-.x_]){3}\d{1,3}')
  OR regexp_matches(h, '^(ec2|ip|pool|host|dynamic|static|cpe|dsl|adsl|cable|customer|syn|modemcable|dhcp|ppp|broadband|client|user|unassigned|server-\d|ows)[-.\d]')
  OR regexp_matches(h, '\d{8,}');

-- base table with stable row id
CREATE OR REPLACE TABLE base AS SELECT row_number() OVER () AS rid, * FROM s;

-- every (row, hostname, registrable domain) triple
CREATE OR REPLACE TABLE rh AS
SELECT rid, ip, h,
       list_filter(domains, lambda d: h = d OR suffix(h, '.' || d))[1] AS d,
       is_rdns(h) AS rdns
FROM (SELECT rid, ip, domains, unnest(hostnames) AS h FROM base WHERE len(hostnames) > 0);

-- domain stats
CREATE OR REPLACE TABLE dstat AS
SELECT d, count(DISTINCT ip) AS n_ips, count(DISTINCT h) AS n_hosts, avg(rdns::INT) AS rdns_frac
FROM rh WHERE d IS NOT NULL GROUP BY d;
