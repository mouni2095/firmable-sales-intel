-- per-IP stats; any honeypot-tagged service poisons the whole IP
CREATE OR REPLACE TABLE ipstat AS
SELECT ip, count(DISTINCT port) nports, bool_or(list_contains(tags, 'honeypot')) hp
FROM base GROUP BY ip;
