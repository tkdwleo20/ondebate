-- Keep anonymous activity completely out of the administrator member-history view.

create or replace function public.admin_member_activity(p_user_id uuid)
returns table (activity_type text, body text, created_at timestamptz, debate_id uuid, debate_title text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select * from (
    select '토론 개설'::text, d.title, d.created_at, d.id, d.title
    from public.debates d
    where d.creator_id = p_user_id and not d.creator_is_anonymous
    union all
    select '토론 발언'::text, m.body, m.created_at, d.id, d.title
    from public.debate_messages m join public.debates d on d.id = m.debate_id
    where m.author_id = p_user_id and not m.is_anonymous
    union all
    select '발언 댓글'::text, mc.body, mc.created_at, d.id, d.title
    from public.message_comments mc join public.debate_messages m on m.id = mc.message_id join public.debates d on d.id = m.debate_id
    where mc.author_id = p_user_id and not mc.is_anonymous
    union all
    select '관전자 댓글'::text, dc.body, dc.created_at, d.id, d.title
    from public.debate_comments dc join public.debates d on d.id = dc.debate_id
    where dc.author_id = p_user_id and not dc.is_anonymous
  ) activities order by created_at desc limit 50;
end;
$$;

revoke all on function public.admin_member_activity(uuid) from public, anon;
grant execute on function public.admin_member_activity(uuid) to authenticated;

