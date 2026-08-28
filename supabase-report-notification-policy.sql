-- Report outcomes are private to the moderator and the sanctioned person.
-- Reporters are not notified of any review outcome, including dismissal or hide.

create or replace function public.admin_hide_debate(p_debate_id uuid, p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  if not exists (select 1 from public.reports where id = p_report_id and debate_id = p_debate_id and status = 'open') then
    raise exception '처리할 신고를 찾을 수 없습니다.';
  end if;
  update public.debates set status = 'hidden' where id = p_debate_id;
  update public.reports set status = 'reviewed' where id = p_report_id and debate_id = p_debate_id;
end;
$$;

create or replace function public.admin_dismiss_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.reports set status = 'dismissed' where id = p_report_id and status = 'open';
  if not found then raise exception '처리할 신고를 찾을 수 없습니다.'; end if;
end;
$$;

revoke all on function public.admin_hide_debate(uuid, uuid) from public, anon;
revoke all on function public.admin_dismiss_report(uuid) from public, anon;
grant execute on function public.admin_hide_debate(uuid, uuid) to authenticated;
grant execute on function public.admin_dismiss_report(uuid) to authenticated;

