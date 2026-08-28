-- Show the completed moderation action in the admin report list.

drop function if exists public.admin_reports();

create function public.admin_reports()
returns table (
  id uuid, debate_id uuid, title text, category text, reason text,
  reason_type text, reason_detail text, resolution_note text, status text,
  created_at timestamptz, reported_nickname text, resolution_action text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select r.id, r.debate_id, d.title, d.category, r.reason, r.reason_type,
    r.reason, r.resolution_note, r.status, r.created_at,
    case when coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id=d.id and m.author_id=r.reported_user_id order by m.created_at limit 1),false)
      then '익명 ' || coalesce((select m.anonymous_code from public.debate_messages m where m.debate_id=d.id and m.author_id=r.reported_user_id order by m.created_at limit 1),'사용자')
      else coalesce(target.nickname,'탈퇴한 사용자') end,
    case
      when r.status = 'reviewed' and wr.report_id is not null then '글쓰기 제한'
      when r.status = 'reviewed' and awr.report_id is not null then '익명 글쓰기 제한'
      when r.status = 'reviewed' and d.status = 'hidden' then '게시물 숨김'
      when r.status = 'reviewed' then '처리 완료'
      else null
    end
  from public.reports r
  join public.debates d on d.id=r.debate_id
  left join public.profiles target on target.id=r.reported_user_id
  left join public.write_restrictions wr on wr.report_id=r.id
  left join public.anonymous_write_restrictions awr on awr.report_id=r.id
  order by case when r.status='open' then 0 else 1 end, r.created_at desc;
end;
$$;

revoke all on function public.admin_reports() from public, anon;
grant execute on function public.admin_reports() to authenticated;

