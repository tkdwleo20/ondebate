-- OnDebate notification clearing. Run once after the existing migrations.
create or replace function public.clear_my_notifications()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  delete from public.notifications where recipient_id = auth.uid();
end;
$$;

revoke all on function public.clear_my_notifications() from public, anon, authenticated;
grant execute on function public.clear_my_notifications() to authenticated;

