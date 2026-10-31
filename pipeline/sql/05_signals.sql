-- Row-level, cleaned security signals. Noisy/inferred items are excluded deliberately (see NOTES).
CREATE OR REPLACE TABLE hp_ip AS SELECT ip FROM ipstat WHERE hp AND ip IS NOT NULL;

CREATE OR REPLACE TABLE rsig AS
SELECT rid, ip, port, module, product, ts, tags, country, org,
  list_contains(tags,'cdn') AS is_cdn,
  -- vulnerabilities: drop CVE-2023-44487 (inferred from HTTP/2 everywhere)
  list_filter(vulns, lambda v: v.cve <> 'CVE-2023-44487') AS v,
  -- version-inferred CVEs on distro builds are usually patched by backports
  list_has_any(list_transform(cpe23, lambda x: split_part(x, ':', 4)), ['canonical','centos','debian','redhat','rocky','almalinux','oracle','suse','amazon']) AS distro_build,
  cloud_provider IS NOT NULL AS on_cloud,
  list_contains(tags,'eol-product') OR list_contains(tags,'eol-os') AS eol,
  (port = 3389 OR module LIKE 'rdp%') AS rdp,
  (port = 445 OR module LIKE 'smb%') AS smb,
  (port = 23 OR module LIKE 'telnet%') AS telnet,
  module LIKE '%vnc%' AS vnc,
  ((module LIKE 'mongodb%' AND mongodb_auth = false) OR (module LIKE 'redis%' AND redis_auth = false)
     OR influx_dbs IS NOT NULL OR ftp_anonymous) AS open_data,
  open_dir,
  list_has_any(tags, ['compromised','c2','malware','doublepulsar'])
     OR product IN ('Sliver C2','Panda C2','Hak5 Cloud C2','Cobalt Strike Beacon','Mythic','PowerSploit',
                    'Metasploit','GoPhish','XtremeRAT trojan','Interactsh SMTP Server')
     OR list_has_any(influx_dbs, ['pwn','exploit','hacked','README','readme']) AS compromise,
  cert_expired AND NOT list_contains(tags,'cdn') AS cert_expired,
  cert_self_signed AND port IN (443, 8443, 993, 995, 465, 587) AS cert_selfsigned,
  (list_contains(tls_versions,'TLSv1') OR list_contains(tls_versions,'SSLv3') OR list_contains(tls_versions,'SSLv2')) AS old_tls,
  exchange_name IS NOT NULL AS exchange,
  (fortinet_device IS NOT NULL OR list_contains(tags,'vpn')) AS edge_device,
  list_contains(tags,'database') AS db_exposed,
  list_contains(tags,'ics') OR list_contains(tags,'medical') AS ot_medical,
  has_securitytxt, http_waf IS NOT NULL AS waf
FROM base
WHERE ip NOT IN (SELECT ip FROM hp_ip);
