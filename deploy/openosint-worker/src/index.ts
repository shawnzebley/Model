/**
 * OSINT MCP server on Cloudflare Workers — Streamable HTTP transport.
 *
 * Exists so claude.ai chat and Cowork can run these lookups: both connect to
 * MCP servers from Anthropic's infrastructure and can only reach a public
 * HTTPS endpoint, so a local stdio server is not an option there.
 *
 * Stateless by design. The spec makes session ids optional, and skipping them
 * means no Durable Object and no storage — every request stands alone.
 * Requests are answered with application/json rather than SSE, which the
 * Streamable HTTP spec permits and which keeps this a single fetch handler.
 */

import {
  Env,
  searchAbuseipdb,
  searchDns,
  searchIp,
  searchShodan,
  searchSubdomains,
  searchVirustotal,
  searchWhois,
} from "./tools";

const PROTOCOL_VERSION = "2025-06-18";
const SERVER_INFO = { name: "openosint-worker", version: "1.0.0" };

type Json = Record<string, any>;

const TOOLS = [
  {
    name: "search_dns",
    description:
      "Enumerate DNS records for a domain (A, AAAA, MX, NS, TXT, SOA) over DNS-over-HTTPS, and flag email-security gaps: missing or permissive SPF, missing or unenforced DMARC. No credentials required.",
    inputSchema: {
      type: "object",
      properties: { domain: { type: "string", description: "Domain name, e.g. example.com" } },
      required: ["domain"],
    },
  },
  {
    name: "search_whois",
    description:
      "Look up domain registration via RDAP (the JSON successor to port-43 WHOIS): registrar, creation and expiry dates, nameservers, and status codes. No credentials required.",
    inputSchema: {
      type: "object",
      properties: { domain: { type: "string", description: "Domain name, e.g. example.com" } },
      required: ["domain"],
    },
  },
  {
    name: "search_subdomains",
    description:
      "Discover subdomains from certificate transparency logs (crt.sh). Shows certificates that were issued, which may include hosts that no longer resolve. No credentials required.",
    inputSchema: {
      type: "object",
      properties: { domain: { type: "string", description: "Domain name, e.g. example.com" } },
      required: ["domain"],
    },
  },
  {
    name: "search_ip",
    description:
      "Geolocation, ASN, org, and reverse hostname for an IP address via ipinfo.io. Works without a token at a reduced rate limit; richer with IPINFO_TOKEN set.",
    inputSchema: {
      type: "object",
      properties: { ip: { type: "string", description: "IPv4 or IPv6 address" } },
      required: ["ip"],
    },
  },
  {
    name: "search_abuseipdb",
    description:
      "Abuse reputation for an IP address from AbuseIPDB: confidence score, report count, ISP, and usage type. Requires ABUSEIPDB_API_KEY.",
    inputSchema: {
      type: "object",
      properties: { ip: { type: "string", description: "IPv4 or IPv6 address" } },
      required: ["ip"],
    },
  },
  {
    name: "search_virustotal",
    description:
      "VirusTotal reputation for a domain or IP address: engine verdict counts, reputation score, AS owner. Requires VIRUSTOTAL_API_KEY.",
    inputSchema: {
      type: "object",
      properties: { target: { type: "string", description: "Domain name or IP address" } },
      required: ["target"],
    },
  },
  {
    name: "search_shodan",
    description:
      "Shodan host record for an IP address: open ports, detected services, hostnames, and reported CVEs. Requires SHODAN_API_KEY.",
    inputSchema: {
      type: "object",
      properties: { ip: { type: "string", description: "IPv4 or IPv6 address" } },
      required: ["ip"],
    },
  },
];

async function dispatch(name: string, args: Json, env: Env): Promise<string> {
  switch (name) {
    case "search_dns": return searchDns(String(args.domain ?? ""));
    case "search_whois": return searchWhois(String(args.domain ?? ""));
    case "search_subdomains": return searchSubdomains(String(args.domain ?? ""));
    case "search_ip": return searchIp(String(args.ip ?? ""), env);
    case "search_abuseipdb": return searchAbuseipdb(String(args.ip ?? ""), env);
    case "search_virustotal": return searchVirustotal(String(args.target ?? ""), env);
    case "search_shodan": return searchShodan(String(args.ip ?? ""), env);
    default: throw new Error(`Unknown tool: ${name}`);
  }
}

const json = (body: Json, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const rpcError = (id: any, code: number, message: string) =>
  json({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

/**
 * Constant-time compare, so a token cannot be recovered by timing repeated
 * requests. Length is allowed to leak; the contents are not.
 */
function tokenMatches(given: string, expected: string): boolean {
  if (given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ status: "ok", server: SERVER_INFO.name, tools: TOOLS.length });
    }

    if (url.pathname !== "/mcp") {
      return json({ error: "Not found. The MCP endpoint is at /mcp." }, 404);
    }

    // GET /mcp would open a server-initiated SSE stream. This server never
    // initiates anything, so declining is correct and spec-permitted.
    if (request.method === "GET") {
      return new Response("This server does not offer an SSE stream. POST JSON-RPC to /mcp.", {
        status: 405,
        headers: { Allow: "POST" },
      });
    }
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "POST" } });
    }

    if (!env.MCP_TOKEN) {
      return json(
        { error: "Server misconfigured: MCP_TOKEN is not set. Run: wrangler secret put MCP_TOKEN" },
        500,
      );
    }

    const auth = request.headers.get("Authorization") ?? "";
    const given = auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
    if (!given || !tokenMatches(given, env.MCP_TOKEN)) {
      // Auth is checked before parsing, so an unauthenticated caller cannot
      // even enumerate tool names.
      return new Response(JSON.stringify({ error: "Invalid or missing bearer token." }), {
        status: 401,
        headers: { "Content-Type": "application/json", "WWW-Authenticate": "Bearer" },
      });
    }

    let parsed: unknown;
    try {
      parsed = await request.json();
    } catch {
      return rpcError(null, -32700, "Parse error: body is not valid JSON");
    }

    // Batches are legal JSON-RPC. Notifications (no id) get no reply, so an
    // all-notification batch correctly produces 202 with an empty body.
    const batch = Array.isArray(parsed);
    const messages = (batch ? parsed : [parsed]) as Json[];
    const replies: Json[] = [];

    for (const msg of messages) {
      const reply = await handle(msg, env);
      if (reply) replies.push(reply);
    }

    if (!replies.length) return new Response(null, { status: 202 });
    return json(batch ? replies : replies[0]);
  },
};

async function handle(msg: Json, env: Env): Promise<Json | null> {
  const { id, method, params } = msg ?? {};
  const isNotification = id === undefined || id === null;

  switch (method) {
    case "initialize":
      return {
        jsonrpc: "2.0",
        id,
        result: {
          // Echo the client's version when we understand it, so a client on an
          // older spec revision is not forced to downgrade the whole session.
          protocolVersion:
            typeof params?.protocolVersion === "string" ? params.protocolVersion : PROTOCOL_VERSION,
          capabilities: { tools: { listChanged: false } },
          serverInfo: SERVER_INFO,
        },
      };

    case "notifications/initialized":
    case "notifications/cancelled":
      return null;

    case "ping":
      return { jsonrpc: "2.0", id, result: {} };

    case "tools/list":
      return { jsonrpc: "2.0", id, result: { tools: TOOLS } };

    case "tools/call": {
      const name = params?.name;
      const args = params?.arguments ?? {};
      if (typeof name !== "string") {
        return { jsonrpc: "2.0", id, error: { code: -32602, message: "params.name is required" } };
      }
      try {
        const text = await dispatch(name, args, env);
        return { jsonrpc: "2.0", id, result: { content: [{ type: "text", text }] } };
      } catch (e: any) {
        // A tool failure is a result with isError, not a protocol error — the
        // model should see what went wrong and be able to carry on.
        return {
          jsonrpc: "2.0",
          id,
          result: { content: [{ type: "text", text: `Tool error: ${e?.message ?? e}` }], isError: true },
        };
      }
    }

    default:
      if (isNotification) return null;
      return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } };
  }
}
