-- Anonymous writing with per-debate codes.
-- Managers receive only public names or anonymous codes; raw anonymous account links
-- remain inside SECURITY DEFINER functions.

alter table public.debates add column if not exists creator_is_anonymous boolean not null default false;
alter table public.debates add column if not exists opponent_is_anonymous boolean;
alter table public.debate_messages add column if not exists is_anonymous boolean not null default false;
alter table public.debate_messages add column if not exists anonymous_code text;
alter table public.message_comments add column if not exists is_anonymous boolean not null default false;
alter table public.message_comments add column if not exists anonymous_code text;
alter table public.debate_comments add column if not exists is_anonymous boolean not null default false;
alter table public.debate_comments add column if not exists anonymous_code text;

create table if not exists public.debate_anonymous_identities (
  debate_id uuid not null references public.debates(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  anonymous_code text not null check (anonymous_code ~ '^[A-Z0-9]{6}$'),
  created_at timestamptz not null default now(),
  primary key (debate_id, user_id),
  unique (debate_id, anonymous_code)
);
alter table public.debate_anonymous_identities enable row level security;

create table if not exists public.anonymous_write_restrictions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  expires_at timestamptz not null,
  report_id uuid references public.reports(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.anonymous_write_restrictions enable row level security;

create or replace function public.anonymous_code_for(p_debate_id uuid, p_user_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  select anonymous_code into v_code from public.debate_anonymous_identities
  where debate_id = p_debate_id and user_id = p_user_id;
  if v_code is not null then return v_code; end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text || p_user_id::text), 1, 6));
    begin
      insert into public.debate_anonymous_identities(debate_id, user_id, anonymous_code)
      values (p_debate_id, p_user_id, v_code);
      return v_code;
    exception when unique_violation then
      -- Retry on the extremely unlikely per-debate code collision.
    end;
  end loop;
end;
$$;

create or replace function public.assert_anonymous_write_allowed(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_until timestamptz;
begin
  select expires_at into v_until from public.anonymous_write_restrictions where user_id = p_user_id;
  if v_until is not null and v_until > now() then
    raise exception '익명 글쓰기가 %까지 제한되어 있습니다.', to_char(v_until at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI');
  end if;
end;
$$;

-- First statement fixes each debater's identity mode for the whole debate.
drop function if exists public.create_debate(text, text, smallint, text);
drop function if exists public.create_debate(text, text, smallint, text, boolean);
create or replace function public.create_debate(
  p_title text, p_category text, p_duration_hours smallint, p_opening text, p_is_anonymous boolean
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_debate_id uuid; v_user_id uuid := auth.uid(); v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_duration_hours not between 1 and 24 then raise exception '토론 시간은 1~24시간으로 설정해야 합니다.'; end if;
  if p_category not in ('일상', '사회 · 정치', '연애', '문화 · 취미', '게임 · 스포츠', '학교 · 직장') then raise exception '올바른 카테고리를 선택해 주세요.'; end if;
  if char_length(trim(p_title)) not between 2 and 100 then raise exception '제목은 2~100자로 작성해 주세요.'; end if;
  if char_length(trim(p_opening)) not between 1 and 3000 then raise exception '첫 발언은 1~3,000자로 작성해 주세요.'; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); end if;
  insert into public.debates(creator_id, creator_is_anonymous, title, category, duration_hours, ends_at)
  values(v_user_id, coalesce(p_is_anonymous, false), trim(p_title), p_category, p_duration_hours, now() + make_interval(hours => p_duration_hours))
  returning id into v_debate_id;
  if coalesce(p_is_anonymous, false) then v_code := public.anonymous_code_for(v_debate_id, v_user_id); end if;
  insert into public.debate_messages(debate_id, author_id, side, body, is_anonymous, anonymous_code)
  values(v_debate_id, v_user_id, 'left', trim(p_opening), coalesce(p_is_anonymous, false), v_code);
  return v_debate_id;
end;
$$;

drop function if exists public.post_debate_message(uuid, text);
drop function if exists public.post_debate_message(uuid, text, boolean);
create or replace function public.post_debate_message(p_debate_id uuid, p_body text, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_user_id uuid := auth.uid(); v_debate public.debates%rowtype; v_side text; v_anonymous boolean; v_code text; v_message_id uuid;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 3000 then raise exception '발언은 1~3,000자로 작성해 주세요.'; end if;
  select * into v_debate from public.debates where id = p_debate_id for update;
  if not found then raise exception '토론을 찾을 수 없습니다.'; end if;
  if v_debate.status in ('ended', 'hidden') or v_debate.ends_at <= now() then raise exception '이미 종료된 토론입니다.'; end if;
  if v_user_id = v_debate.creator_id then
    v_side := 'left'; v_anonymous := v_debate.creator_is_anonymous;
  elsif v_user_id = v_debate.opponent_id then
    v_side := 'right'; v_anonymous := coalesce(v_debate.opponent_is_anonymous, false);
  elsif v_debate.opponent_id is null then
    v_side := 'right'; v_anonymous := coalesce(p_is_anonymous, false);
    update public.debates set opponent_id = v_user_id, opponent_is_anonymous = v_anonymous, status = 'active' where id = p_debate_id;
  else
    raise exception '참가자만 발언을 남길 수 있습니다.';
  end if;
  if v_anonymous then perform public.assert_anonymous_write_allowed(v_user_id); v_code := public.anonymous_code_for(p_debate_id, v_user_id); end if;
  insert into public.debate_messages(debate_id, author_id, side, body, is_anonymous, anonymous_code)
  values(p_debate_id, v_user_id, v_side, trim(p_body), v_anonymous, v_code) returning id into v_message_id;
  return v_message_id;
end;
$$;

drop function if exists public.add_message_comment(uuid, text, uuid);
drop function if exists public.add_message_comment(uuid, text, uuid, boolean);
create or replace function public.add_message_comment(p_message_id uuid, p_body text, p_parent_id uuid, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_user_id uuid := auth.uid(); v_parent_message uuid; v_debate_id uuid; v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  select m.debate_id into v_debate_id from public.debate_messages m join public.debates d on d.id = m.debate_id where m.id = p_message_id and d.status <> 'hidden';
  if v_debate_id is null then raise exception '댓글을 남길 수 없는 발언입니다.'; end if;
  if p_parent_id is not null then select message_id into v_parent_message from public.message_comments where id = p_parent_id; if v_parent_message is distinct from p_message_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); v_code := public.anonymous_code_for(v_debate_id, v_user_id); end if;
  insert into public.message_comments(message_id, author_id, body, parent_id, is_anonymous, anonymous_code)
  values(p_message_id, v_user_id, trim(p_body), p_parent_id, coalesce(p_is_anonymous, false), v_code) returning id into v_id;
  return v_id;
end;
$$;

drop function if exists public.add_debate_comment(uuid, text, uuid);
drop function if exists public.add_debate_comment(uuid, text, uuid, boolean);
create or replace function public.add_debate_comment(p_debate_id uuid, p_body text, p_parent_id uuid, p_is_anonymous boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_user_id uuid := auth.uid(); v_parent_debate uuid; v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if not exists (select 1 from public.debates d where d.id = p_debate_id and d.status <> 'hidden') then raise exception '댓글을 남길 수 없는 토론입니다.'; end if;
  if p_parent_id is not null then select debate_id into v_parent_debate from public.debate_comments where id = p_parent_id; if v_parent_debate is distinct from p_debate_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); v_code := public.anonymous_code_for(p_debate_id, v_user_id); end if;
  insert into public.debate_comments(debate_id, author_id, body, parent_id, is_anonymous, anonymous_code)
  values(p_debate_id, v_user_id, trim(p_body), p_parent_id, coalesce(p_is_anonymous, false), v_code) returning id into v_id;
  return v_id;
end;
$$;

-- Sanitised reading endpoints: anonymous rows never expose their account UUID.
create or replace function public.get_debate_detail(p_debate_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', d.id, 'status', d.status, 'title', d.title, 'category', d.category, 'ends_at', d.ends_at,
    'created_at', d.created_at, 'view_count', d.view_count,
    'opponent_present', d.opponent_id is not null,
    'viewer_side', case when auth.uid() = d.creator_id then 'left' when auth.uid() = d.opponent_id then 'right' else null end,
    'messages', coalesce((select jsonb_agg(jsonb_build_object(
      'id', m.id, 'author_id', case when m.is_anonymous then null else m.author_id end,
      'is_mine', m.author_id = auth.uid(), 'is_anonymous', m.is_anonymous, 'anonymous_code', m.anonymous_code,
      'side', m.side, 'body', m.body, 'created_at', m.created_at, 'like_count', m.like_count, 'deleted_at', m.deleted_at
    ) order by m.created_at) from public.debate_messages m where m.debate_id = d.id), '[]'::jsonb)
  )
  from public.debates d where d.id = p_debate_id and d.status <> 'hidden';
$$;

create or replace function public.get_debate_message_comments(p_debate_id uuid)
returns table(id uuid, message_id uuid, author_id uuid, is_mine boolean, parent_id uuid, body text, like_count integer, created_at timestamptz, is_anonymous boolean, anonymous_code text)
language sql stable security definer set search_path = public as $$
  select mc.id, mc.message_id, case when mc.is_anonymous then null else mc.author_id end, mc.author_id = auth.uid(), mc.parent_id, mc.body, mc.like_count, mc.created_at, mc.is_anonymous, mc.anonymous_code
  from public.message_comments mc join public.debate_messages m on m.id = mc.message_id join public.debates d on d.id = m.debate_id
  where m.debate_id = p_debate_id and d.status <> 'hidden' order by mc.created_at;
$$;

create or replace function public.get_debate_comments(p_debate_id uuid)
returns table(id uuid, debate_id uuid, author_id uuid, is_mine boolean, parent_id uuid, body text, like_count integer, created_at timestamptz, is_anonymous boolean, anonymous_code text)
language sql stable security definer set search_path = public as $$
  select dc.id, dc.debate_id, case when dc.is_anonymous then null else dc.author_id end, dc.author_id = auth.uid(), dc.parent_id, dc.body, dc.like_count, dc.created_at, dc.is_anonymous, dc.anonymous_code
  from public.debate_comments dc join public.debates d on d.id = dc.debate_id
  where dc.debate_id = p_debate_id and d.status <> 'hidden' order by dc.created_at;
$$;

-- A safe Realtime signal includes only the debate ID and timestamp.
create table if not exists public.debate_live_updates (
  debate_id uuid primary key references public.debates(id) on delete cascade,
  updated_at timestamptz not null default now()
);
alter table public.debate_live_updates enable row level security;
drop policy if exists "Live debate updates are readable" on public.debate_live_updates;
create policy "Live debate updates are readable" on public.debate_live_updates for select to anon, authenticated using (true);
grant select on public.debate_live_updates to anon, authenticated;

create or replace function public.touch_debate_live_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.debate_live_updates(debate_id, updated_at) values (new.debate_id, now())
  on conflict (debate_id) do update set updated_at = excluded.updated_at;
  return new;
end;
$$;
drop trigger if exists debate_message_live_update on public.debate_messages;
create trigger debate_message_live_update after insert or update of body, deleted_at on public.debate_messages
for each row execute function public.touch_debate_live_update();

do $$ begin
  if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'debate_messages') then
    alter publication supabase_realtime drop table public.debate_messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'debate_live_updates') then
    alter publication supabase_realtime add table public.debate_live_updates;
  end if;
end $$;

-- Direct reads would expose hidden author IDs, so all public detail reads use the
-- sanitised functions above instead.
drop policy if exists "Visible debates are readable" on public.debates;
drop policy if exists "Messages are readable" on public.debate_messages;
drop policy if exists "Comments on messages are readable" on public.message_comments;
drop policy if exists "Debate comments are readable" on public.debate_comments;

-- Report a participant by side, never by user UUID.
drop function if exists public.submit_debate_report(uuid, text, uuid);
create or replace function public.submit_debate_report(p_debate_id uuid, p_reason text, p_target_side text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_user_id uuid := auth.uid(); v_target_id uuid; v_reporter_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_target_side not in ('left', 'right') then raise exception '신고 대상을 선택해 주세요.'; end if;
  if char_length(trim(p_reason)) not between 5 and 1000 then raise exception '신고 사유는 5~1000자로 입력해 주세요.'; end if;
  select case when p_target_side = 'left' then creator_id else opponent_id end into v_target_id from public.debates where id = p_debate_id and status <> 'hidden';
  if v_target_id is null then raise exception '신고할 참가자를 찾을 수 없습니다.'; end if;
  if exists (select 1 from public.reports where reporter_id = v_user_id and debate_id = p_debate_id and status = 'open') then raise exception '이미 검토 중인 신고가 있습니다.'; end if;
  v_reporter_code := public.anonymous_code_for(p_debate_id, v_user_id);
  insert into public.reports(reporter_id, debate_id, reported_user_id, reason) values(v_user_id, p_debate_id, v_target_id, trim(p_reason)) returning id into v_id;
  return v_id;
end;
$$;

-- Manager views preserve identities chosen as public, but do not turn anonymous
-- posts into a nickname-to-account lookup.
create or replace function public.admin_reports()
returns table (id uuid, debate_id uuid, title text, category text, reason text, status text, created_at timestamptz, reporter_nickname text, reported_nickname text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select r.id, r.debate_id, d.title, d.category, r.reason, r.status, r.created_at,
    '익명 ' || public.anonymous_code_for(r.debate_id, r.reporter_id),
    case when coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = d.id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
      then '익명 ' || coalesce((select m.anonymous_code from public.debate_messages m where m.debate_id = d.id and m.author_id = r.reported_user_id order by m.created_at limit 1), '사용자')
      else coalesce(target.nickname, '탈퇴한 사용자') end
  from public.reports r join public.debates d on d.id = r.debate_id
  left join public.profiles target on target.id = r.reported_user_id
  order by case when r.status = 'open' then 0 else 1 end, r.created_at desc;
end;
$$;

create or replace function public.admin_debates()
returns table (id uuid, title text, category text, status text, created_at timestamptz, ends_at timestamptz, creator_nickname text, opponent_nickname text, messages_count bigint, comments_count bigint, votes_count bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select d.id, d.title, d.category, d.status, d.created_at, d.ends_at,
    case when d.creator_is_anonymous then '익명 ' || coalesce((select m.anonymous_code from public.debate_messages m where m.debate_id = d.id and m.side = 'left' order by m.created_at limit 1), '사용자') else coalesce(creator.nickname, '탈퇴한 사용자') end,
    case when d.opponent_id is null then '상대 미정' when d.opponent_is_anonymous then '익명 ' || coalesce((select m.anonymous_code from public.debate_messages m where m.debate_id = d.id and m.side = 'right' order by m.created_at limit 1), '사용자') else coalesce(opponent.nickname, '탈퇴한 사용자') end,
    (select count(*) from public.debate_messages m where m.debate_id = d.id),
    ((select count(*) from public.message_comments mc join public.debate_messages m on m.id = mc.message_id where m.debate_id = d.id) + (select count(*) from public.debate_comments dc where dc.debate_id = d.id)),
    (select count(*) from public.votes v where v.debate_id = d.id)
  from public.debates d
  left join public.profiles creator on creator.id = d.creator_id
  left join public.profiles opponent on opponent.id = d.opponent_id
  order by d.created_at desc;
end;
$$;

create or replace function public.admin_member_activity(p_user_id uuid)
returns table (activity_type text, body text, created_at timestamptz, debate_id uuid, debate_title text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select * from (
    select case when d.creator_is_anonymous then '익명 활동' else '토론 개설' end, case when d.creator_is_anonymous then '익명 작성 내용' else d.title end, d.created_at, case when d.creator_is_anonymous then null else d.id end, case when d.creator_is_anonymous then null else d.title end from public.debates d where d.creator_id = p_user_id
    union all select case when m.is_anonymous then '익명 활동' else '토론 발언' end, case when m.is_anonymous then '익명 작성 내용' else m.body end, m.created_at, case when m.is_anonymous then null else d.id end, case when m.is_anonymous then null else d.title end from public.debate_messages m join public.debates d on d.id = m.debate_id where m.author_id = p_user_id
    union all select case when mc.is_anonymous then '익명 활동' else '발언 댓글' end, case when mc.is_anonymous then '익명 작성 내용' else mc.body end, mc.created_at, case when mc.is_anonymous then null else d.id end, case when mc.is_anonymous then null else d.title end from public.message_comments mc join public.debate_messages m on m.id = mc.message_id join public.debates d on d.id = m.debate_id where mc.author_id = p_user_id
    union all select case when dc.is_anonymous then '익명 활동' else '관전자 댓글' end, case when dc.is_anonymous then '익명 작성 내용' else dc.body end, dc.created_at, case when dc.is_anonymous then null else d.id end, case when dc.is_anonymous then null else d.title end from public.debate_comments dc join public.debates d on d.id = dc.debate_id where dc.author_id = p_user_id
  ) activities order by created_at desc limit 50;
end;
$$;

create or replace function public.admin_restrict_anonymous_subject(p_report_id uuid, p_hours integer default 168)
returns void language plpgsql security definer set search_path = public as $$
declare v_user_id uuid;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_hours not between 1 and 8760 then raise exception '제한 시간은 1시간~365일 사이여야 합니다.'; end if;
  select reported_user_id into v_user_id from public.reports where id = p_report_id for update;
  if v_user_id is null then raise exception '신고 대상을 찾을 수 없습니다.'; end if;
  insert into public.anonymous_write_restrictions(user_id, expires_at, report_id)
  values (v_user_id, now() + make_interval(hours => p_hours), p_report_id)
  on conflict (user_id) do update set expires_at = greatest(public.anonymous_write_restrictions.expires_at, excluded.expires_at), report_id = excluded.report_id;
  update public.reports set status = 'reviewed' where id = p_report_id;
end;
$$;

create or replace function public.admin_complete_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.reports set status = 'reviewed' where id = p_report_id;
end;
$$;

-- Privileges: do not leave SECURITY DEFINER endpoints callable by PUBLIC.
revoke all on function public.anonymous_code_for(uuid, uuid) from public, anon, authenticated;
revoke all on function public.assert_anonymous_write_allowed(uuid) from public, anon, authenticated;
revoke all on function public.create_debate(text, text, smallint, text, boolean) from public, anon;
revoke all on function public.post_debate_message(uuid, text, boolean) from public, anon;
revoke all on function public.add_message_comment(uuid, text, uuid, boolean) from public, anon;
revoke all on function public.add_debate_comment(uuid, text, uuid, boolean) from public, anon;
revoke all on function public.get_debate_detail(uuid) from public;
revoke all on function public.get_debate_message_comments(uuid) from public;
revoke all on function public.get_debate_comments(uuid) from public;
revoke all on function public.submit_debate_report(uuid, text, text) from public, anon;
grant execute on function public.create_debate(text, text, smallint, text, boolean) to authenticated;
grant execute on function public.post_debate_message(uuid, text, boolean) to authenticated;
grant execute on function public.add_message_comment(uuid, text, uuid, boolean) to authenticated;
grant execute on function public.add_debate_comment(uuid, text, uuid, boolean) to authenticated;
grant execute on function public.get_debate_detail(uuid) to anon, authenticated;
grant execute on function public.get_debate_message_comments(uuid) to anon, authenticated;
grant execute on function public.get_debate_comments(uuid) to anon, authenticated;
grant execute on function public.submit_debate_report(uuid, text, text) to authenticated;
grant execute on function public.admin_restrict_anonymous_subject(uuid, integer) to authenticated;
grant execute on function public.admin_complete_report(uuid) to authenticated;

