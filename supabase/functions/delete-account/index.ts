import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const allowedOrigins = new Set([
  'https://ondebate.co.kr',
  'https://www.ondebate.co.kr',
  'https://ondebate.pages.dev',
])

function corsHeadersFor(request: Request) {
  const origin = request.headers.get('Origin') ?? ''
  return {
    ...(allowedOrigins.has(origin) ? { 'Access-Control-Allow-Origin': origin } : {}),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

Deno.serve(async (request) => {
  const corsHeaders = corsHeadersFor(request)
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const authHeader = request.headers.get('Authorization') ?? ''
    const userClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) return new Response(JSON.stringify({ error: '로그인이 필요합니다.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { error: endError } = await admin.from('debates').update({ status: 'ended' }).or(`creator_id.eq.${user.id},opponent_id.eq.${user.id}`).in('status', ['waiting', 'active'])
    if (endError) throw endError
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
    if (deleteError) throw deleteError
    return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message ?? '탈퇴 처리에 실패했습니다.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})

