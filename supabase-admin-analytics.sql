-- OnDebate 관리자 성장 분석
-- Supabase SQL Editor에서 한 번 실행하세요.
-- '활동 이용자'는 가입, 토론 개설/참가, 발언, 댓글, 투표 중
-- 하나 이상을 수행한 회원의 일별 고유 인원입니다.

create or replace function public.admin_growth_daily(p_days integer default 30)
returns table (
  day date,
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
    select generate_series(
      timezone('Asia/Seoul', now())::date - (v_days - 1),
      timezone('Asia/Seoul', now())::date,
      interval '1 day'
    )::date as metric_day
  ), activity as (
    select timezone('Asia/Seoul', created_at)::date as metric_day, id as user_id from public.profiles
    union
    select timezone('Asia/Seoul', created_at)::date, creator_id from public.debates
    union
    select timezone('Asia/Seoul', created_at)::date, opponent_id from public.debates where opponent_id is not null
    union
    select timezone('Asia/Seoul', created_at)::date, author_id from public.debate_messages
    union
    select timezone('Asia/Seoul', created_at)::date, author_id from public.message_comments
    union
    select timezone('Asia/Seoul', created_at)::date, author_id from public.debate_comments
    union
    select timezone('Asia/Seoul', created_at)::date, voter_id from public.votes
  ), active_counts as (
    select metric_day, count(distinct user_id)::bigint as total from activity group by metric_day
  ), signup_counts as (
    select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total
    from public.profiles group by metric_day
  ), debate_counts as (
    select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total
    from public.debates group by metric_day
  ), message_counts as (
    select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total
    from public.debate_messages group by metric_day
  ), comment_counts as (
    select metric_day, count(*)::bigint as total from (
      select timezone('Asia/Seoul', created_at)::date as metric_day from public.message_comments
      union all
      select timezone('Asia/Seoul', created_at)::date from public.debate_comments
    ) comments group by metric_day
  ), vote_counts as (
    select timezone('Asia/Seoul', created_at)::date as metric_day, count(*)::bigint as total
    from public.votes group by metric_day
  )
  select c.metric_day,
    coalesce(a.total, 0), coalesce(s.total, 0), coalesce(d.total, 0),
    coalesce(m.total, 0), coalesce(cm.total, 0), coalesce(v.total, 0)
  from calendar c
  left join active_counts a on a.metric_day = c.metric_day
  left join signup_counts s on s.metric_day = c.metric_day
  left join debate_counts d on d.metric_day = c.metric_day
  left join message_counts m on m.metric_day = c.metric_day
  left join comment_counts cm on cm.metric_day = c.metric_day
  left join vote_counts v on v.metric_day = c.metric_day
  order by c.metric_day;
end;
$$;

revoke all on function public.admin_growth_daily(integer) from public, anon;
grant execute on function public.admin_growth_daily(integer) to authenticated;

create index if not exists profiles_created_at_idx on public.profiles (created_at);
create index if not exists debates_created_at_idx on public.debates (created_at);
create index if not exists debate_messages_created_at_idx on public.debate_messages (created_at);
create index if not exists message_comments_created_at_idx on public.message_comments (created_at);
create index if not exists debate_comments_created_at_idx on public.debate_comments (created_at);
create index if not exists votes_created_at_idx on public.votes (created_at);

