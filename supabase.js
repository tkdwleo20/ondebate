import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Publishable key only. Never place a service_role or secret key in this file.
const supabaseUrl = 'https://sczgelfdrlkenlshthsa.supabase.co';
const supabasePublishableKey = 'sb_publishable_cJv4iU4Aod6RVY8se0TiZg_oXS0Ukdk';
export const supabase = createClient(supabaseUrl, supabasePublishableKey);

// A random browser ID lets us count one anonymous visitor per Korea-standard
// calendar day. It does not contain an email, nickname, or account identifier.
function recordSiteVisit() {
  try {
    let visitorKey = localStorage.getItem('ondebate_visitor_key');
    if (!visitorKey) {
      visitorKey = crypto.randomUUID();
      localStorage.setItem('ondebate_visitor_key', visitorKey);
    }
    const today = new Intl.DateTimeFormat('en-CA', { timeZone:'Asia/Seoul' }).format(new Date());
    const recordedKey = 'ondebate_site_visit_recorded';
    if (localStorage.getItem(recordedKey) === today) return;
    supabase.rpc('record_site_visit', { p_visitor_key: visitorKey }).then(({ error }) => {
      if (!error) localStorage.setItem(recordedKey, today);
    }).catch(() => {});
  } catch (_) { /* private browsing or an older browser may block storage */ }
}
if (typeof window !== 'undefined') recordSiteVisit();

if (typeof document !== 'undefined' && !document.querySelector('link[rel="icon"]')) {
  const icon = document.createElement('link');
  icon.rel = 'icon'; icon.type = 'image/svg+xml'; icon.href = 'ondebate-logo.svg';
  document.head.append(icon);
}

// Use the same compact wordmark in every shared header without changing the
// surrounding menu layout. Keeping it inline avoids a separate asset request.
function mountBrandLogo() {
  const brand = document.querySelector('header .brand');
  if (!brand || brand.dataset.logoMounted) return;
  brand.dataset.logoMounted = 'true';
  brand.setAttribute('aria-label', 'OnDebate 홈');
  brand.style.cssText += ';display:inline-flex;align-items:center;width:122px;height:34px;flex:none';
  brand.innerHTML = '<svg viewBox="42 12 276 66" role="img" aria-label="OnDebate 로고" style="display:block;width:100%;height:100%"><text x="180" y="66" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="54" font-weight="700" letter-spacing="-4"><tspan fill="#222">On</tspan><tspan fill="#e64b3c">Debate</tspan></text></svg>';
  brand.style.visibility = 'visible';
  if (!document.getElementById('brand-logo-style')) {
    const style = document.createElement('style');
    style.id = 'brand-logo-style';
    style.textContent = '@media(max-width:650px){header .brand{width:104px!important;height:29px!important}}';
    document.head.append(style);
  }
}
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountBrandLogo, { once:true });
  else mountBrandLogo();
}

// Keep the legal notice available on every page that uses the shared client.
// It is intentionally inlined here because static asset requests can be
// rewritten to the SPA entry point by the Pages deployment.
function mountSiteFooter() {
  let style = document.getElementById('site-footer-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'site-footer-style';
    style.textContent = '.site-footer{margin-top:auto;border-top:1px solid #e5e5e5;background:#fff;color:#858585;font:12px/1.7 "Noto Sans KR",sans-serif}.site-footer__inner{width:min(1120px,calc(100% - 48px));margin:0 auto;padding:18px 0 22px;display:flex;align-items:center;gap:20px;flex-wrap:wrap}.site-footer__logo{display:inline-flex;align-items:center;width:108px;height:38px;text-decoration:none}.site-footer__logo svg{display:block;width:100%;height:100%}.site-footer nav{display:flex;gap:18px;height:auto}.site-footer nav a{color:#555;text-decoration:none;font-size:13px;font-weight:600;letter-spacing:-.25px}.site-footer nav a:hover{text-decoration:underline}.site-footer__contact{margin-left:auto}.site-footer__contact a{color:#666;text-decoration:none}.site-footer__business{color:#aaa}@media(max-width:650px){.site-footer__inner{width:calc(100% - 48px);padding:14px 0 18px;gap:7px 18px}.site-footer__logo{width:96px;height:35px}.site-footer__contact,.site-footer__business{width:100%;margin-left:0}}';
    document.head.append(style);
  }
  // Some older pages still load footer.js. Replace that legacy footer so every
  // screen uses the same structure and styling as the home page.
  document.querySelector('.site-footer')?.remove();
  const footer = document.createElement('footer');
  footer.className = 'site-footer';
  footer.innerHTML = '<div class="site-footer__inner"><a class="site-footer__logo" href="index.html" aria-label="OnDebate 홈"><img class="site-footer__logo-image" alt="OnDebate" src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAzNjAgMTAwIj48cmVjdCB3aWR0aD0iMzYwIiBoZWlnaHQ9IjEwMCIgcng9IjEwIiBmaWxsPSIjZmZmIi8+PHRleHQgeD0iMTgwIiB5PSI2NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC1mYW1pbHk9IkFyaWFsLEhlbHZldGljYSxzYW5zLXNlcmlmIiBmb250LXNpemU9IjU0IiBmb250LXdlaWdodD0iNzAwIiBsZXR0ZXItc3BhY2luZz0iLTQiPjx0c3BhbiBmaWxsPSIjMjIyIj5PbjwvdHNwYW4+PHRzcGFuIGZpbGw9IiNlNjRiM2MiPkRlYmF0ZTwvdHNwYW4+PC90ZXh0Pjwvc3ZnPg==" /></a><nav aria-label="정책 안내"><a href="terms.html">이용약관</a><a href="privacy.html">개인정보처리방침</a></nav><span class="site-footer__contact">문의 <a href="mailto:support@ondebate.co.kr">support@ondebate.co.kr</a></span><span class="site-footer__business">사업자 정보는 추후 업데이트됩니다.</span></div>';
  footer.style.cssText = 'margin-top:auto;border-top:1px solid #e5e5e5;background:#fff;color:#858585;font:12px/1.7 "Noto Sans KR",sans-serif';
  const footerInner = footer.querySelector('.site-footer__inner');
  footerInner.style.cssText = 'width:min(1120px,calc(100% - 48px));margin:0 auto;padding:18px 0 22px;display:flex;align-items:center;gap:20px;flex-wrap:wrap';
  const footerLogo = footer.querySelector('.site-footer__logo');
  footerLogo.style.cssText = 'display:inline-flex;align-items:center;width:108px;height:38px;text-decoration:none;flex:none';
  footer.querySelector('.site-footer__logo-image').style.cssText = 'display:block;width:100%;height:100%;object-fit:contain';
  const footerNav = footer.querySelector('nav'); footerNav.style.cssText = 'display:flex;align-items:center;gap:18px;height:auto';
  footerNav.querySelectorAll('a').forEach(link => link.style.cssText = 'color:#555;text-decoration:none;font-size:13px;font-weight:600;letter-spacing:-.25px');
  footer.querySelector('.site-footer__contact').style.marginLeft = 'auto';
  footer.querySelector('.site-footer__contact a').style.cssText = 'color:#666;text-decoration:none';
  footer.querySelector('.site-footer__business').style.color = '#aaa';
  document.body.append(footer);
}
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountSiteFooter, { once:true });
  else mountSiteFooter();
}

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
  try {
    // getSession reads the locally stored session first, so a temporarily busy
    // auth server cannot make the start button appear unresponsive.
    const { data: { session } } = await supabase.auth.getSession();
    location.href = session?.user ? 'create-debate.html' : 'login.html?next=create-debate.html';
  } catch (_) {
    // The safe fallback remains available even if browser storage is blocked.
    location.href = 'login.html?next=create-debate.html';
  }
});

// Keep the shared header navigation consistent across every existing page.
document.querySelectorAll('a[href="index.html#popular"], a[href="#popular"]').forEach(link => { link.href = 'popular.html'; });
document.querySelectorAll('a[href="index.html#categories"]').forEach(link => { link.href = 'index.html?section=categories&nav=1'; });

// Preserve the list a visitor came from so the debate detail can show the
// matching list again below its comments.
document.addEventListener('click', event => {
  const clickedLink = event.target.closest?.('a[href^="debate-detail.html?id="]');
  const cardLink = clickedLink || event.target.closest?.('article')?.querySelector('a[href^="debate-detail.html?id="]');
  if (!cardLink) return;
  const page = location.pathname.split('/').pop() || 'index.html';
  const destination = new URL(cardLink.href, location.href);
  if (destination.searchParams.has('from')) return;
  if (page === 'popular.html') destination.searchParams.set('from', cardLink.closest('#daily') ? 'popular-daily' : 'popular-weekly');
  else if (page === 'category.html') { destination.searchParams.set('from', 'category'); destination.searchParams.set('category', new URLSearchParams(location.search).get('name') || ''); }
  else if (page === 'search.html') { destination.searchParams.set('from', 'search'); destination.searchParams.set('q', new URLSearchParams(location.search).get('q') || ''); }
  else if (page === 'index.html' || page === '') destination.searchParams.set('from', 'home');
  else return;
  cardLink.href = destination.href;
  if (!clickedLink) { event.preventDefault(); event.stopImmediatePropagation(); location.href = destination.href; }
}, true);

let profilePromise = null;
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const profileCacheKey = userId => `ondebate_profile_${userId}`;

function readCachedProfile(userId) {
  try {
    const cached = sessionStorage.getItem(profileCacheKey(userId));
    const profile = cached ? JSON.parse(cached) : null;
    return profile?.id === userId && typeof profile.nickname === 'string' ? profile : null;
  } catch (_) { return null; }
}

function cacheProfile(profile) {
  try { sessionStorage.setItem(profileCacheKey(profile.id), JSON.stringify(profile)); }
  catch (_) { /* storage is optional and only improves short outage recovery */ }
}

// A busy or briefly reconnecting network must not make an existing member look
// like a new member. Confirm an absent profile across retries; surface actual
// request failures to the caller instead of returning a misleading null.
export async function getProfile({ refresh = false } = {}) {
  if (!refresh && profilePromise) return profilePromise;
  const request = (async () => {
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError) throw userError;
    if (!user) return null;
    let lastError = null;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const { data, error } = await supabase.from('profiles').select('id,nickname,points').eq('id', user.id).maybeSingle();
      if (data) { cacheProfile(data); return data; }
      if (error) lastError = error;
      if (attempt < 2) await wait(450 * (attempt + 1));
    }
    // A profile that was already confirmed in this browser is safer than
    // sending a signed-in member to nickname setup during a brief outage.
    const cached = readCachedProfile(user.id);
    if (cached) return cached;
    if (lastError) throw lastError;
    return null;
  })();
  profilePromise = request;
  try { return await request; }
  catch (error) { if (profilePromise === request) profilePromise = null; throw error; }
}

export async function saveNickname(nickname) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('로그인이 필요합니다.');
  const cleanNickname = nickname.trim();
  if (cleanNickname.length < 2 || cleanNickname.length > 20) throw new Error('닉네임은 2~20자로 입력해 주세요.');
  const { error } = await supabase.rpc('set_nickname', { p_nickname: cleanNickname, p_is_change: false });
  if (error) throw error;
  profilePromise = null;
  return cleanNickname;
}

export async function changeNickname(nickname) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('로그인이 필요합니다.');
  const cleanNickname = nickname.trim();
  if (cleanNickname.length < 2 || cleanNickname.length > 20) throw new Error('닉네임은 2~20자로 입력해 주세요.');
  const { error } = await supabase.rpc('set_nickname', { p_nickname: cleanNickname, p_is_change: true });
  if (error) throw error;
  profilePromise = null;
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
  const { data: unreadItems } = await supabase.from('notifications').select('id,debate_id,type').eq('recipient_id', userId).eq('is_read', false).is('deleted_at', null).order('created_at', { ascending:false }).limit(500);
  const badge = link.querySelector('.notification-badge'); const unread = groupNotifications(unreadItems || []).length;
  badge.textContent = unread > 99 ? '99+' : unread;
  link.classList.toggle('has-unread', unread > 0);
  link.setAttribute('aria-label', unread ? `읽지 않은 알림 ${unread}개` : '알림');
}

function groupNotifications(items) {
  const groups = new Map();
  items.forEach(item => {
    const activity = item.type === 'opponent_message' ? 'message' : ['message_comment', 'debate_comment'].includes(item.type) ? 'comment' : null;
    const key = activity && item.debate_id ? `${item.debate_id}:${activity}` : `single:${item.id}`;
    const group = groups.get(key) || { ...item, count:0, activity };
    group.count += 1;
    groups.set(key, group);
  });
  return [...groups.values()];
}

function notificationTitle(title) {
  const clean = String(title || '').replace(/\s+/g, ' ').trim();
  return clean.length > 20 ? `${clean.slice(0, 20)}…` : clean;
}

function groupedNotificationText(item) {
  const subject = notificationTitle(item.debate_title);
  if (item.count < 2) {
    if (!subject || !item.activity || String(item.body || '').startsWith('「')) return item.body;
    const preview = String(item.body || '').replace(/^(상대방의 새 발언|내 발언에 새 댓글|내 토론에 새 댓글|작성한 발언에 새 댓글이 등록되었습니다|작성한 토론에 새 댓글이 등록되었습니다)\s*:?\s*/, '');
    return `「${subject}」에 ${item.activity === 'message' ? '상대방의 새 발언' : '새 댓글'}${preview ? `: ${preview}` : ''}`;
  }
  if (!subject) return item.activity === 'message' ? `참여한 토론에 상대방의 새 발언 ${item.count}개` : `해당 토론에 새 댓글 ${item.count}개`;
  if (item.activity === 'message') return `「${subject}」에 상대방의 새 발언 ${item.count}개`;
  if (item.activity === 'comment') return `「${subject}」에 새 댓글 ${item.count}개`;
  return item.body;
}

async function openNotificationPanel(target, userId) {
  const panel = target.querySelector('.notification-panel');
  panel.classList.add('open');
  panel.innerHTML = '<div class="notification-panel-head"><div class="notification-panel-title">알림</div><button class="notification-clear" type="button">모두 지우기</button></div><div class="notification-empty">알림을 불러오는 중입니다.</div>';
  const { data: items, error } = await supabase.from('notifications').select('id,debate_id,type,body,is_read,created_at').eq('recipient_id', userId).is('deleted_at', null).order('created_at', { ascending:false }).limit(50);
  if (error) { panel.innerHTML = '<div class="notification-panel-head"><div class="notification-panel-title">알림</div></div><div class="notification-empty">알림을 불러오지 못했습니다.</div>'; return; }
  panel.replaceChildren();
  const head = document.createElement('div'); head.className = 'notification-panel-head'; const title = document.createElement('div'); title.className = 'notification-panel-title'; title.textContent = '알림'; const clear = document.createElement('button'); clear.type = 'button'; clear.className = 'notification-clear'; clear.textContent = '모두 지우기'; clear.disabled = !items?.length; head.append(title, clear); panel.append(head);
  clear.addEventListener('click', async () => { if (!items?.length || !confirm('알림을 모두 지울까요?')) return; clear.disabled = true; const { error: clearError } = await supabase.rpc('clear_my_notifications'); if (clearError) { alert('알림을 지우지 못했습니다.'); clear.disabled = false; return; } panel.classList.remove('open'); panel.replaceChildren(); await refreshNotificationBadge(target, userId); });
  if (!items?.length) { const empty = document.createElement('div'); empty.className = 'notification-empty'; empty.textContent = '새 알림이 없습니다.'; panel.append(empty); return; }
  const { data: debates } = await supabase.rpc('my_notification_debate_titles');
  const titles = new Map((debates || []).map(debate => [debate.debate_id, debate.title]));
  items.forEach(item => { item.debate_title = titles.get(item.debate_id) || ''; });
  const formatter = new Intl.DateTimeFormat('ko-KR', { month:'numeric', day:'numeric', hour:'2-digit', minute:'2-digit' });
  groupNotifications(items).slice(0,8).forEach(item => { const row = document.createElement('a'); row.className = 'notification-item'; row.href = item.debate_id ? `debate-detail.html?id=${item.debate_id}` : 'index.html'; row.textContent = groupedNotificationText(item); if (item.type === 'report_result') { row.style.cssText = 'border-left:3px solid #d85a50;background:#fff7f5;color:#8f372f;font-weight:700'; const warning = document.createElement('span'); warning.textContent = '⚠ '; warning.setAttribute('aria-label', '경고'); row.prepend(warning); } const time = document.createElement('time'); time.textContent = formatter.format(new Date(item.created_at)); row.append(time); panel.append(row); });
  if (items?.length) { await supabase.from('notifications').update({ is_read:true }).eq('recipient_id', userId).is('deleted_at', null); refreshNotificationBadge(target, userId); }
}

export async function mountAuthState(targetId) {
  const target = document.getElementById(targetId);
  if (!target || target.dataset.authMounted === 'true') return;
  const showGuestLink = () => {
    target.replaceChildren();
    const login = document.createElement('a');
    login.className = 'account-link';
    login.href = 'login.html';
    login.textContent = '로그인';
    target.append(login);
    target.style.visibility = 'visible';
  };
  const showChecking = () => {
    target.replaceChildren();
    const loading = document.createElement('span');
    loading.className = 'account-link';
    loading.textContent = '계정 확인 중…';
    target.append(loading);
    target.style.visibility = 'visible';
  };
  const retrySoon = () => {
    if (target.dataset.authRetryPending) return;
    target.dataset.authRetryPending = 'true';
    window.setTimeout(() => {
      delete target.dataset.authRetryPending;
      mountAuthState(targetId);
    }, 2500);
  };
  let user;
  let localSession = null;
  try { ({ data: { session: localSession } } = await supabase.auth.getSession()); }
  catch (_) { /* show the normal guest link below */ }
  try { ({ data: { user } } = await supabase.auth.getUser()); }
  catch (_) {
    // Previously this left a visibility:hidden header empty during short
    // Supabase outages. Keep a usable state on screen and retry silently.
    if (localSession?.user) { showChecking(); retrySoon(); }
    else showGuestLink();
    return;
  }
  if (!user && localSession?.user) {
    showChecking();
    retrySoon();
    return;
  }
  if (!user) { showGuestLink(); return; }
  let profile;
  try { profile = await getProfile(); }
  catch (_) {
    showChecking();
    retrySoon();
    return;
  }
  if (!profile || /^토론자[0-9a-f]{6}$/i.test(profile.nickname)) {
    location.href = `nickname.html?next=${encodeURIComponent(location.pathname.split('/').pop() || 'index.html')}`;
    return;
  }
  // The database enforces one reward per Korea-standard calendar day.
  // Point features may not be installed yet. They must never prevent an
  // otherwise valid login session or the rest of a page from rendering.
  try { await supabase.rpc('daily_checkin'); } catch (_) { /* optional feature */ }
  const nickname = profile.nickname;
  ensureNotificationStyle();
  target.replaceChildren();
  const account = document.createElement('a'); account.className = 'account-link'; account.href = 'my.html'; account.textContent = nickname;
  target.style.position = 'relative';
  const notification = document.createElement('button'); notification.className = 'notification-link'; notification.type = 'button'; notification.setAttribute('aria-label', '알림'); notification.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></svg><span class="notification-badge"></span>';
  const logout = document.createElement('button'); logout.className = 'logout-button'; logout.type = 'button'; logout.textContent = '로그아웃';
  const panel = document.createElement('div'); panel.className = 'notification-panel';
  target.append(account, notification, logout, panel);
  target.dataset.authMounted = 'true';
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
