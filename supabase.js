import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Publishable key only. Never place a service_role or secret key in this file.
export const supabase = createClient(
  'https://sczgelfdrlkenlshthsa.supabase.co',
  'sb_publishable_cJv4iU4Aod6RVY8se0TiZg_oXS0Ukdk'
);

// Level 1 covers 0–1,999P. From 2,000P onward, every additional 1,000P
// increases the displayed level by one.
export function levelForPoints(points = 0) {
  return Math.max(1, Math.floor(Number(points) / 1000));
}

// The header initially has a login route so signed-out visitors are protected.
// Intercept it for signed-in visitors to avoid a visible login-page flash.
document.addEventListener('click', async event => {
  const startLink = event.target.closest('a[href="login.html?next=create-debate.html"]');
  if (!startLink || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  const { data: { user } } = await supabase.auth.getUser();
  location.href = user ? 'create-debate.html' : 'login.html?next=create-debate.html';
});

// Keep the shared header navigation consistent across every existing page.
document.querySelectorAll('a[href="index.html#popular"], a[href="#popular"]').forEach(link => { link.href = 'popular.html'; });

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
  style.textContent = '.notification-link{position:relative;display:inline-grid;place-items:center;width:30px;height:30px;padding:0;border:0;background:transparent;color:#555;cursor:pointer}.notification-link svg{width:18px;height:18px;stroke:currentColor;fill:none;stroke-width:1.8}.notification-badge{position:absolute;top:1px;right:0;display:none;min-width:15px;height:15px;padding:0 3px;border-radius:9px;background:#d85a50;color:#fff;font:700 10px/15px Arial,sans-serif;text-align:center}.notification-link.has-unread .notification-badge{display:block}.notification-panel{position:absolute;z-index:20;top:38px;right:0;display:none;width:min(200px,calc(100vw - 24px));max-height:360px;overflow:auto;border:1px solid #dedede;background:#fff;box-shadow:0 7px 18px rgba(0,0,0,.12);padding:5px 0}.notification-panel.open{display:block}.notification-panel-head{display:flex;align-items:center;padding:7px 12px 9px;border-bottom:1px solid #ededed}.notification-panel-title{color:#222;font:700 12px "Noto Sans KR",sans-serif}.notification-clear{margin-left:auto;border:0;background:transparent;padding:1px 0;color:#aaa;font:11px "Noto Sans KR",sans-serif;cursor:pointer}.notification-clear:hover{color:#666}.notification-clear:disabled{color:#ccc;cursor:wait}.notification-item{display:block;padding:10px 12px;color:#444;text-decoration:none;border-bottom:1px solid #f0f0f0;font:12px/1.55 "Noto Sans KR",sans-serif}.notification-item:last-child{border-bottom:0}.notification-item:hover{background:#fafafa}.notification-item time{display:block;margin-top:3px;color:#999;font-size:11px}.notification-empty{padding:14px 12px;color:#888;font:12px "Noto Sans KR",sans-serif}';
  document.head.append(style);
}

async function refreshNotificationBadge(target, userId) {
  const link = target.querySelector('.notification-link'); if (!link) return;
  const { count } = await supabase.from('notifications').select('id', { count:'exact', head:true }).eq('recipient_id', userId).eq('is_read', false).is('deleted_at', null);
  const badge = link.querySelector('.notification-badge'); const unread = count || 0;
  badge.textContent = unread > 99 ? '99+' : unread;
  link.classList.toggle('has-unread', unread > 0);
  link.setAttribute('aria-label', unread ? `읽지 않은 알림 ${unread}개` : '알림');
}

async function openNotificationPanel(target, userId) {
  const panel = target.querySelector('.notification-panel');
  panel.classList.add('open');
  panel.innerHTML = '<div class="notification-panel-head"><div class="notification-panel-title">알림</div><button class="notification-clear" type="button">모두 지우기</button></div><div class="notification-empty">알림을 불러오는 중입니다.</div>';
  const { data: items, error } = await supabase.from('notifications').select('id,debate_id,body,is_read,created_at').eq('recipient_id', userId).is('deleted_at', null).order('created_at', { ascending:false }).limit(8);
  if (error) { panel.innerHTML = '<div class="notification-panel-head"><div class="notification-panel-title">알림</div></div><div class="notification-empty">알림을 불러오지 못했습니다.</div>'; return; }
  panel.replaceChildren();
  const head = document.createElement('div'); head.className = 'notification-panel-head'; const title = document.createElement('div'); title.className = 'notification-panel-title'; title.textContent = '알림'; const clear = document.createElement('button'); clear.type = 'button'; clear.className = 'notification-clear'; clear.textContent = '모두 지우기'; clear.disabled = !items?.length; head.append(title, clear); panel.append(head);
  clear.addEventListener('click', async () => { if (!items?.length || !confirm('알림을 모두 지울까요?')) return; clear.disabled = true; const { error: clearError } = await supabase.rpc('clear_my_notifications'); if (clearError) { alert('알림을 지우지 못했습니다.'); clear.disabled = false; return; } panel.classList.remove('open'); panel.replaceChildren(); await refreshNotificationBadge(target, userId); });
  if (!items?.length) { const empty = document.createElement('div'); empty.className = 'notification-empty'; empty.textContent = '새 알림이 없습니다.'; panel.append(empty); return; }
  const formatter = new Intl.DateTimeFormat('ko-KR', { month:'numeric', day:'numeric', hour:'2-digit', minute:'2-digit' });
  items.forEach(item => { const row = document.createElement('a'); row.className = 'notification-item'; row.href = item.debate_id ? `debate-detail.html?id=${item.debate_id}` : 'index.html'; row.textContent = item.body; const time = document.createElement('time'); time.textContent = formatter.format(new Date(item.created_at)); row.append(time); panel.append(row); });
  if (items?.length) { await supabase.from('notifications').update({ is_read:true }).eq('recipient_id', userId).is('deleted_at', null); refreshNotificationBadge(target, userId); }
}

export async function mountAuthState(targetId) {
  const target = document.getElementById(targetId);
  if (!target) return;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) { target.style.visibility = 'visible'; return; }
  const profile = await getProfile();
  if (!profile || /^토론자[0-9a-f]{6}$/i.test(profile.nickname)) {
    location.href = `nickname.html?next=${encodeURIComponent(location.pathname.split('/').pop() || 'index.html')}`;
    return;
  }
  // The database enforces one reward per Korea-standard calendar day.
  // Point features may not be installed yet. They must never prevent an
  // otherwise valid login session or the rest of a page from rendering.
  try { await supabase.rpc('daily_checkin'); } catch (_) { /* optional feature */ }
  try { await supabase.rpc('settle_expired_debates'); } catch (_) { /* optional feature */ }
  const nickname = profile.nickname;
  ensureNotificationStyle();
  target.replaceChildren();
  const account = document.createElement('a'); account.className = 'account-link'; account.href = 'my.html'; account.textContent = nickname;
  target.style.position = 'relative';
  const notification = document.createElement('button'); notification.className = 'notification-link'; notification.type = 'button'; notification.setAttribute('aria-label', '알림'); notification.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></svg><span class="notification-badge"></span>';
  const logout = document.createElement('button'); logout.className = 'logout-button'; logout.type = 'button'; logout.textContent = '로그아웃';
  const panel = document.createElement('div'); panel.className = 'notification-panel';
  target.append(account, notification, logout, panel);
  target.style.visibility = 'visible';
  await refreshNotificationBadge(target, user.id);
  window.setInterval(() => refreshNotificationBadge(target, user.id), 60000);
  notification.addEventListener('click', async event => { event.stopPropagation(); if (panel.classList.contains('open')) { panel.classList.remove('open'); return; } await openNotificationPanel(target, user.id); });
  document.addEventListener('click', event => { if (!target.contains(event.target)) panel.classList.remove('open'); });
  logout.addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.href = 'index.html';
  });
}

