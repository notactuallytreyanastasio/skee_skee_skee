// The casino host's relay: the app talks to this, this talks to DeepSeek.
//
// A key in the app can be read out of any downloaded copy, so the key lives
// here. That makes this a public door to a paid API, and the limits are the
// point of the file: the model, the reply size and the conversation size are
// fixed here whatever the client asks for, and a daily cap bounds the bill.
// A request over a limit gets a 429 and the app's scripted host answers.
//
// Chat text is forwarded and never written down. Addresses are held in memory
// for the rate limit and dropped when their window ends.
import { createServer } from 'node:http';

const num = (name, fallback) => Number(process.env[name] ?? fallback);
export const limits = {
  perAddress: num('PER_ADDRESS', 40),
  windowMs: num('WINDOW_MS', 10 * 60 * 1000),
  perDay: num('PER_DAY', 5000),
  bodyBytes: 32 * 1024,
  messages: 60,
  systemChars: 8000,
  lineChars: 1000,
  replyTokens: 300,
};

/// What goes upstream, built from nothing the client can widen. Null if the
/// request isn't a haggle.
export function upstreamBody(body) {
  const list = body?.messages;
  if (!Array.isArray(list) || list.length < 2 || list.length > limits.messages) return null;
  if (list[0]?.role !== 'system') return null;
  for (const [i, m] of list.entries()) {
    if (typeof m?.content !== 'string') return null;
    if (i === 0 ? m.content.length > limits.systemChars : m.content.length > limits.lineChars) return null;
    if (i > 0 && m.role !== 'user' && m.role !== 'assistant') return null;
  }
  const temperature = Number.isFinite(body.temperature) ? Math.min(Math.max(body.temperature, 0), 1.3) : 0.9;
  return {
    model: 'deepseek-chat',
    messages: list.map(({ role, content }) => ({ role, content })),
    max_tokens: limits.replyTokens,
    temperature,
    ...(body.response_format?.type === 'json_object' ? { response_format: { type: 'json_object' } } : {}),
  };
}

export function makeLimiter(now = Date.now) {
  const seen = new Map();
  let day = '', today = 0;
  return (address) => {
    const t = now();
    const stamp = new Date(t).toISOString().slice(0, 10);
    if (stamp !== day) { day = stamp; today = 0; }
    if (today >= limits.perDay) return false;
    for (const [a, w] of seen) if (t - w.start >= limits.windowMs) seen.delete(a);
    const w = seen.get(address) ?? { start: t, count: 0 };
    if (w.count >= limits.perAddress) return false;
    w.count += 1; seen.set(address, w); today += 1;
    return true;
  };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0; const parts = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limits.bodyBytes) { reject(new Error('too large')); req.destroy(); } else parts.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(parts).toString('utf8')));
    req.on('error', reject);
  });
}

export function makeServer({ key, upstream = 'https://api.deepseek.com/chat/completions', allow = makeLimiter() }) {
  const send = (res, code, text, type = 'application/json') => {
    res.writeHead(code, { 'content-type': type }); res.end(text);
  };
  return createServer(async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') return send(res, 200, 'ok', 'text/plain');
    if (req.method !== 'POST' || req.url !== '/chat') return send(res, 404, '{"error":"not found"}');
    // Caddy sets this from its resolved client IP, overwriting anything the
    // client sent. X-Forwarded-For won't do: behind Cloudflare its last entry
    // is the edge, so every player on an edge would share one limit.
    const address = String(req.headers['x-real-ip'] ?? req.socket.remoteAddress);
    if (!allow(address)) return send(res, 429, '{"error":"slow down"}');
    let outgoing;
    try { outgoing = upstreamBody(JSON.parse(await readBody(req))); } catch { outgoing = null; }
    if (!outgoing) return send(res, 400, '{"error":"not a haggle"}');
    try {
      const r = await fetch(upstream, {
        method: 'POST',
        headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
        body: JSON.stringify(outgoing),
        signal: AbortSignal.timeout(25_000),
      });
      send(res, r.status, await r.text());
    } catch (e) {
      console.error('upstream failed:', e.name);
      send(res, 502, '{"error":"upstream"}');
    }
  });
}

if (process.argv[1]?.endsWith('relay.mjs')) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) { console.error('DEEPSEEK_API_KEY is not set'); process.exit(1); }
  const port = num('PORT', 8788);
  makeServer({ key }).listen(port, () => console.log(`relay on ${port}`));
}
