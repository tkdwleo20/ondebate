-- OnDebate notification previews. Run once after the notification migration.
-- New message/comment notifications include a one-line, 50-character preview.

create or replace function public.notification_preview(p_body text)
returns text language sql immutable set search_path = public as $$
  select case
    when char_length(regexp_replace(btrim(coalesce(p_body, '')), '\\s+', ' ', 'g')) > 50
      then left(regexp_replace(btrim(coalesce(p_body, '')), '\\s+', ' ', 'g'), 50) || '...'
    else regexp_replace(btrim(coalesce(p_body, '')), '\\s+', ' ', 'g')
  end;
$$;

create or replace function public.notify_opponent_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid;
begin
  select case when d.creator_id = new.author_id then d.opponent_id else d.creator_id end into v_recipient
  from public.debates d where d.id = new.debate_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, new.debate_id, 'opponent_message', '상대방의 새 발언: ' || public.notification_preview(new.body));
  end if;
  return new;
end;
$$;

create or replace function public.notify_message_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_debate_id uuid;
begin
  if new.parent_id is not null then
    select author_id into v_recipient from public.message_comments where id = new.parent_id;
  else
    select author_id, debate_id into v_recipient, v_debate_id from public.debate_messages where id = new.message_id;
  end if;
  select debate_id into v_debate_id from public.debate_messages where id = new.message_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, v_debate_id, 'message_comment', '내 발언에 새 댓글: ' || public.notification_preview(new.body));
  end if;
  return new;
end;
$$;

create or replace function public.notify_debate_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid;
begin
  if new.parent_id is not null then
    select author_id into v_recipient from public.debate_comments where id = new.parent_id;
  else
    select creator_id into v_recipient from public.debates where id = new.debate_id;
  end if;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, new.debate_id, 'debate_comment', '내 토론에 새 댓글: ' || public.notification_preview(new.body));
  end if;
  return new;
end;
$$;

revoke all on function public.notification_preview(text) from public, anon, authenticated;
revoke all on function public.notify_opponent_message() from public, anon, authenticated;
revoke all on function public.notify_message_comment() from public, anon, authenticated;
revoke all on function public.notify_debate_comment() from public, anon, authenticated;

