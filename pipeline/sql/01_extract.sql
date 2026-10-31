-- Firmable take-home, stage 1: stream the raw Shodan zstd NDJSON once and keep only the fields we need.
-- Placeholders: __SRC__ = raw file, __OUT__ = output folder
SET preserve_insertion_order = false;
SET memory_limit = '__MEM__';
SET temp_directory = '__OUT__/tmp';

CREATE OR REPLACE TEMP VIEW raw AS
SELECT * FROM read_json('__SRC__',
  format = 'newline_delimited', compression = 'zstd', ignore_errors = true,
  maximum_object_size = 67108864,
  columns = {
    ip_str: 'VARCHAR', port: 'INTEGER', transport: 'VARCHAR', timestamp: 'TIMESTAMP',
    org: 'VARCHAR', isp: 'VARCHAR', asn: 'VARCHAR', os: 'VARCHAR', product: 'VARCHAR',
    version: 'VARCHAR', devicetype: 'VARCHAR', data: 'VARCHAR',
    hostnames: 'VARCHAR[]', domains: 'VARCHAR[]', tags: 'VARCHAR[]', cpe23: 'VARCHAR[]',
    location: 'STRUCT(country_code VARCHAR, city VARCHAR)',
    _shodan: 'STRUCT(module VARCHAR)',
    cloud: 'STRUCT(provider VARCHAR)',
    http: 'STRUCT(status INTEGER, title VARCHAR, server VARCHAR, waf VARCHAR, securitytxt VARCHAR, components JSON)',
    ssl: 'STRUCT(versions VARCHAR[], cert STRUCT(expired BOOLEAN, expires VARCHAR, subject STRUCT(CN VARCHAR, O VARCHAR), issuer STRUCT(CN VARCHAR, O VARCHAR)))',
    ntlm: 'STRUCT(dns_domain_name VARCHAR, netbios_domain_name VARCHAR)',
    microsoft_exchange: 'STRUCT(name VARCHAR)',
    fortinet: 'STRUCT(device VARCHAR)',
    mongodb: 'STRUCT(authentication BOOLEAN)',
    redis: 'STRUCT(authentication_required BOOLEAN)',
    influxdb: 'STRUCT(databases VARCHAR[])',
    ftp: 'STRUCT(anonymous BOOLEAN)',
    open_dir: 'JSON',
    vulns: 'MAP(VARCHAR, STRUCT(cvss DOUBLE, epss DOUBLE, kev BOOLEAN, ransomware_campaign VARCHAR, verified BOOLEAN))'
  });

CREATE OR REPLACE TEMP VIEW slim AS
SELECT
  ip_str AS ip, port, transport, "timestamp" AS ts, org, isp, asn,
  location.country_code AS country, location.city AS city,
  _shodan.module AS module, product, trim(version) AS version, os, devicetype,
  hostnames, domains, tags, cpe23, cloud.provider AS cloud_provider,
  http.status AS http_status, left(http.title, 200) AS http_title, http.server AS http_server,
  http.waf AS http_waf, http.securitytxt IS NOT NULL AS has_securitytxt,
  json_keys(http.components) AS http_components,
  ssl.cert.subject.CN AS cert_cn, ssl.cert.subject.O AS cert_o, ssl.cert.issuer.O AS cert_issuer_o,
  ssl.cert.expired AS cert_expired, ssl.cert.expires AS cert_expires,
  ssl.cert.issuer.CN = ssl.cert.subject.CN AS cert_self_signed,
  ssl.versions AS tls_versions,
  ntlm.dns_domain_name AS ntlm_dns_domain, ntlm.netbios_domain_name AS ntlm_netbios_domain,
  microsoft_exchange.name AS exchange_name, fortinet.device AS fortinet_device,
  mongodb.authentication AS mongodb_auth, redis.authentication_required AS redis_auth,
  influxdb.databases AS influx_dbs, ftp.anonymous AS ftp_anonymous,
  open_dir IS NOT NULL AS open_dir,
  list_transform(map_entries(vulns), lambda e: {
      'cve': e.key, 'cvss': e.value.cvss, 'epss': e.value.epss,
      'kev': coalesce(e.value.kev, false), 'ransomware': e.value.ransomware_campaign,
      'verified': e.value.verified}) AS vulns,
  left(data, 300) AS banner_head
FROM raw;

COPY (SELECT * FROM slim)
TO '__OUT__/slim' (FORMAT parquet, COMPRESSION zstd, FILE_SIZE_BYTES '250MB', OVERWRITE true);
