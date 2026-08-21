import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Publishable key only. Never place a service_role or secret key in this file.
export const supabase = createClient(
  'https://sczgelfdrlkenlshthsa.supabase.co',
  'sb_publishable_cJv4iU4Aod6RVY8se0TiZg_oXS0Ukdk'
);

export async function ensureProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const nickname = `토론자${user.id.replaceAll('-', '').slice(0, 6)}`;
  const { error } = await supabase.from('profiles').upsert({ id: user.id, nickname });
  if (error) throw error;
  return user;
}

export async function mountAuthState(targetId) {
  const target = document.getElementById(targetId);
  if (!target) return;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  const profile = await ensureProfile();
  const nickname = `토론자${profile.id.replaceAll('-', '').slice(0, 6)}`;
  target.innerHTML = `<button class="account-button" type="button">${nickname} · 로그아웃</button>`;
  target.querySelector('button').addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.href = 'index.html';
  });
}

