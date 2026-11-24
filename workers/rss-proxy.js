// Cloudflare Worker — RSS CORS proxy for AntPod share page
// Deploy: Workers & Pages → Create Worker → paste this → Deploy
// URL: https://<name>.<account>.workers.dev?url=<rss-feed-url>
//
// Caches each feed 30 minutes in Cloudflare's edge cache.
// CORS-open (Access-Control-Allow-Origin: *) — RSS feeds are public anyway.

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET',
        },
      });
    }
    if (request.method !== 'GET') {
      return new Response('Method not allowed', { status: 405 });
    }

    const feedUrl = new URL(request.url).searchParams.get('url');
    if (!feedUrl) return new Response('Missing ?url= param', { status: 400 });

    let parsed;
    try { parsed = new URL(feedUrl); } catch {
      return new Response('Invalid URL', { status: 400 });
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return new Response('Only http/https URLs allowed', { status: 400 });
    }

    // Serve from edge cache when available
    const cache = caches.default;
    const cacheKey = new Request(feedUrl);
    const cached = await cache.match(cacheKey);
    if (cached) return corsWrap(cached);

    const upstream = await fetch(feedUrl, {
      headers: {
        'User-Agent': 'AntPod/1.0 (https://antpod.eu)',
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
      },
    });

    const body = await upstream.arrayBuffer();
    const ct = upstream.headers.get('Content-Type') || 'text/xml; charset=utf-8';
    const response = new Response(body, {
      status: upstream.status,
      headers: {
        'Content-Type': ct,
        'Cache-Control': 'public, max-age=1800',   // 30-min edge cache
        'Access-Control-Allow-Origin': '*',
      },
    });

    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};

function corsWrap(r) {
  const h = new Headers(r.headers);
  h.set('Access-Control-Allow-Origin', '*');
  return new Response(r.body, { status: r.status, headers: h });
}
