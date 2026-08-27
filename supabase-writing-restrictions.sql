-- Moderation writing restrictions.
-- Public-name reports can restrict all writing. Anonymous reports only restrict
-- anonymous writing, while keeping the anonymous author concealed in admin UI.

create table if not exists public.write_restrictions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  expires_at timestamptz not null,
  report_id uuid references public.reports(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.write_restrictions enable row level security;

create or replace function public.assert_write_allowed(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_until timestamptz;
begin
  select expires_at into v_until from public.write_restrictions where user_id = p_user_id;
  if v_until is not null and v_until > now() then
    raise exception '글쓰기가 %까지 제한되어 있습니다.', to_char(v_until at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI');
  end if;
end;
$$;

create or replace function public.admin_restrict_public_subject(p_report_id uuid, p_hours integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_user_id uuid; v_is_anonymous boolean; v_debate_id uuid; v_until timestamptz;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_hours not in (24, 168) then raise exception '제한 시간은 1일 또는 7일만 가능합니다.'; end if;
  select r.reported_user_id, r.debate_id, coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = r.debate_id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
  into v_user_id, v_debate_id, v_is_anonymous from public.reports r where r.id = p_report_id and r.status = 'open';
  if v_user_id is null then raise exception '처리할 신고를 찾을 수 없습니다.'; end if;
  if v_is_anonymous then raise exception '익명 글 신고에는 익명 글쓰기 제한만 적용할 수 있습니다.'; end if;
  v_until := now() + make_interval(hours => p_hours);
  insert into public.write_restrictions(user_id, expires_at, report_id)
  values (v_user_id, v_until, p_report_id)
  on conflict (user_id) do update set expires_at = greatest(public.write_restrictions.expires_at, excluded.expires_at), report_id = excluded.report_id;
  update public.reports set status = 'reviewed' where id = p_report_id;
  perform public.create_notification(v_user_id, auth.uid(), v_debate_id, 'report_result',
    format('글쓰기 %s일 제한이 적용되었습니다. 제한 종료: %s', p_hours / 24, to_char(v_until at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일 HH24:MI')),
    'writing-restriction:' || p_report_id::text || ':' || p_hours::text);
end;
$$;

create or replace function public.admin_restrict_anonymous_subject(p_report_id uuid, p_hours integer default 168)
returns void language plpgsql security definer set search_path = public as $$
declare v_user_id uuid; v_is_anonymous boolean; v_debate_id uuid; v_until timestamptz;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_hours not in (24, 168) then raise exception '제한 시간은 1일 또는 7일만 가능합니다.'; end if;
  select r.reported_user_id, r.debate_id, coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = r.debate_id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
  into v_user_id, v_debate_id, v_is_anonymous from public.reports r where r.id = p_report_id and r.status = 'open';
  if v_user_id is null then raise exception '처리할 신고를 찾을 수 없습니다.'; end if;
  if not v_is_anonymous then raise exception '닉네임 글 신고에는 글쓰기 제한을 적용해 주세요.'; end if;
  v_until := now() + make_interval(hours => p_hours);
  insert into public.anonymous_write_restrictions(user_id, expires_at, report_id)
  values (v_user_id, v_until, p_report_id)
  on conflict (user_id) do update set expires_at = greatest(public.anonymous_write_restrictions.expires_at, excluded.expires_at), report_id = excluded.report_id;
  update public.reports set status = 'reviewed' where id = p_report_id;
  perform public.create_notification(v_user_id, auth.uid(), v_debate_id, 'report_result',
    format('익명 글쓰기 %s일 제한이 적용되었습니다. 제한 종료: %s', p_hours / 24, to_char(v_until at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일 HH24:MI')),
    'anonymous-writing-restriction:' || p_report_id::text || ':' || p_hours::text);
end;
$$;

-- Add the general restriction to all content-writing functions. The remainder of
-- each function is deliberately preserved from the currently deployed anonymous-writing version.
create or replace function public.create_debate(p_title text, p_category text, p_duration_hours smallint, p_opening text, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_debate_id uuid; v_user_id uuid := auth.uid(); v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  perform public.assert_write_allowed(v_user_id);
  if p_duration_hours not between 1 and 24 then raise exception '토론 시간은 1~24시간으로 설정해야 합니다.'; end if;
  if p_category not in ('일상', '사회 · 정치', '연애', '문화 · 취미', '게임 · 스포츠', '학교 · 직장') then raise exception '올바른 카테고리를 선택해 주세요.'; end if;
  if char_length(trim(p_title)) not between 2 and 100 then raise exception '제목은 2~100자로 작성해 주세요.'; end if;
  if char_length(trim(p_opening)) not between 1 and 3000 then raise exception '첫 발언은 1~3,000자로 작성해 주세요.'; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); end if;
  insert into public.debates(creator_id, creator_is_anonymous, title, category, duration_hours, ends_at)
  values(v_user_id, coalesce(p_is_anonymous, false), trim(p_title), p_category, p_duration_hours, now() + make_interval(hours => p_duration_hours)) returning id into v_debate_id;
  if coalesce(p_is_anonymous, false) then v_code := public.anonymous_code_for(v_debate_id, v_user_id); end if;
  insert into public.debate_messages(debate_id, author_id, side, body, is_anonymous, anonymous_code)
  values(v_debate_id, v_user_id, 'left', trim(p_opening), coalesce(p_is_anonymous, false), v_code);
  return v_debate_id;
end;
$$;

create or replace function public.post_debate_message(p_debate_id uuid, p_body text, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_user_id uuid := auth.uid(); v_debate public.debates%rowtype; v_side text; v_anonymous boolean; v_code text; v_message_id uuid;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  perform public.assert_write_allowed(v_user_id);
  if char_length(trim(p_body)) not between 1 and 3000 then raise exception '발언은 1~3,000자로 작성해 주세요.'; end if;
  select * into v_debate from public.debates where id = p_debate_id for update;
  if not found then raise exception '토론을 찾을 수 없습니다.'; end if;
  if v_debate.status in ('ended', 'hidden') or v_debate.ends_at <= now() then raise exception '이미 종료된 토론입니다.'; end if;
  if v_user_id = v_debate.creator_id then v_side := 'left'; v_anonymous := v_debate.creator_is_anonymous;
  elsif v_user_id = v_debate.opponent_id then v_side := 'right'; v_anonymous := coalesce(v_debate.opponent_is_anonymous, false);
  elsif v_debate.opponent_id is null then v_side := 'right'; v_anonymous := coalesce(p_is_anonymous, false); update public.debates set opponent_id = v_user_id, opponent_is_anonymous = v_anonymous, status = 'active' where id = p_debate_id;
  else raise exception '참가자만 발언을 남길 수 있습니다.'; end if;
  if v_anonymous then perform public.assert_anonymous_write_allowed(v_user_id); v_code := public.anonymous_code_for(p_debate_id, v_user_id); end if;
  insert into public.debate_messages(debate_id, author_id, side, body, is_anonymous, anonymous_code)
  values(p_debate_id, v_user_id, v_side, trim(p_body), v_anonymous, v_code) returning id into v_message_id;
  return v_message_id;
end;
$$;

create or replace function public.add_message_comment(p_message_id uuid, p_body text, p_parent_id uuid, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_user_id uuid := auth.uid(); v_parent_message uuid; v_debate_id uuid; v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  perform public.assert_write_allowed(v_user_id);
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  select m.debate_id into v_debate_id from public.debate_messages m join public.debates d on d.id = m.debate_id where m.id = p_message_id and d.status <> 'hidden' and m.deleted_at is null;
  if v_debate_id is null then raise exception '댓글을 남길 수 없는 발언입니다.'; end if;
  if p_parent_id is not null then select message_id into v_parent_message from public.message_comments where id = p_parent_id; if v_parent_message is distinct from p_message_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); v_code := public.anonymous_code_for(v_debate_id, v_user_id); end if;
  insert into public.message_comments(message_id, author_id, body, parent_id, is_anonymous, anonymous_code)
  values(p_message_id, v_user_id, trim(p_body), p_parent_id, coalesce(p_is_anonymous, false), v_code) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.add_debate_comment(p_debate_id uuid, p_body text, p_parent_id uuid, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_user_id uuid := auth.uid(); v_parent_debate uuid; v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  perform public.assert_write_allowed(v_user_id);
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if not exists (select 1 from public.debates d where d.id = p_debate_id and d.status <> 'hidden') then raise exception '댓글을 남길 수 없는 토론입니다.'; end if;
  if p_parent_id is not null then select debate_id into v_parent_debate from public.debate_comments where id = p_parent_id; if v_parent_debate is distinct from p_debate_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); v_code := public.anonymous_code_for(p_debate_id, v_user_id); end if;
  insert into public.debate_comments(debate_id, author_id, body, parent_id, is_anonymous, anonymous_code)
  values(p_debate_id, v_user_id, trim(p_body), p_parent_id, coalesce(p_is_anonymous, false), v_code) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.assert_write_allowed(uuid) from public, anon, authenticated;
revoke all on function public.admin_restrict_public_subject(uuid, integer) from public, anon;
grant execute on function public.admin_restrict_public_subject(uuid, integer) to authenticated;
grant execute on function public.admin_restrict_anonymous_subject(uuid, integer) to authenticated;

