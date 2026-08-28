-- Repeat-report sanction escalation.
-- Three separate 1-day sanctions within a rolling 90-day window result in a
-- 7-day site-wide writing restriction. The audit table is not exposed to users
-- or the normal admin UI, so anonymous authors remain anonymous to admins.

create table if not exists public.writing_restriction_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  report_id uuid references public.reports(id) on delete set null,
  restriction_kind text not null check (restriction_kind in ('public', 'anonymous')),
  duration_hours integer not null check (duration_hours in (24, 168)),
  created_at timestamptz not null default now()
);

alter table public.writing_restriction_events enable row level security;
create index if not exists writing_restriction_events_user_created_idx
  on public.writing_restriction_events (user_id, created_at desc);

create or replace function public.record_one_day_restriction_and_should_escalate(
  p_user_id uuid,
  p_report_id uuid,
  p_kind text
)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  insert into public.writing_restriction_events(user_id, report_id, restriction_kind, duration_hours)
  values (p_user_id, p_report_id, p_kind, 24);

  select count(*) into v_count
  from public.writing_restriction_events
  where user_id = p_user_id
    and duration_hours = 24
    and created_at >= now() - interval '90 days';

  return v_count >= 3;
end;
$$;

create or replace function public.admin_restrict_public_subject(p_report_id uuid, p_hours integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_is_anonymous boolean;
  v_debate_id uuid;
  v_until timestamptz;
  v_escalated boolean := false;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_hours not in (24, 168) then raise exception '제한 시간은 1일 또는 7일만 가능합니다.'; end if;

  select r.reported_user_id, r.debate_id,
    coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = r.debate_id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
  into v_user_id, v_debate_id, v_is_anonymous
  from public.reports r where r.id = p_report_id and r.status = 'open';

  if v_user_id is null then raise exception '처리할 신고를 찾을 수 없습니다.'; end if;
  if v_is_anonymous then raise exception '익명 글 신고에는 익명 글쓰기 제한만 적용할 수 있습니다.'; end if;

  if p_hours = 24 then
    v_escalated := public.record_one_day_restriction_and_should_escalate(v_user_id, p_report_id, 'public');
  end if;

  v_until := now() + make_interval(hours => case when v_escalated then 168 else p_hours end);
  insert into public.write_restrictions(user_id, expires_at, report_id)
  values (v_user_id, v_until, p_report_id)
  on conflict (user_id) do update
    set expires_at = greatest(public.write_restrictions.expires_at, excluded.expires_at),
        report_id = excluded.report_id
  returning expires_at into v_until;

  update public.reports set status = 'reviewed' where id = p_report_id;
  if v_escalated then
    perform public.create_notification(v_user_id, auth.uid(), v_debate_id, 'report_result',
      format('반복 신고 제재로 글쓰기 7일 제한이 적용되었습니다. 제한 종료: %s', to_char(v_until at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일 HH24:MI')),
      'repeat-writing-restriction:' || p_report_id::text);
  else
    perform public.create_notification(v_user_id, auth.uid(), v_debate_id, 'report_result',
      format('글쓰기 %s일 제한이 적용되었습니다. 제한 종료: %s', p_hours / 24, to_char(v_until at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일 HH24:MI')),
      'writing-restriction:' || p_report_id::text || ':' || p_hours::text);
  end if;
end;
$$;

create or replace function public.admin_restrict_anonymous_subject(p_report_id uuid, p_hours integer default 168)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_is_anonymous boolean;
  v_debate_id uuid;
  v_until timestamptz;
  v_escalated boolean := false;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_hours not in (24, 168) then raise exception '제한 시간은 1일 또는 7일만 가능합니다.'; end if;

  select r.reported_user_id, r.debate_id,
    coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = r.debate_id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
  into v_user_id, v_debate_id, v_is_anonymous
  from public.reports r where r.id = p_report_id and r.status = 'open';

  if v_user_id is null then raise exception '처리할 신고를 찾을 수 없습니다.'; end if;
  if not v_is_anonymous then raise exception '닉네임 글 신고에는 글쓰기 제한을 적용해 주세요.'; end if;

  if p_hours = 24 then
    v_escalated := public.record_one_day_restriction_and_should_escalate(v_user_id, p_report_id, 'anonymous');
  end if;

  if v_escalated then
    v_until := now() + interval '168 hours';
    insert into public.write_restrictions(user_id, expires_at, report_id)
    values (v_user_id, v_until, p_report_id)
    on conflict (user_id) do update
      set expires_at = greatest(public.write_restrictions.expires_at, excluded.expires_at),
          report_id = excluded.report_id
    returning expires_at into v_until;
  else
    v_until := now() + make_interval(hours => p_hours);
    insert into public.anonymous_write_restrictions(user_id, expires_at, report_id)
    values (v_user_id, v_until, p_report_id)
    on conflict (user_id) do update
      set expires_at = greatest(public.anonymous_write_restrictions.expires_at, excluded.expires_at),
          report_id = excluded.report_id
    returning expires_at into v_until;
  end if;

  update public.reports set status = 'reviewed' where id = p_report_id;
  if v_escalated then
    perform public.create_notification(v_user_id, auth.uid(), v_debate_id, 'report_result',
      format('반복 신고 제재로 글쓰기 7일 제한이 적용되었습니다. 제한 종료: %s', to_char(v_until at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일 HH24:MI')),
      'repeat-writing-restriction:' || p_report_id::text);
  else
    perform public.create_notification(v_user_id, auth.uid(), v_debate_id, 'report_result',
      format('익명 글쓰기 %s일 제한이 적용되었습니다. 제한 종료: %s', p_hours / 24, to_char(v_until at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일 HH24:MI')),
      'anonymous-writing-restriction:' || p_report_id::text || ':' || p_hours::text);
  end if;
end;
$$;

revoke all on table public.writing_restriction_events from public, anon, authenticated;
revoke all on function public.record_one_day_restriction_and_should_escalate(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.admin_restrict_public_subject(uuid, integer) to authenticated;
grant execute on function public.admin_restrict_anonymous_subject(uuid, integer) to authenticated;

