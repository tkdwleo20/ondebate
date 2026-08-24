// Deploy as a Supabase Edge Function named "kakao-token" with JWT verification disabled.
// Required secrets: KAKAO_REST_API_KEY, KAKAO_CLIENT_SECRET, SITE_URL=https://ondebate.pages.dev
const siteUrl = (Deno.env.get('SITE_URL') ?? '').replace(/\/$/, '');
const clientId = Deno.env.get('KAKAO_REST_API_KEY') ?? '';
const clientSecret = Deno.env.get('KAKAO_CLIENT_SECRET') ?? '';
const corsHeaders = { 'Access-Control-Allow-Origin': siteUrl, 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json' };

function response(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: corsHeaders }); }
function callbackUrl() { return `${siteUrl}/kakao-callback.html`; }

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST' || !siteUrl || !clientId || !clientSecret) return response({ error:'Server configuration is incomplete.' }, 500);
  const origin = request.headers.get('origin');
  if (origin && origin !== siteUrl) return response({ error:'Origin is not allowed.' }, 403);
  try {
    const { action, state, code, redirectUri } = await request.json();
    if (redirectUri !== callbackUrl()) return response({ error:'Invalid redirect URI.' }, 400);
    if (action === 'start') {
      if (typeof state !== 'string' || state.length < 20) return response({ error:'Invalid state.' }, 400);
      const authorizeUrl = new URL('https://kauth.kakao.com/oauth/authorize');
      authorizeUrl.search = new URLSearchParams({ client_id:clientId, redirect_uri:callbackUrl(), response_type:'code', scope:'openid,profile_nickname,profile_image', state }).toString();
      return response({ authorizeUrl:authorizeUrl.toString() });
    }
    if (action === 'exchange') {
      if (typeof code !== 'string' || code.length < 10) return response({ error:'Invalid authorization code.' }, 400);
      const tokenResponse = await fetch('https://kauth.kakao.com/oauth/token', { method:'POST', headers:{ 'Content-Type':'application/x-www-form-urlencoded;charset=utf-8' }, body:new URLSearchParams({ grant_type:'authorization_code', client_id:clientId, client_secret:clientSecret, redirect_uri:callbackUrl(), code }) });
      const tokenData = await tokenResponse.json();
      if (!tokenResponse.ok || !tokenData.id_token) return response({ error:'Kakao token exchange failed.' }, 400);
      return response({ idToken:tokenData.id_token });
    }
    return response({ error:'Invalid action.' }, 400);
  } catch { return response({ error:'Invalid request.' }, 400); }
});

