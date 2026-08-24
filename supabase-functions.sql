
-- Run this after supabase-schema.sql in Supabase Dashboard > SQL Editor.
-- It creates a single safe operation for starting a debate and its first message.
create or replace function public.create_debate(
  p_title text,
  p_category text,
  p_duration_hours smallint,
  p_opening text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_debate_id uuid;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_duration_hours not between 1 and 24 then
    raise exception '토론 시간은 1~24시간으로 설정해야 합니다.';
  end if;

  if char_length(trim(p_title)) not between 2 and 100 then
    raise exception '제목은 2~100자로 작성해 주세요.';
  end if;

  if char_length(trim(p_opening)) not between 1 and 3000 then
    raise exception '첫 발언은 1~3,000자로 작성해 주세요.';
  end if;

  insert into public.debates (creator_id, title, category, duration_hours, ends_at)
  values (current_user_id, trim(p_title), p_category, p_duration_hours, now() + make_interval(hours => p_duration_hours))
  returning id into new_debate_id;

  insert into public.debate_messages (debate_id, author_id, side, body)
  values (new_debate_id, current_user_id, 'left', trim(p_opening));

  return new_debate_id;
end;
$$;

grant execute on function public.create_debate(text, text, smallint, text) to authenticated;

-- Run this section as well. It safely decides whether the signed-in user is
-- the creator, the existing opponent, or the first person joining as opponent.
create or replace function public.post_debate_message(
  p_debate_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_debate public.debates%rowtype;
  message_side text;
  new_message_id uuid;
begin
  if current_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if char_length(trim(p_body)) not between 1 and 3000 then
    raise exception '발언은 1~3,000자로 작성해 주세요.';
  end if;

  select * into target_debate from public.debates where id = p_debate_id for update;
  if not found then
    raise exception '토론을 찾을 수 없습니다.';
  end if;
  if target_debate.status in ('ended', 'hidden') or target_debate.ends_at <= now() then
    raise exception '이미 종료된 토론입니다.';
  end if;

  if current_user_id = target_debate.creator_id then
    message_side := 'left';
  elsif current_user_id = target_debate.opponent_id then
    message_side := 'right';
  elsif target_debate.opponent_id is null then
    update public.debates set opponent_id = current_user_id, status = 'active' where id = p_debate_id;
    message_side := 'right';
  else
    raise exception '참가자만 발언을 남길 수 있습니다.';
  end if;

  insert into public.debate_messages (debate_id, author_id, side, body)
  values (p_debate_id, current_user_id, message_side, trim(p_body))
  returning id into new_message_id;

  return new_message_id;
end;
$$;

grant execute on function public.post_debate_message(uuid, text) to authenticated;

-- Run this section once to add a view counter. It also marks an expired debate
-- as ended the first time its detail page is opened after its deadline.
alter table public.debates add column if not exists view_count integer not null default 0;

create or replace function public.record_debate_view(p_debate_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  new_view_count integer;
begin
  update public.debates
  set view_count = view_count + 1,
      status = case when ends_at <= now() and status <> 'hidden' then 'ended' else status end
  where id = p_debate_id and status <> 'hidden'
  returning view_count into new_view_count;

  if new_view_count is null then
    raise exception '토론을 찾을 수 없습니다.';
  end if;
  return new_view_count;
end;
$$;

grant execute on function public.record_debate_view(uuid) to anon, authenticated;

-- Spectator comments, nested replies, and hearts for messages and whole debates.
alter table public.message_comments add column if not exists parent_id uuid references public.message_comments(id) on delete cascade;
alter table public.message_comments add column if not exists like_count integer not null default 0 check (like_count >= 0);
alter table public.debate_comments add column if not exists parent_id uuid references public.debate_comments(id) on delete cascade;
alter table public.debate_comments add column if not exists like_count integer not null default 0 check (like_count >= 0);

create table if not exists public.message_comment_likes (
  comment_id uuid not null references public.message_comments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create table if not exists public.debate_comment_likes (
  comment_id uuid not null references public.debate_comments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
alter table public.message_comment_likes enable row level security;
alter table public.debate_comment_likes enable row level security;
drop policy if exists "Users read own message comment likes" on public.message_comment_likes;
create policy "Users read own message comment likes" on public.message_comment_likes for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Users read own debate comment likes" on public.debate_comment_likes;
create policy "Users read own debate comment likes" on public.debate_comment_likes for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.add_message_comment(p_message_id uuid, p_body text, p_parent_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; current_user_id uuid := auth.uid(); parent_message_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if p_parent_id is not null then select message_id into parent_message_id from public.message_comments where id = p_parent_id; if parent_message_id is distinct from p_message_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  insert into public.message_comments (message_id, author_id, body, parent_id) values (p_message_id, current_user_id, trim(p_body), p_parent_id) returning id into new_id; return new_id;
end; $$;

create or replace function public.add_debate_comment(p_debate_id uuid, p_body text, p_parent_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; current_user_id uuid := auth.uid(); parent_debate_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 1000 then raise exception '댓글은 1~1,000자로 작성해 주세요.'; end if;
  if p_parent_id is not null then select debate_id into parent_debate_id from public.debate_comments where id = p_parent_id; if parent_debate_id is distinct from p_debate_id then raise exception '잘못된 답글 대상입니다.'; end if; end if;
  insert into public.debate_comments (debate_id, author_id, body, parent_id) values (p_debate_id, current_user_id, trim(p_body), p_parent_id) returning id into new_id; return new_id;
end; $$;

create or replace function public.toggle_message_comment_like(p_comment_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare current_user_id uuid := auth.uid(); count_after integer;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if exists (select 1 from public.message_comment_likes where comment_id = p_comment_id and user_id = current_user_id) then delete from public.message_comment_likes where comment_id = p_comment_id and user_id = current_user_id; update public.message_comments set like_count = greatest(0, like_count - 1) where id = p_comment_id returning like_count into count_after;
  else insert into public.message_comment_likes (comment_id, user_id) values (p_comment_id, current_user_id); update public.message_comments set like_count = like_count + 1 where id = p_comment_id returning like_count into count_after; end if;
  if count_after is null then raise exception '댓글을 찾을 수 없습니다.'; end if; return count_after;
end; $$;

create or replace function public.toggle_debate_comment_like(p_comment_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare current_user_id uuid := auth.uid(); count_after integer;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if exists (select 1 from public.debate_comment_likes where comment_id = p_comment_id and user_id = current_user_id) then delete from public.debate_comment_likes where comment_id = p_comment_id and user_id = current_user_id; update public.debate_comments set like_count = greatest(0, like_count - 1) where id = p_comment_id returning like_count into count_after;
  else insert into public.debate_comment_likes (comment_id, user_id) values (p_comment_id, current_user_id); update public.debate_comments set like_count = like_count + 1 where id = p_comment_id returning like_count into count_after; end if;
  if count_after is null then raise exception '댓글을 찾을 수 없습니다.'; end if; return count_after;
end; $$;

grant execute on function public.add_message_comment(uuid, text, uuid) to authenticated;
grant execute on function public.add_debate_comment(uuid, text, uuid) to authenticated;
grant execute on function public.toggle_message_comment_like(uuid) to authenticated;
grant execute on function public.toggle_debate_comment_like(uuid) to authenticated;

-- Hearts on debate messages and one vote per spectator.
alter table public.debate_messages add column if not exists like_count integer not null default 0 check (like_count >= 0);
create table if not exists public.message_likes (
  message_id uuid not null references public.debate_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.message_likes enable row level security;
drop policy if exists "Users read own message likes" on public.message_likes;
create policy "Users read own message likes" on public.message_likes for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.toggle_message_like(p_message_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare current_user_id uuid := auth.uid(); count_after integer;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if exists (select 1 from public.message_likes where message_id = p_message_id and user_id = current_user_id) then delete from public.message_likes where message_id = p_message_id and user_id = current_user_id; update public.debate_messages set like_count = greatest(0, like_count - 1) where id = p_message_id returning like_count into count_after;
  else insert into public.message_likes (message_id, user_id) values (p_message_id, current_user_id); update public.debate_messages set like_count = like_count + 1 where id = p_message_id returning like_count into count_after; end if;
  if count_after is null then raise exception '발언을 찾을 수 없습니다.'; end if; return count_after;
end; $$;

create or replace function public.cast_debate_vote(p_debate_id uuid, p_chosen_side text)
returns text language plpgsql security definer set search_path = public as $$
declare current_user_id uuid := auth.uid(); target_debate public.debates%rowtype;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_chosen_side not in ('left', 'right') then raise exception '잘못된 투표 선택입니다.'; end if;
  select * into target_debate from public.debates where id = p_debate_id;
  if not found then raise exception '토론을 찾을 수 없습니다.'; end if;
  if target_debate.ends_at <= now() or target_debate.status in ('ended', 'hidden') then raise exception '종료된 토론에는 투표할 수 없습니다.'; end if;
  if current_user_id = target_debate.creator_id or current_user_id = target_debate.opponent_id then raise exception '토론 참가자는 투표할 수 없습니다.'; end if;
  if exists (select 1 from public.votes where debate_id = p_debate_id and voter_id = current_user_id) then raise exception '이미 투표하셨습니다.'; end if;
  insert into public.votes (debate_id, voter_id, chosen_side) values (p_debate_id, current_user_id, p_chosen_side); return p_chosen_side;
end; $$;

grant execute on function public.toggle_message_like(uuid) to authenticated;
grant execute on function public.cast_debate_vote(uuid, text) to authenticated;

-- Soft-delete spectator comments while preserving nested reply structure.
create or replace function public.delete_message_comment(p_comment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  update public.message_comments
  set body = '삭제된 댓글입니다.'
  where id = p_comment_id and author_id = auth.uid();
  if not found then raise exception '삭제할 수 없는 댓글입니다.'; end if;
end; $$;

create or replace function public.delete_debate_comment(p_comment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  update public.debate_comments
  set body = '삭제된 댓글입니다.'
  where id = p_comment_id and author_id = auth.uid();
  if not found then raise exception '삭제할 수 없는 댓글입니다.'; end if;
end; $$;

grant execute on function public.delete_message_comment(uuid) to authenticated;
grant execute on function public.delete_debate_comment(uuid) to authenticated;

-- Ensure the home page can read every debate except ones hidden by moderation.
drop policy if exists "Visible debates are readable" on public.debates;
create policy "Visible debates are readable" on public.debates
  for select to anon, authenticated
  using (status <> 'hidden');

