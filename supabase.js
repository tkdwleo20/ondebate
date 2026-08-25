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
  const { error } = await supabase.rpc('set_nickname', { p_nickname: cleanNickname, p_is_change: false });
  if (error) throw error;
  return cleanNickname;
}

export async function changeNickname(nickname) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('로그인이 필요합니다.');
  const cleanNickname = nickname.trim();
  if (cleanNickname.length < 2 || cleanNickname.length > 20) throw new Error('닉네임은 2~20자로 입력해 주세요.');
  const { error } = await supabase.rpc('set_nickname', { p_nickname: cleanNickname, p_is_change: true });
  if (error) throw error;
  return cleanNickname;
}

function ensureNotificationStyle() {
  if (document.getElementById('notification-style')) return;
  const style = document.createElement('style'); style.id = 'notification-style';
  style.textContent = '.notification-link{position:relative;display:inline-grid;place-items:center;width:30px;height:30px;color:#555;text-decoration:none}.notification-link svg{width:18px;height:18px;stroke:currentColor;fill:none;stroke-width:1.8}.notification-badge{position:absolute;top:1px;right:0;display:none;min-width:15px;height:15px;padding:0 3px;border-radius:9px;background:#d85a50;color:#fff;font:700 10px/15px Arial,sans-serif;text-align:center}.notification-link.has-unread .notification-badge{display:block}';
  document.head.append(style);
}

async function refreshNotificationBadge(target, userId) {
  const link = target.querySelector('.notification-link'); if (!link) return;
  const { count } = await supabase.from('notifications').select('id', { count:'exact', head:true }).eq('recipient_id', userId).eq('is_read', false);
  const badge = link.querySelector('.notification-badge'); const unread = count || 0;
  badge.textContent = unread > 99 ? '99+' : unread;
  link.classList.toggle('has-unread', unread > 0);
  link.setAttribute('aria-label', unread ? `읽지 않은 알림 ${unread}개` : '알림');
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
  ensureNotificationStyle();
  target.replaceChildren();
  const account = document.createElement('a'); account.className = 'account-link'; account.href = 'my.html'; account.textContent = nickname;
  const notification = document.createElement('a'); notification.className = 'notification-link'; notification.href = 'notifications.html'; notification.setAttribute('aria-label', '알림'); notification.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></svg><span class="notification-badge"></span>';
  const logout = document.createElement('button'); logout.className = 'logout-button'; logout.type = 'button'; logout.textContent = '로그아웃';
  target.append(account, notification, logout);
  await refreshNotificationBadge(target, user.id);
  window.setInterval(() => refreshNotificationBadge(target, user.id), 60000);
  logout.addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.href = 'index.html';
  });
}

