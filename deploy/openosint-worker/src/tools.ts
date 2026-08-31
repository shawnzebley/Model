/**
 * OSINT lookups implemented as plain HTTPS calls, so they run on Workers.
 *
 * OpenOSINT's Python tools shell out to binaries (sherlock, sublist3r) and do
 * raw UDP DNS, neither of which exists in the Workers runtime. These are
 * reimplementations over HTTP equivalents:
 *
 *   DNS       -> DNS-over-HTTPS (cloudflare-dns.com)
 *   WHOIS     -> RDAP, the JSON protocol that replaced port-43 WHOIS
 *   subdomain -> certificate transparency logs (crt.sh)
 *
 * Every function returns display text and never throws — a failed lookup is a
 * reported result, not a protocol error.
 */

export interface Env {
  /** Bearer token clients must present. Set with: wrangler secret put MCP_TOKEN */
  MCP_TOKEN: string;
  IPINFO_TOKEN?: string;
  ABUSEIPDB_API_KEY?: string;
  VIRUSTOTAL_API_KEY?: string;
  SHODAN_API_KEY?: string;
}

const TIMEOUT_MS = 15_000;

// crt.sh answers a certificate-transparency query by scanning an index of
// billions of certificates, and routinely takes far longer than the other
// upstreams. A live run against the deployed Worker timed out at 15s on
// anthropic.com, so it gets its own budget rather than dragging the shared one
// up for endpoints that should answer fast.
const CRTSH_TIMEOUT_MS = 45_000;

const UA = "openosint-worker/1.0";

async function getJSON(
  url: string,
  headers: Record<string, string> = {},
  opts: { authenticated?: boolean; timeoutMs?: number } = {},
): Promise<{ ok: true; data: any } | { ok: false; error: string }> {
  const timeoutMs = opts.timeoutMs ?? TIMEOUT_MS;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": UA, Accept: "application/json", ...headers },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) {
      // On a call that actually sent credentials, 401/403 almost always means
      // the key is wrong, which is worth saying plainly rather than surfacing a
      // bare status code. On a keyless endpoint it cannot mean that, and saying
      // so sends the reader hunting for a key that does not exist — an
      // intercepting proxy, a WAF, or an egress policy is the likelier cause.
      // Credentials travel by header for some upstreams and by query string for
      // others, so the call site states this rather than it being sniffed here.
      if (res.status === 401 || res.status === 403) {
        return {
          ok: false,
          error: opts.authenticated
            ? `upstream rejected the API key (HTTP ${res.status})`
            : `upstream refused the request (HTTP ${res.status}); this endpoint takes no API key, so a proxy, WAF, or network policy is the likely cause`,
        };
      }
      if (res.status === 404) return { ok: false, error: "not found upstream (HTTP 404)" };
      if (res.status === 429) return { ok: false, error: "rate limited upstream (HTTP 429)" };
      return { ok: false, error: `upstream returned HTTP ${res.status}` };
    }
    return { ok: true, data: await res.json() };
  } catch (e: any) {
    const msg = e?.name === "TimeoutError" ? `timed out after ${timeoutMs / 1000}s` : String(e?.message ?? e);
    return { ok: false, error: msg };
  }
}

/** Reject inputs that would let a caller steer a request somewhere unintended. */
function cleanDomain(input: string): string | null {
  const d = input.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
  return /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(d) ? d : null;
}

function cleanIP(input: string): string | null {
  const ip = input.trim();
  const v4 = /^(\d{1,3}\.){3}\d{1,3}$/;
  if (v4.test(ip)) return ip.split(".").every((o) => Number(o) <= 255) ? ip : null;
  return /^[0-9a-fA-F:]+$/.test(ip) && ip.includes(":") ? ip : null;
}

// ── DNS, over DoH ─────────────────────────────────────────────────────────────

/**
 * Returns null when the query itself failed, [] when it succeeded with no
 * records. Collapsing those two into [] would let a network failure be
 * reported as "no SPF record" — a confident, alarming, and wrong finding.
 */
async function doh(name: string, type: string): Promise<string[] | null> {
  const url = `https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(name)}&type=${type}`;
  const r = await getJSON(url, { Accept: "application/dns-json" });
  if (!r.ok) return null;
  // NXDOMAIN (3) is a real answer: the name does not exist.
  if (typeof r.data?.Status === "number" && r.data.Status !== 0 && r.data.Status !== 3) return null;
  return (r.data?.Answer ?? [])
    .filter((a: any) => a?.data)
    .map((a: any) => String(a.data).replace(/^"|"$/g, ""));
}

export async function searchDns(domain: string): Promise<string> {
  const d = cleanDomain(domain);
  if (!d) return `Error: '${domain}' is not a valid domain name.`;

  const [a, aaaa, mx, ns, txt, soa, dmarc] = await Promise.all([
    doh(d, "A"), doh(d, "AAAA"), doh(d, "MX"), doh(d, "NS"),
    doh(d, "TXT"), doh(d, "SOA"), doh(`_dmarc.${d}`, "TXT"),
  ]);

  // If nothing resolved at all, the resolver is unreachable — say so rather
  // than reporting an absence of records we never actually observed.
  if ([a, aaaa, mx, ns, txt, soa, dmarc].every((r) => r === null)) {
    return `[DNS] Domain: ${d}\nLookup failed: could not reach the DNS-over-HTTPS resolver. No conclusions can be drawn about this domain's records.`;
  }

  const out = [`[DNS] Domain: ${d}`];
  if (a?.length) out.push(`[DNS] A: ${a.join(", ")}`);
  if (aaaa?.length) out.push(`[DNS] AAAA: ${aaaa.join(", ")}`);
  if (ns?.length) out.push(`[DNS] NS: ${ns.join(", ")}`);
  if (soa?.length) out.push(`[DNS] SOA: ${soa[0]}`);
  if (mx?.length) out.push(`[DNS] MX: ${mx.join(" | ")}`);

  // Only claim SPF is absent when the TXT query actually succeeded.
  const spf = txt?.find((t) => t.toLowerCase().startsWith("v=spf1"));
  if (spf) {
    out.push(`[DNS] SPF: ${spf}`);
    // A trailing "?all" or "+all" accepts mail from anywhere, which defeats
    // the point of publishing SPF at all.
    if (/[?+]all\s*$/.test(spf)) out.push(`[!] SPF ends in a permissive qualifier — it does not restrict senders.`);
  } else if (txt === null) {
    out.push(`[DNS] SPF: not checked — the TXT lookup failed.`);
  } else {
    out.push(`[!] No SPF record — anyone can spoof email from this domain.`);
  }

  const dm = dmarc?.find((t) => t.toLowerCase().startsWith("v=dmarc1"));
  if (dm) {
    out.push(`[DNS] DMARC: ${dm}`);
    if (/p=none/i.test(dm)) out.push(`[!] DMARC policy is p=none — reports only, nothing is enforced.`);
  } else if (dmarc === null) {
    out.push(`[DNS] DMARC: not checked — the lookup failed.`);
  } else {
    out.push(`[!] No DMARC record.`);
  }

  const other = (txt ?? []).filter((t) => t !== spf);
  if (other.length) out.push(`[DNS] TXT (other): ${other.slice(0, 8).join(" | ")}`);

  // A partial failure must not read like a complete picture.
  const failed = [a, aaaa, mx, ns, txt, soa, dmarc].filter((r) => r === null).length;
  if (failed) out.push(`\nNote: ${failed} of 7 record lookups failed; this result is incomplete.`);

  return out.join("\n");
}

// ── WHOIS, over RDAP ──────────────────────────────────────────────────────────

export async function searchWhois(domain: string): Promise<string> {
  const d = cleanDomain(domain);
  if (!d) return `Error: '${domain}' is not a valid domain name.`;

  // rdap.org redirects to whichever registry is authoritative for the TLD.
  const r = await getJSON(`https://rdap.org/domain/${encodeURIComponent(d)}`);
  if (!r.ok) return `[WHOIS] ${d}\nLookup failed: ${r.error}`;

  const out = [`[WHOIS] Domain: ${d}`];
  const data = r.data;

  for (const ev of data?.events ?? []) {
    if (ev?.eventAction && ev?.eventDate) {
      out.push(`[WHOIS] ${ev.eventAction}: ${ev.eventDate}`);
    }
  }

  const registrar = (data?.entities ?? []).find((e: any) => (e?.roles ?? []).includes("registrar"));
  if (registrar) {
    // vCard layout: ["vcard", [["fn", {}, "text", "Name"], ...]]
    const fn = (registrar?.vcardArray?.[1] ?? []).find((f: any) => f?.[0] === "fn");
    if (fn?.[3]) out.push(`[WHOIS] Registrar: ${fn[3]}`);
  }

  const ns = (data?.nameservers ?? []).map((n: any) => n?.ldhName).filter(Boolean);
  if (ns.length) out.push(`[WHOIS] Nameservers: ${ns.join(", ")}`);

  if (data?.status?.length) out.push(`[WHOIS] Status: ${data.status.join(", ")}`);

  return out.length > 1 ? out.join("\n") : `[WHOIS] ${d}\nNo RDAP data returned.`;
}

// ── Subdomains, via certificate transparency ──────────────────────────────────

export async function searchSubdomains(domain: string): Promise<string> {
  const d = cleanDomain(domain);
  if (!d) return `Error: '${domain}' is not a valid domain name.`;

  const r = await getJSON(
    `https://crt.sh/?q=%25.${encodeURIComponent(d)}&output=json`,
    {},
    { timeoutMs: CRTSH_TIMEOUT_MS },
  );
  if (!r.ok) return `[SUBDOMAINS] ${d}\nLookup failed: ${r.error}\n(crt.sh is frequently slow or down; retry later.)`;

  const names = new Set<string>();
  for (const row of Array.isArray(r.data) ? r.data : []) {
    for (const n of String(row?.name_value ?? "").split("\n")) {
      const v = n.trim().toLowerCase();
      // Wildcards are noise for enumeration, and CT logs include the apex too.
      if (v && !v.startsWith("*.") && v.endsWith(`.${d}`)) names.add(v);
    }
  }

  if (!names.size) return `[SUBDOMAINS] ${d}\nNo subdomains found in certificate transparency logs.`;

  const sorted = [...names].sort();
  const shown = sorted.slice(0, 200);
  const out = [`[SUBDOMAINS] ${d} — ${sorted.length} found in CT logs`, ...shown.map((s) => `  • ${s}`)];
  if (sorted.length > shown.length) out.push(`  … and ${sorted.length - shown.length} more`);
  out.push(`\nNote: CT logs show certificates issued, not hosts currently live.`);
  return out.join("\n");
}

// ── IP intelligence ───────────────────────────────────────────────────────────

export async function searchIp(ip: string, env: Env): Promise<string> {
  const v = cleanIP(ip);
  if (!v) return `Error: '${ip}' is not a valid IP address.`;

  const q = env.IPINFO_TOKEN ? `?token=${encodeURIComponent(env.IPINFO_TOKEN)}` : "";
  const r = await getJSON(`https://ipinfo.io/${encodeURIComponent(v)}/json${q}`, {}, {
    // ipinfo serves anonymous callers too; only a present token can be rejected.
    authenticated: Boolean(env.IPINFO_TOKEN),
  });
  if (!r.ok) return `[IP] ${v}\nLookup failed: ${r.error}`;

  const d = r.data;
  const out = [`[IP] Address: ${v}`];
  for (const [label, key] of [
    ["Hostname", "hostname"], ["Org", "org"], ["City", "city"],
    ["Region", "region"], ["Country", "country"], ["Timezone", "timezone"],
  ] as const) {
    if (d?.[key]) out.push(`[IP] ${label}: ${d[key]}`);
  }
  if (!env.IPINFO_TOKEN) out.push(`\nNote: no IPINFO_TOKEN set — using the anonymous tier, which is rate limited and returns less detail.`);
  return out.join("\n");
}

export async function searchAbuseipdb(ip: string, env: Env): Promise<string> {
  const v = cleanIP(ip);
  if (!v) return `Error: '${ip}' is not a valid IP address.`;
  if (!env.ABUSEIPDB_API_KEY) return missingKey("search_abuseipdb", "ABUSEIPDB_API_KEY", "abuseipdb.com");

  const r = await getJSON(
    `https://api.abuseipdb.com/api/v2/check?ipAddress=${encodeURIComponent(v)}&maxAgeInDays=90`,
    { Key: env.ABUSEIPDB_API_KEY },
    { authenticated: true },
  );
  if (!r.ok) return `[ABUSEIPDB] ${v}\nLookup failed: ${r.error}`;

  const d = r.data?.data ?? {};
  return [
    `[ABUSEIPDB] Address: ${v}`,
    `[ABUSEIPDB] Abuse confidence: ${d.abuseConfidenceScore ?? "?"}%`,
    `[ABUSEIPDB] Total reports (90d): ${d.totalReports ?? 0}`,
    `[ABUSEIPDB] Distinct reporters: ${d.numDistinctUsers ?? 0}`,
    `[ABUSEIPDB] ISP: ${d.isp ?? "unknown"}`,
    `[ABUSEIPDB] Usage type: ${d.usageType ?? "unknown"}`,
    `[ABUSEIPDB] Country: ${d.countryCode ?? "unknown"}`,
    d.isWhitelisted ? `[ABUSEIPDB] Whitelisted upstream.` : "",
    d.lastReportedAt ? `[ABUSEIPDB] Last reported: ${d.lastReportedAt}` : "",
  ].filter(Boolean).join("\n");
}

export async function searchVirustotal(target: string, env: Env): Promise<string> {
  if (!env.VIRUSTOTAL_API_KEY) return missingKey("search_virustotal", "VIRUSTOTAL_API_KEY", "virustotal.com");

  const ip = cleanIP(target);
  const domain = ip ? null : cleanDomain(target);
  if (!ip && !domain) return `Error: '${target}' is not a valid domain or IP address.`;

  const path = ip ? `ip_addresses/${encodeURIComponent(ip)}` : `domains/${encodeURIComponent(domain!)}`;
  const r = await getJSON(`https://www.virustotal.com/api/v3/${path}`, { "x-apikey": env.VIRUSTOTAL_API_KEY }, { authenticated: true });
  if (!r.ok) return `[VIRUSTOTAL] ${ip ?? domain}\nLookup failed: ${r.error}`;

  const attr = r.data?.data?.attributes ?? {};
  const stats = attr.last_analysis_stats ?? {};
  const out = [
    `[VIRUSTOTAL] Target: ${ip ?? domain}`,
    `[VIRUSTOTAL] Malicious: ${stats.malicious ?? 0} | Suspicious: ${stats.suspicious ?? 0} | Harmless: ${stats.harmless ?? 0} | Undetected: ${stats.undetected ?? 0}`,
  ];
  if (attr.reputation !== undefined) out.push(`[VIRUSTOTAL] Reputation: ${attr.reputation}`);
  if (attr.as_owner) out.push(`[VIRUSTOTAL] AS owner: ${attr.as_owner}`);
  if (attr.registrar) out.push(`[VIRUSTOTAL] Registrar: ${attr.registrar}`);
  if ((stats.malicious ?? 0) > 0) out.push(`[!] Flagged malicious by ${stats.malicious} engine(s).`);
  return out.join("\n");
}

export async function searchShodan(ip: string, env: Env): Promise<string> {
  const v = cleanIP(ip);
  if (!v) return `Error: '${ip}' is not a valid IP address.`;
  if (!env.SHODAN_API_KEY) return missingKey("search_shodan", "SHODAN_API_KEY", "shodan.io");

  const r = await getJSON(
    `https://api.shodan.io/shodan/host/${encodeURIComponent(v)}?key=${encodeURIComponent(env.SHODAN_API_KEY)}`,
    {},
    { authenticated: true },
  );
  if (!r.ok) {
    if (r.error.includes("404")) return `[SHODAN] ${v}\nNo information available for this IP.`;
    return `[SHODAN] ${v}\nLookup failed: ${r.error}`;
  }

  const d = r.data;
  const out = [`[SHODAN] Address: ${v}`];
  if (d?.org) out.push(`[SHODAN] Org: ${d.org}`);
  if (d?.os) out.push(`[SHODAN] OS: ${d.os}`);
  if (d?.country_name) out.push(`[SHODAN] Location: ${[d.city, d.country_name].filter(Boolean).join(", ")}`);
  if (d?.ports?.length) out.push(`[SHODAN] Open ports: ${d.ports.join(", ")}`);
  if (d?.hostnames?.length) out.push(`[SHODAN] Hostnames: ${d.hostnames.join(", ")}`);
  if (d?.vulns?.length) out.push(`[!] Reported CVEs: ${d.vulns.join(", ")}`);
  out.push(`\nData provided by Shodan (shodan.io).`);
  return out.join("\n");
}

function missingKey(tool: string, envVar: string, provider: string): string {
  return [
    `Error: ${tool} needs ${envVar}, which is not set on this deployment.`,
    `Get a key from ${provider}, then:`,
    `  wrangler secret put ${envVar}`,
    `Other tools are unaffected.`,
  ].join("\n");
}
