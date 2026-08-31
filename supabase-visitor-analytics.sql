-- OnDebate 단순 방문자를 포함한 성장 분석
-- 기존 supabase-admin-analytics.sql 실행 여부와 관계없이 추가로 한 번 실행하세요.

create table if not exists public.daily_site_visitors (
  visit_day date not null,
  visitor_key uuid not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (visit_day, visitor_key)
);

alter table public.daily_site_visitors enable row level security;

create or replace function public.record_site_visit(p_visitor_key uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.daily_site_visitors (visit_day, visitor_key)
  values (timezone('Asia/Seoul', now())::date, p_visitor_key)
  on conflict (visit_day, visitor_key) do update
    set last_seen_at = now();
end;
$$;

revoke all on function public.record_site_visit(uuid) from public;
grant execute on function public.record_site_visit(uuid) to anon, authenticated;

create or replace function public.admin_growth_daily_v2(p_days integer default 30)
returns table (
  day date,
  visitors bigint,
  active_users bigint,
  new_signups bigint,
  debates_created bigint,
  messages_created bigint,
  comments_created bigint,
  votes_created bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days integer := greatest(7, least(coalesce(p_days, 30), 365));
begin
  if not public.is_admin() then
    raise exception '관리자 권한이 필요합니다.' using errcode = '42501';
  end if;

  return query
  with calendar as (
    select generate_series(timezone('Asia/Seoul', now())::date - (v_days - 1), timezone('Asia/Seoul', now())::date, interval '1 day')::date as metric_day
  ), visitor_counts as (
    select visit_day as metric_day, count(*)::bigint as total from public.daily_site_visitors group by visit_day
  ), activity as (
    select timezone('Asia/Seoul', created_at)::date as metric_day, id as user_id from public.profiles
    union select timezone('Asia/Seoul', created_at)::date, creator_id from public.debates
    union select timezone('Asia/Seoul', created_at)::date, opponent_id from public.debates where opponent_id is not null
    union select timezone('Asia/Seoul', created_at)::date, author_id from public.debate_messages
    union select timezone('Asia/Seoul', created_at)::date, author_id from public.message_comments
    union select timezone('Asia/Seoul', created_at)::date, author_id from public.debate_comments
    union select timezone('Asia/Seoul', created_at)::date, voter_id from public.votes
  ), active_counts as (
    select metric_day, count(distinct user_id)::bigint as total from activity group by metric_day
  ), signup_counts as (select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total from public.profiles group by metric_day),
  debate_counts as (select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total from public.debates group by metric_day),
  message_counts as (select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total from public.debate_messages group by metric_day),
  comment_counts as (
    select metric_day, count(*)::bigint as total from (
      select timezone('Asia/Seoul', created_at)::date as metric_day from public.message_comments
      union all select timezone('Asia/Seoul', created_at)::date from public.debate_comments
    ) comments group by metric_day
  ), vote_counts as (select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total from public.votes group by metric_day)
  select c.metric_day, coalesce(vc.total,0), coalesce(a.total,0), coalesce(s.total,0), coalesce(d.total,0), coalesce(m.total,0), coalesce(cm.total,0), coalesce(v.total,0)
  from calendar c
  left join visitor_counts vc on vc.metric_day=c.metric_day
  left join active_counts a on a.metric_day=c.metric_day
  left join signup_counts s on s.metric_day=c.metric_day
  left join debate_counts d on d.metric_day=c.metric_day
  left join message_counts m on m.metric_day=c.metric_day
  left join comment_counts cm on cm.metric_day=c.metric_day
  left join vote_counts v on v.metric_day=c.metric_day
  order by c.metric_day;
end;
$$;

revoke all on function public.admin_growth_daily_v2(integer) from public, anon;
grant execute on function public.admin_growth_daily_v2(integer) to authenticated;

