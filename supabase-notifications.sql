-- OnDebate in-app notifications. Run this once in Supabase SQL Editor.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  debate_id uuid references public.debates(id) on delete cascade,
  type text not null check (type in ('opponent_message', 'message_comment', 'debate_comment')),
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_unread_idx on public.notifications(recipient_id, is_read, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "Users read their own notifications" on public.notifications;
drop policy if exists "Users update their own notifications" on public.notifications;
create policy "Users read their own notifications" on public.notifications for select to authenticated using ((select auth.uid()) = recipient_id);
create policy "Users update their own notifications" on public.notifications for update to authenticated using ((select auth.uid()) = recipient_id) with check ((select auth.uid()) = recipient_id);

create or replace function public.notify_opponent_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_title text;
begin
  select case when d.creator_id = new.author_id then d.opponent_id else d.creator_id end, d.title into v_recipient, v_title
  from public.debates d where d.id = new.debate_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, new.debate_id, 'opponent_message', '참여한 토론에 상대방의 새 발언이 등록되었습니다: ' || v_title);
  end if;
  return new;
end; $$;

create or replace function public.notify_message_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_debate_id uuid; v_title text;
begin
  if new.parent_id is not null then
    select author_id into v_recipient from public.message_comments where id = new.parent_id;
  else
    select author_id, debate_id into v_recipient, v_debate_id from public.debate_messages where id = new.message_id;
  end if;
  select m.debate_id, d.title into v_debate_id, v_title from public.debate_messages m join public.debates d on d.id = m.debate_id where m.id = new.message_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, v_debate_id, 'message_comment', '작성한 발언에 새 댓글이 등록되었습니다: ' || v_title);
  end if;
  return new;
end; $$;

create or replace function public.notify_debate_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_recipient uuid; v_title text;
begin
  if new.parent_id is not null then
    select author_id into v_recipient from public.debate_comments where id = new.parent_id;
  else
    select creator_id, title into v_recipient, v_title from public.debates where id = new.debate_id;
  end if;
  select title into v_title from public.debates where id = new.debate_id;
  if v_recipient is not null and v_recipient <> new.author_id then
    insert into public.notifications(recipient_id, actor_id, debate_id, type, body)
    values(v_recipient, new.author_id, new.debate_id, 'debate_comment', '작성한 토론에 새 댓글이 등록되었습니다: ' || v_title);
  end if;
  return new;
end; $$;

drop trigger if exists on_opponent_message_notification on public.debate_messages;
create trigger on_opponent_message_notification after insert on public.debate_messages for each row execute function public.notify_opponent_message();
drop trigger if exists on_message_comment_notification on public.message_comments;
create trigger on_message_comment_notification after insert on public.message_comments for each row execute function public.notify_message_comment();
drop trigger if exists on_debate_comment_notification on public.debate_comments;
create trigger on_debate_comment_notification after insert on public.debate_comments for each row execute function public.notify_debate_comment();

