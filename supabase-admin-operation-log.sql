-- OnDebate administrator operation log.
-- Run once in Supabase SQL Editor. The log is append-only: administrators can read it,
-- but no browser role can update or delete its rows.

create table if not exists public.admin_operation_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  admin_id uuid references public.profiles(id) on delete set null,
  action_type text not null,
  target_type text not null,
  target_id text,
  target_label text,
  reason text,
  details jsonb not null default '{}'::jsonb
);

-- Older projects may not yet have these report resolution columns.
alter table public.reports add column if not exists resolution_action text;
alter table public.reports add column if not exists resolution_note text;

create index if not exists admin_operation_logs_created_at_idx
  on public.admin_operation_logs (created_at desc);
create index if not exists admin_operation_logs_target_idx
  on public.admin_operation_logs (target_type, target_id);

alter table public.admin_operation_logs enable row level security;
drop policy if exists "No direct admin operation log access" on public.admin_operation_logs;
create policy "No direct admin operation log access"
  on public.admin_operation_logs as restrictive for all using (false) with check (false);

create or replace function public.admin_operation_log_page(p_limit integer default 50, p_offset integer default 0)
returns table (
  id uuid, created_at timestamptz, admin_nickname text, action_type text,
  target_type text, target_id text, target_label text, reason text, details jsonb
)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select l.id, l.created_at, coalesce(p.nickname, '알 수 없음'), l.action_type,
         l.target_type, l.target_id, l.target_label, l.reason, l.details
    from public.admin_operation_logs l
    left join public.profiles p on p.id = l.admin_id
   order by l.created_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 100))
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.admin_record_policy_change(
  p_category text,
  p_summary text,
  p_detail text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if p_category not in ('운영 정책', '제재 기준') then raise exception '허용되지 않은 변경 분류입니다.'; end if;
  if char_length(trim(coalesce(p_summary, ''))) < 2 then raise exception '변경 요약을 2자 이상 입력해 주세요.'; end if;

  insert into public.admin_operation_logs
    (admin_id, action_type, target_type, target_label, reason, details)
  values
    (auth.uid(), 'policy_changed', 'policy', p_category, trim(p_summary),
     jsonb_build_object('detail', nullif(trim(coalesce(p_detail, '')), '')))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.audit_admin_debate_status_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_admin() and old.status is distinct from new.status
     and (old.status = 'hidden' or new.status = 'hidden') then
    insert into public.admin_operation_logs
      (admin_id, action_type, target_type, target_id, target_label, details)
    values
      (auth.uid(), case when new.status = 'hidden' then 'debate_hidden' else 'debate_unhidden' end,
       'debate', new.id::text, new.title,
       jsonb_build_object('before_status', old.status, 'after_status', new.status));
  end if;
  return new;
end;
$$;

create or replace function public.audit_admin_debate_delete()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_admin() then
    insert into public.admin_operation_logs
      (admin_id, action_type, target_type, target_id, target_label, details)
    values
      (auth.uid(), 'debate_deleted', 'debate', old.id::text, old.title,
       jsonb_build_object('status', old.status, 'category', old.category));
  end if;
  return old;
end;
$$;

create or replace function public.audit_admin_report_resolution()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_admin() and old.status = 'open' and new.status <> 'open' then
    insert into public.admin_operation_logs
      (admin_id, action_type, target_type, target_id, target_label, reason, details)
    values
      (auth.uid(), 'report_processed', 'report', new.id::text, '신고 처리',
       coalesce(new.resolution_action, case when new.status = 'dismissed' then '신고 기각' else '신고 처리' end),
       jsonb_strip_nulls(jsonb_build_object(
         'report_status', new.status,
         'debate_id', new.debate_id,
         'reported_user_id', new.reported_user_id,
         'admin_note', new.resolution_note
       )));
  end if;
  return new;
end;
$$;

drop trigger if exists audit_admin_debate_status_change on public.debates;
create trigger audit_admin_debate_status_change
after update of status on public.debates
for each row execute function public.audit_admin_debate_status_change();

drop trigger if exists audit_admin_debate_delete on public.debates;
create trigger audit_admin_debate_delete
before delete on public.debates
for each row execute function public.audit_admin_debate_delete();

drop trigger if exists audit_admin_report_resolution on public.reports;
create trigger audit_admin_report_resolution
after update of status on public.reports
for each row execute function public.audit_admin_report_resolution();

revoke all on table public.admin_operation_logs from public, anon, authenticated;
revoke all on function public.admin_operation_log_page(integer, integer) from public, anon;
revoke all on function public.admin_record_policy_change(text, text, text) from public, anon;
grant execute on function public.admin_operation_log_page(integer, integer) to authenticated;
grant execute on function public.admin_record_policy_change(text, text, text) to authenticated;

