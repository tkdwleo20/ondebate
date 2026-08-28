-- The moderation list intentionally does not disclose reporter identity.

drop function if exists public.admin_reports();

create function public.admin_reports()
returns table (
  id uuid, debate_id uuid, title text, category text, reason text,
  reason_type text, reason_detail text, resolution_note text, status text,
  created_at timestamptz, reported_nickname text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception '관리자 권한이 필요합니다.';
  end if;

  return query
  select
    r.id, r.debate_id, d.title, d.category, r.reason, r.reason_type,
    r.reason, r.resolution_note, r.status, r.created_at,
    case
      when coalesce((
        select m.is_anonymous
        from public.debate_messages m
        where m.debate_id = d.id and m.author_id = r.reported_user_id
        order by m.created_at
        limit 1
      ), false)
        then '익명 ' || coalesce((
          select m.anonymous_code
          from public.debate_messages m
          where m.debate_id = d.id and m.author_id = r.reported_user_id
          order by m.created_at
          limit 1
        ), '사용자')
      else coalesce(target.nickname, '탈퇴한 사용자')
    end
  from public.reports r
  join public.debates d on d.id = r.debate_id
  left join public.profiles target on target.id = r.reported_user_id
  order by case when r.status = 'open' then 0 else 1 end, r.created_at desc;
end;
$$;

revoke all on function public.admin_reports() from public, anon;
grant execute on function public.admin_reports() to authenticated;
