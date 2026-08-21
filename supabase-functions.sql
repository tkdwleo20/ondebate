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

