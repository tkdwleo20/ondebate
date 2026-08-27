// Deploy as a Supabase Edge Function named "kakao-token" with JWT verification disabled.
// Required secrets: KAKAO_REST_API_KEY, KAKAO_CLIENT_SECRET, SITE_URL=https://ondebate.co.kr
// Optional: ADDITIONAL_SITE_URLS=https://ondebate.pages.dev,https://www.ondebate.co.kr
const siteUrls = [
  Deno.env.get('SITE_URL') ?? '',
  ...(Deno.env.get('ADDITIONAL_SITE_URLS') ?? '').split(','),
].map((url) => url.trim().replace(/\/$/, '')).filter(Boolean);
const clientId = Deno.env.get('KAKAO_REST_API_KEY') ?? '';
const clientSecret = Deno.env.get('KAKAO_CLIENT_SECRET') ?? '';

function corsHeaders(origin: string | null) {
  const allowedOrigin = origin && siteUrls.includes(origin) ? origin : siteUrls[0] ?? '';
  return { 'Access-Control-Allow-Origin': allowedOrigin, 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json', Vary: 'Origin' };
}
function response(request: Request, body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: corsHeaders(request.headers.get('origin')) }); }
function isAllowedCallback(url: unknown): url is string { return typeof url === 'string' && siteUrls.some((siteUrl) => url === `${siteUrl}/kakao-callback.html`); }

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(request.headers.get('origin')) });
  if (request.method !== 'POST' || !siteUrls.length || !clientId || !clientSecret) return response(request, { error:'Server configuration is incomplete.' }, 500);
  const origin = request.headers.get('origin');
  if (origin && !siteUrls.includes(origin)) return response(request, { error:'Origin is not allowed.' }, 403);
  try {
    const { action, state, code, redirectUri } = await request.json();
    if (!isAllowedCallback(redirectUri)) return response(request, { error:'Invalid redirect URI.' }, 400);
    if (action === 'start') {
      if (typeof state !== 'string' || state.length < 20) return response(request, { error:'Invalid state.' }, 400);
      const authorizeUrl = new URL('https://kauth.kakao.com/oauth/authorize');
      authorizeUrl.search = new URLSearchParams({ client_id:clientId, redirect_uri:redirectUri, response_type:'code', scope:'openid,profile_nickname,profile_image', state }).toString();
      return response(request, { authorizeUrl:authorizeUrl.toString() });
    }
    if (action === 'exchange') {
      if (typeof code !== 'string' || code.length < 10) return response(request, { error:'Invalid authorization code.' }, 400);
      const tokenResponse = await fetch('https://kauth.kakao.com/oauth/token', { method:'POST', headers:{ 'Content-Type':'application/x-www-form-urlencoded;charset=utf-8' }, body:new URLSearchParams({ grant_type:'authorization_code', client_id:clientId, client_secret:clientSecret, redirect_uri:redirectUri, code }) });
      const tokenData = await tokenResponse.json();
      if (!tokenResponse.ok || !tokenData.id_token) return response(request, { error:'Kakao token exchange failed.' }, 400);
      return response(request, { idToken:tokenData.id_token });
    }
    return response(request, { error:'Invalid action.' }, 400);
  } catch { return response(request, { error:'Invalid request.' }, 400); }
});

