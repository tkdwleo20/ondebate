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

create or replace function public.notification_title(p_title text)
returns text language sql immutable set search_path = public as $$
  select case
    when char_length(regexp_replace(btrim(coalesce(p_title, '')), '\\s+', ' ', 'g')) > 20
      then left(regexp_replace(btrim(coalesce(p_title, '')), '\\s+', ' ', 'g'), 20) || '…'
    else regexp_replace(btrim(coalesce(p_title, '')), '\\s+', ' ', 'g')
  end;
$$;

-- Return titles only for the signed-in user's own active notifications. This
-- also works when a moderated debate is no longer publicly readable.
create or replace function public.my_notification_debate_titles()
returns table (debate_id uuid, title text)
language sql stable security definer set search_path = public as $$
  select distinct n.debate_id, d.title
  from public.notifications n
  join public.debates d on d.id = n.debate_id
  where auth.uid() is not null
    and n.recipient_id = auth.uid()
    and n.deleted_at is null
    and n.debate_id is not null;
$$;

create or replace function public.notify_opponent_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_title text;
begin
  select case when d.creator_id = new.author_id then d.opponent_id else d.creator_id end, d.title into v_recipient, v_title
  from public.debates d where d.id = new.debate_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, new.debate_id, 'opponent_message', format('「%s」에 상대방의 새 발언: %s', public.notification_title(v_title), public.notification_preview(new.body)));
  end if;
  return new;
end;
$$;

create or replace function public.notify_message_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_debate_id uuid; v_title text;
begin
  if new.parent_id is not null then
    select author_id into v_recipient from public.message_comments where id = new.parent_id;
  else
    select author_id, debate_id into v_recipient, v_debate_id from public.debate_messages where id = new.message_id;
  end if;
  select m.debate_id, d.title into v_debate_id, v_title
  from public.debate_messages m join public.debates d on d.id = m.debate_id
  where m.id = new.message_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, v_debate_id, 'message_comment', format('「%s」에 새 댓글: %s', public.notification_title(v_title), public.notification_preview(new.body)));
  end if;
  return new;
end;
$$;

create or replace function public.notify_debate_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_title text;
begin
  if new.parent_id is not null then
    select author_id into v_recipient from public.debate_comments where id = new.parent_id;
  else
    select creator_id into v_recipient from public.debates where id = new.debate_id;
  end if;
  select title into v_title from public.debates where id = new.debate_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, new.debate_id, 'debate_comment', format('「%s」에 새 댓글: %s', public.notification_title(v_title), public.notification_preview(new.body)));
  end if;
  return new;
end;
$$;

revoke all on function public.notification_preview(text) from public, anon, authenticated;
revoke all on function public.notification_title(text) from public, anon, authenticated;
revoke all on function public.my_notification_debate_titles() from public, anon, authenticated;
revoke all on function public.notify_opponent_message() from public, anon, authenticated;
revoke all on function public.notify_message_comment() from public, anon, authenticated;
revoke all on function public.notify_debate_comment() from public, anon, authenticated;
grant execute on function public.my_notification_debate_titles() to authenticated;
