import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Publishable key only. Never place a service_role or secret key in this file.
export const supabase = createClient(
  'https://sczgelfdrlkenlshthsa.supabase.co',
  'sb_publishable_cJv4iU4Aod6RVY8se0TiZg_oXS0Ukdk'
);

export async function getProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase.from('profiles').select('id,nickname,points').eq('id', user.id).maybeSingle();
  if (error) throw error;
  return data;
}

export async function saveNickname(nickname) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('로그인이 필요합니다.');
  const cleanNickname = nickname.trim();
  if (cleanNickname.length < 2 || cleanNickname.length > 20) throw new Error('닉네임은 2~20자로 입력해 주세요.');
  const { error } = await supabase.from('profiles').upsert({ id: user.id, nickname: cleanNickname });
  if (error) throw error;
  return cleanNickname;
}

export async function mountAuthState(targetId) {
  const target = document.getElementById(targetId);
  if (!target) return;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  const profile = await getProfile();
  if (!profile || /^토론자[0-9a-f]{6}$/i.test(profile.nickname)) {
    location.href = `nickname.html?next=${encodeURIComponent(location.pathname.split('/').pop() || 'index.html')}`;
    return;
  }
  const nickname = profile.nickname;
  target.innerHTML = `<a class="account-link" href="my.html">${nickname}</a><button class="logout-button" type="button">로그아웃</button>`;
  target.querySelector('.logout-button').addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.href = 'index.html';
  });
}

