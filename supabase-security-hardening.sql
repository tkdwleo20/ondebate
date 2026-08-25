-- OnDebate security hardening. Run once after the existing migrations.
-- This migration keeps public display names public, but protects account data
-- and forces all state changes through the validated RPC functions.

-- Keep every public table protected by RLS, including helper tables.
alter table public.profiles enable row level security;
alter table public.debates enable row level security;
alter table public.debate_messages enable row level security;
alter table public.message_comments enable row level security;
alter table public.debate_comments enable row level security;
alter table public.votes enable row level security;
alter table public.point_ledger enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;
alter table public.admin_users enable row level security;
alter table public.debate_view_events enable row level security;
alter table public.message_likes enable row level security;
alter table public.message_comment_likes enable row level security;
alter table public.debate_comment_likes enable row level security;

-- A profile row contains points and administrative state. Only its owner can
-- read it directly; public nickname lookups use the narrow RPC below.
drop policy if exists "Public profiles are readable" on public.profiles;
drop policy if exists "Users create their own profile" on public.profiles;
drop policy if exists "Users read their own profile" on public.profiles;
create policy "Users read their own profile" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);

create or replace function public.get_public_profiles(p_ids uuid[])
returns table (id uuid, nickname text, level integer)
language sql stable security definer set search_path = public as $$
  select p.id, p.nickname, greatest(1, floor(p.points / 1000.0)::integer)
  from public.profiles p
  where p.id = any(coalesce(p_ids, '{}'::uuid[]));
$$;

create or replace function public.is_nickname_available(p_nickname text)
returns boolean
language sql stable security definer set search_path = public as $$
  select char_length(btrim(p_nickname)) between 2 and 20
    and not exists (
      select 1 from public.profiles p
      where lower(p.nickname) = lower(btrim(p_nickname))
        and p.id <> auth.uid()
    );
$$;

-- Hidden posts must not leak through their messages, comments, or vote rows.
drop policy if exists "Messages are readable" on public.debate_messages;
create policy "Messages of visible debates are readable" on public.debate_messages
  for select using (exists (
    select 1 from public.debates d where d.id = debate_id and d.status <> 'hidden'
  ));

drop policy if exists "Comments on messages are readable" on public.message_comments;
create policy "Comments of visible debates are readable" on public.message_comments
  for select using (exists (
    select 1 from public.debate_messages m
    join public.debates d on d.id = m.debate_id
    where m.id = message_id and d.status <> 'hidden'
  ));

drop policy if exists "Debate comments are readable" on public.debate_comments;
create policy "Debate comments of visible debates are readable" on public.debate_comments
  for select using (exists (
    select 1 from public.debates d where d.id = debate_id and d.status <> 'hidden'
  ));

drop policy if exists "Votes are readable" on public.votes;

-- Vote identities are not public. The UI receives only counts and its own vote.
create or replace function public.get_debate_vote_summary(p_debate_id uuid)
returns table (left_votes bigint, right_votes bigint, total_votes bigint, my_chosen_side text)
language sql stable security definer set search_path = public as $$
  select
    count(*) filter (where v.chosen_side = 'left'),
    count(*) filter (where v.chosen_side = 'right'),
    count(v.id),
    max(v.chosen_side) filter (where v.voter_id = auth.uid())
  from public.debates d
  left join public.votes v on v.debate_id = d.id
  where d.id = p_debate_id and d.status <> 'hidden';
$$;

create or replace function public.weekly_win_rankings()
returns table (user_id uuid, nickname text, wins bigint, total bigint)
language sql stable security definer set search_path = public as $$
  with results as (
    select d.creator_id, d.opponent_id,
      case
        when count(v.id) filter (where v.chosen_side = 'left') > count(v.id) filter (where v.chosen_side = 'right') then d.creator_id
        when count(v.id) filter (where v.chosen_side = 'right') > count(v.id) filter (where v.chosen_side = 'left') then d.opponent_id
      end as winner_id
    from public.debates d
    left join public.votes v on v.debate_id = d.id
    where d.status = 'ended' and d.ends_at >= now() - interval '7 days' and d.opponent_id is not null
    group by d.id
  ), records as (
    select creator_id as user_id, winner_id from results where winner_id is not null
    union all
    select opponent_id as user_id, winner_id from results where winner_id is not null
  )
  select r.user_id, p.nickname,
    count(*) filter (where r.winner_id = r.user_id) as wins,
    count(*) as total
  from records r join public.profiles p on p.id = r.user_id
  group by r.user_id, p.nickname
  order by (count(*) filter (where r.winner_id = r.user_id))::numeric / count(*) desc, wins desc, total desc
  limit 3;
$$;

create or replace function public.my_debate_outcomes()
returns table (wins bigint, total bigint)
language sql stable security definer set search_path = public as $$
  with results as (
    select d.creator_id, d.opponent_id,
      case
        when count(v.id) filter (where v.chosen_side = 'left') > count(v.id) filter (where v.chosen_side = 'right') then d.creator_id
        when count(v.id) filter (where v.chosen_side = 'right') > count(v.id) filter (where v.chosen_side = 'left') then d.opponent_id
      end as winner_id
    from public.debates d
    left join public.votes v on v.debate_id = d.id
    where d.status = 'ended' and d.status <> 'hidden' and (d.creator_id = auth.uid() or d.opponent_id = auth.uid())
    group by d.id
  )
  select count(*) filter (where winner_id = auth.uid()), count(*)
  from results where winner_id is not null;
$$;

-- Do not let clients bypass participation, point, time-limit, or reply rules.
drop policy if exists "Users create their own debate" on public.debates;
drop policy if exists "Creator can update waiting debate" on public.debates;
drop policy if exists "Signed-in users add message comments" on public.message_comments;
drop policy if exists "Signed-in users add debate comments" on public.debate_comments;
drop policy if exists "A non-participant votes once" on public.votes;

-- These helper tables are deliberately accessed only through privileged RPCs.
drop policy if exists "No direct admin user access" on public.admin_users;
drop policy if exists "No direct debate view event access" on public.debate_view_events;
drop policy if exists "No direct vote access" on public.votes;
create policy "No direct admin user access" on public.admin_users as restrictive for all using (false) with check (false);
create policy "No direct debate view event access" on public.debate_view_events as restrictive for all using (false) with check (false);
create policy "No direct vote access" on public.votes as restrictive for all using (false) with check (false);

-- The comment RPCs may only target a visible debate.
create or replace function public.add_message_comment(p_message_id uuid, p_body text, p_parent_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; current_user_id uuid := auth.uid(); parent_message_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if not exists (select 1 from public.debate_messages m join public.debates d on d.id=m.debate_id where m.id=p_message_id and d.status <> 'hidden') then raise exception '댓글을 남길 수 없는 발언입니다.'; end if;
  if p_parent_id is not null then select message_id into parent_message_id from public.message_comments where id = p_parent_id; if parent_message_id is distinct from p_message_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  insert into public.message_comments (message_id, author_id, body, parent_id) values (p_message_id, current_user_id, trim(p_body), p_parent_id) returning id into new_id;
  return new_id;
end; $$;

create or replace function public.add_debate_comment(p_debate_id uuid, p_body text, p_parent_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; current_user_id uuid := auth.uid(); parent_debate_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if not exists (select 1 from public.debates d where d.id=p_debate_id and d.status <> 'hidden') then raise exception '댓글을 남길 수 없는 토론입니다.'; end if;
  if p_parent_id is not null then select debate_id into parent_debate_id from public.debate_comments where id = p_parent_id; if parent_debate_id is distinct from p_debate_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  insert into public.debate_comments (debate_id, author_id, body, parent_id) values (p_debate_id, current_user_id, trim(p_body), p_parent_id) returning id into new_id;
  return new_id;
end; $$;

-- Validate categories inside the privileged creation function as well.
create or replace function public.create_debate(p_title text, p_category text, p_duration_hours smallint, p_opening text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_debate_id uuid; current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_duration_hours not between 1 and 24 then raise exception '토론 시간은 1~24시간으로 설정해야 합니다.'; end if;
  if p_category not in ('일상', '사회 · 정치', '연애', '문화 · 취미', '게임 · 스포츠', '학교 · 직장') then raise exception '올바른 카테고리를 선택해 주세요.'; end if;
  if char_length(trim(p_title)) not between 2 and 100 then raise exception '제목은 2~100자로 작성해 주세요.'; end if;
  if char_length(trim(p_opening)) not between 1 and 3000 then raise exception '첫 발언은 1~3,000자로 작성해 주세요.'; end if;
  insert into public.debates (creator_id, title, category, duration_hours, ends_at)
  values (current_user_id, trim(p_title), p_category, p_duration_hours, now() + make_interval(hours => p_duration_hours)) returning id into new_debate_id;
  insert into public.debate_messages (debate_id, author_id, side, body)
  values (new_debate_id, current_user_id, 'left', trim(p_opening));
  return new_debate_id;
end; $$;

-- SECURITY DEFINER functions otherwise receive PUBLIC EXECUTE by default.
-- Revoke first, then grant only the role each endpoint needs.
revoke all on function public.get_public_profiles(uuid[]) from public, anon, authenticated;
revoke all on function public.is_nickname_available(text) from public, anon, authenticated;
revoke all on function public.record_debate_view(uuid, text) from public, anon, authenticated;
revoke all on function public.get_debate_vote_summary(uuid) from public, anon, authenticated;
revoke all on function public.weekly_win_rankings() from public, anon, authenticated;
revoke all on function public.my_debate_outcomes() from public, anon, authenticated;
revoke all on function public.create_debate(text, text, smallint, text) from public, anon;
revoke all on function public.post_debate_message(uuid, text) from public, anon;
revoke all on function public.add_message_comment(uuid, text, uuid) from public, anon;
revoke all on function public.add_debate_comment(uuid, text, uuid) from public, anon;
revoke all on function public.toggle_message_like(uuid) from public, anon;
revoke all on function public.toggle_message_comment_like(uuid) from public, anon;
revoke all on function public.toggle_debate_comment_like(uuid) from public, anon;
revoke all on function public.cast_debate_vote(uuid, text) from public, anon;
revoke all on function public.delete_message_comment(uuid) from public, anon;
revoke all on function public.delete_debate_comment(uuid) from public, anon;
revoke all on function public.set_nickname(text, boolean) from public, anon;
revoke all on function public.daily_checkin() from public, anon;
revoke all on function public.settle_debate_points(uuid) from public, anon;
revoke all on function public.settle_expired_debates() from public, anon;
revoke all on function public.submit_debate_report(uuid, text, uuid) from public, anon;
revoke all on function public.admin_reports() from public, anon;
revoke all on function public.admin_hide_debate(uuid, uuid) from public, anon;
revoke all on function public.admin_set_debate_visibility(uuid, boolean) from public, anon;
revoke all on function public.admin_delete_debate(uuid) from public, anon;
revoke all on function public.admin_debates() from public, anon;
revoke all on function public.admin_members() from public, anon;
revoke all on function public.admin_member_activity(uuid) from public, anon;
revoke all on function public.admin_dismiss_report(uuid) from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.notify_opponent_message() from public, anon, authenticated;
revoke all on function public.notify_message_comment() from public, anon, authenticated;
revoke all on function public.notify_debate_comment() from public, anon, authenticated;

grant execute on function public.get_public_profiles(uuid[]) to anon, authenticated;
grant execute on function public.is_nickname_available(text) to authenticated;
grant execute on function public.record_debate_view(uuid, text) to anon, authenticated;
grant execute on function public.get_debate_vote_summary(uuid) to anon, authenticated;
grant execute on function public.weekly_win_rankings() to anon, authenticated;
grant execute on function public.my_debate_outcomes() to authenticated;
grant execute on function public.create_debate(text, text, smallint, text) to authenticated;
grant execute on function public.post_debate_message(uuid, text) to authenticated;
grant execute on function public.add_message_comment(uuid, text, uuid) to authenticated;
grant execute on function public.add_debate_comment(uuid, text, uuid) to authenticated;
grant execute on function public.toggle_message_like(uuid) to authenticated;
grant execute on function public.toggle_message_comment_like(uuid) to authenticated;
grant execute on function public.toggle_debate_comment_like(uuid) to authenticated;
grant execute on function public.cast_debate_vote(uuid, text) to authenticated;
grant execute on function public.delete_message_comment(uuid) to authenticated;
grant execute on function public.delete_debate_comment(uuid) to authenticated;
grant execute on function public.set_nickname(text, boolean) to authenticated;
grant execute on function public.daily_checkin() to authenticated;
grant execute on function public.settle_debate_points(uuid) to authenticated;
grant execute on function public.settle_expired_debates() to authenticated;
grant execute on function public.submit_debate_report(uuid, text, uuid) to authenticated;
grant execute on function public.admin_reports() to authenticated;
grant execute on function public.admin_hide_debate(uuid, uuid) to authenticated;
grant execute on function public.admin_set_debate_visibility(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_debate(uuid) to authenticated;
grant execute on function public.admin_debates() to authenticated;
grant execute on function public.admin_members() to authenticated;
grant execute on function public.admin_member_activity(uuid) to authenticated;
grant execute on function public.admin_dismiss_report(uuid) to authenticated;
grant execute on function public.is_admin() to authenticated;
