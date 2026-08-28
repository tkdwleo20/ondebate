-- Internal processing notes for report decisions.

alter table public.reports add column if not exists resolution_note text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reports_resolution_note_check' and conrelid = 'public.reports'::regclass) then
    alter table public.reports add constraint reports_resolution_note_check
      check (resolution_note is null or char_length(trim(resolution_note)) between 1 and 1000);
  end if;
end;
$$;

create or replace function public.admin_set_report_resolution_note(p_report_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if v_note is not null and char_length(v_note) > 1000 then raise exception '처리 메모는 1,000자 이내로 입력해 주세요.'; end if;
  update public.reports set resolution_note = v_note where id = p_report_id and status = 'open';
  if not found then raise exception '처리할 신고를 찾을 수 없습니다.'; end if;
end;
$$;

drop function if exists public.admin_reports();
create function public.admin_reports()
returns table (
  id uuid, debate_id uuid, title text, category text, reason text,
  reason_type text, reason_detail text, resolution_note text, status text,
  created_at timestamptz, reporter_nickname text, reported_nickname text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select r.id, r.debate_id, d.title, d.category, r.reason, r.reason_type, r.reason, r.resolution_note, r.status, r.created_at,
    '익명 ' || public.anonymous_code_for(r.debate_id, r.reporter_id),
    case when coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = d.id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
      then '익명 ' || coalesce((select m.anonymous_code from public.debate_messages m where m.debate_id = d.id and m.author_id = r.reported_user_id order by m.created_at limit 1), '사용자')
      else coalesce(target.nickname, '탈퇴한 사용자') end
  from public.reports r join public.debates d on d.id = r.debate_id
  left join public.profiles target on target.id = r.reported_user_id
  order by case when r.status = 'open' then 0 else 1 end, r.created_at desc;
end;
$$;

revoke all on function public.admin_set_report_resolution_note(uuid, text) from public, anon;
grant execute on function public.admin_set_report_resolution_note(uuid, text) to authenticated;
grant execute on function public.admin_reports() to authenticated;

