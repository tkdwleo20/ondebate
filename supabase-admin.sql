-- OnDebate admin and report tools. Run once in Supabase SQL Editor.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
alter table public.reports add column if not exists reported_user_id uuid references public.profiles(id) on delete set null;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated;

drop function if exists public.submit_debate_report(uuid, text);
create or replace function public.submit_debate_report(p_debate_id uuid, p_reason text, p_reported_user_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare report_id uuid; current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_reason)) < 5 or char_length(trim(p_reason)) > 1000 then raise exception '신고 사유는 5~1000자로 입력해 주세요.'; end if;
  if not exists (select 1 from public.debates where id = p_debate_id and status <> 'hidden') then raise exception '신고할 토론을 찾을 수 없습니다.'; end if;
  if not exists (select 1 from public.debates where id = p_debate_id and (creator_id = p_reported_user_id or opponent_id = p_reported_user_id)) then raise exception '이 토론의 참가자만 신고 대상으로 선택할 수 있습니다.'; end if;
  if exists (select 1 from public.reports where reporter_id = current_user_id and debate_id = p_debate_id and status = 'open') then raise exception '이미 검토 중인 신고가 있습니다.'; end if;
  insert into public.reports (reporter_id, debate_id, reported_user_id, reason) values (current_user_id, p_debate_id, p_reported_user_id, trim(p_reason)) returning id into report_id;
  return report_id;
end; $$;
grant execute on function public.submit_debate_report(uuid, text, uuid) to authenticated;

drop function if exists public.admin_reports();
create or replace function public.admin_reports()
returns table (id uuid, debate_id uuid, title text, category text, reason text, status text, created_at timestamptz, reporter_nickname text, reported_nickname text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query select r.id, r.debate_id, d.title, d.category, r.reason, r.status, r.created_at, coalesce(p.nickname, '탈퇴한 사용자'), coalesce(target.nickname, '선택되지 않음')
  from public.reports r join public.debates d on d.id = r.debate_id left join public.profiles p on p.id = r.reporter_id left join public.profiles target on target.id = r.reported_user_id
  order by case when r.status = 'open' then 0 else 1 end, r.created_at desc;
end; $$;
grant execute on function public.admin_reports() to authenticated;

create or replace function public.admin_hide_debate(p_debate_id uuid, p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.debates set status = 'hidden' where id = p_debate_id;
  update public.reports set status = 'reviewed' where id = p_report_id and debate_id = p_debate_id;
end; $$;
grant execute on function public.admin_hide_debate(uuid, uuid) to authenticated;

create or replace function public.admin_delete_debate(p_debate_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  delete from public.debates where id = p_debate_id;
end; $$;
grant execute on function public.admin_delete_debate(uuid) to authenticated;

create or replace function public.admin_debates()
returns table (id uuid, title text, category text, status text, created_at timestamptz, ends_at timestamptz, creator_nickname text, opponent_nickname text, messages_count bigint, comments_count bigint, votes_count bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query select d.id, d.title, d.category, d.status, d.created_at, d.ends_at,
    coalesce(creator.nickname, '탈퇴한 사용자'), coalesce(opponent.nickname, '상대 미정'),
    (select count(*) from public.debate_messages m where m.debate_id = d.id),
    ((select count(*) from public.message_comments mc join public.debate_messages m on m.id = mc.message_id where m.debate_id = d.id) + (select count(*) from public.debate_comments dc where dc.debate_id = d.id)),
    (select count(*) from public.votes v where v.debate_id = d.id)
  from public.debates d
  left join public.profiles creator on creator.id = d.creator_id
  left join public.profiles opponent on opponent.id = d.opponent_id
  order by d.created_at desc;
end; $$;
grant execute on function public.admin_debates() to authenticated;

create or replace function public.admin_members()
returns table (user_id uuid, nickname text, points integer, joined_at timestamptz, debates_count bigint, messages_count bigint, comments_count bigint, reports_received bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query select p.id, p.nickname, p.points, p.created_at,
    (select count(*) from public.debates d where d.creator_id = p.id or d.opponent_id = p.id),
    (select count(*) from public.debate_messages m where m.author_id = p.id),
    ((select count(*) from public.message_comments mc where mc.author_id = p.id) + (select count(*) from public.debate_comments dc where dc.author_id = p.id)),
    (select count(*) from public.reports r where r.reported_user_id = p.id)
  from public.profiles p order by p.created_at desc;
end; $$;
grant execute on function public.admin_members() to authenticated;

create or replace function public.admin_member_activity(p_user_id uuid)
returns table (activity_type text, body text, created_at timestamptz, debate_id uuid, debate_title text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select * from (
    select '토론 개설'::text, d.title, d.created_at, d.id, d.title from public.debates d where d.creator_id = p_user_id
    union all select '토론 발언'::text, m.body, m.created_at, d.id, d.title from public.debate_messages m join public.debates d on d.id = m.debate_id where m.author_id = p_user_id
    union all select '발언 댓글'::text, mc.body, mc.created_at, d.id, d.title from public.message_comments mc join public.debate_messages m on m.id = mc.message_id join public.debates d on d.id = m.debate_id where mc.author_id = p_user_id
    union all select '관전자 댓글'::text, dc.body, dc.created_at, d.id, d.title from public.debate_comments dc join public.debates d on d.id = dc.debate_id where dc.author_id = p_user_id
  ) activities order by created_at desc limit 50;
end; $$;
grant execute on function public.admin_member_activity(uuid) to authenticated;

create or replace function public.admin_dismiss_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.reports set status = 'dismissed' where id = p_report_id;
end; $$;
grant execute on function public.admin_dismiss_report(uuid) to authenticated;

-- Make your existing account an administrator. Replace the nickname before running.
-- insert into public.admin_users (user_id) select id from public.profiles where nickname = '내 닉네임';

