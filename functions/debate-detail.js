// Server-rendered social preview for /debate-detail?id=…
// Chat apps do not execute the page JavaScript, so they need title metadata
// in the initial HTML response rather than the browser-rendered page.

const SUPABASE_URL = 'https://sczgelfdrlkenlshthsa.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_cJv4iU4Aod6RVY8se0TiZg_oXS0Ukdk';

const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
}[character]));

async function getDebatePreview(id) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return null;
  const endpoint = new URL('/rest/v1/debates', SUPABASE_URL);
  endpoint.searchParams.set('id', `eq.${id}`);
  endpoint.searchParams.set('status', 'neq.hidden');
  endpoint.searchParams.set('select', 'title,category');
  const response = await fetch(endpoint, {
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${SUPABASE_PUBLISHABLE_KEY}` },
    cf: { cacheTtl: 60, cacheEverything: true }
  });
  if (!response.ok) return null;
  const rows = await response.json();
  return rows?.[0] || null;
}

export async function onRequestGet(context) {
  const url = new URL(context.request.url);
  const assetUrl = new URL(context.request.url);
  assetUrl.pathname = '/debate-detail.html';
  const assetResponse = await context.env.ASSETS.fetch(new Request(assetUrl, context.request));
  const debate = await getDebatePreview(url.searchParams.get('id') || '').catch(() => null);
  if (!debate || !assetResponse.headers.get('content-type')?.includes('text/html')) return assetResponse;

  const title = `${debate.title} — OnDebate`;
  const description = `${debate.category} 토론 · OnDebate에서 의견을 나눠보세요.`;
  const metadata = `\n    <meta property="og:type" content="website" />\n    <meta property="og:site_name" content="OnDebate" />\n    <meta property="og:title" content="${escapeHtml(title)}" />\n    <meta property="og:description" content="${escapeHtml(description)}" />\n    <meta property="og:url" content="${escapeHtml(url.href)}" />\n    <meta name="twitter:card" content="summary" />\n    <meta name="twitter:title" content="${escapeHtml(title)}" />\n    <meta name="twitter:description" content="${escapeHtml(description)}" />`;
  const html = (await assetResponse.text())
    .replace(/<title>[\s\S]*?<\/title>/i, `<title>${escapeHtml(title)}</title>`)
    .replace('</head>', `${metadata}\n  </head>`);
  const headers = new Headers(assetResponse.headers);
  headers.set('content-type', 'text/html; charset=UTF-8');
  headers.set('cache-control', 'public, max-age=300');
  headers.delete('content-length');
  headers.delete('content-encoding');
  return new Response(html, { status: assetResponse.status, headers });
}

