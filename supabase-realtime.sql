-- 상세 토론 화면의 발언 자동 갱신용 Realtime 등록
-- 이미 등록되어 있어도 오류 없이 다시 실행할 수 있습니다.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'debate_messages'
  ) then
    alter publication supabase_realtime add table public.debate_messages;
  end if;
end;
$$;

