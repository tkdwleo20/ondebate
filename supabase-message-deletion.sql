-- OnDebate message deletion. Run once after the existing migrations.
-- Deleted messages keep their comment thread but no longer accept new comments.

alter table public.debate_messages
  add column if not exists deleted_at timestamptz;

create or replace function public.delete_debate_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_message public.debate_messages%rowtype;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_message
  from public.debate_messages
  where id = p_message_id
  for update;

  if not found or v_message.author_id <> v_user_id then
    raise exception '본인이 작성한 발언만 삭제할 수 있습니다.';
  end if;
  if v_message.deleted_at is not null then
    raise exception '이미 삭제된 발언입니다.';
  end if;

  update public.debate_messages
  set body = '삭제된 발언입니다.', deleted_at = now()
  where id = p_message_id;
end;
$$;

-- Existing comments remain readable, but new comments and replies are blocked.
create or replace function public.add_message_comment(p_message_id uuid, p_body text, p_parent_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; current_user_id uuid := auth.uid(); parent_message_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if not exists (
    select 1 from public.debate_messages m
    join public.debates d on d.id = m.debate_id
    where m.id = p_message_id and m.deleted_at is null and d.status <> 'hidden'
  ) then raise exception '삭제된 발언에는 댓글을 남길 수 없습니다.'; end if;
  if p_parent_id is not null then select message_id into parent_message_id from public.message_comments where id = p_parent_id; if parent_message_id is distinct from p_message_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  insert into public.message_comments (message_id, author_id, body, parent_id)
  values (p_message_id, current_user_id, trim(p_body), p_parent_id)
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.delete_debate_message(uuid) from public, anon, authenticated;
grant execute on function public.delete_debate_message(uuid) to authenticated;

