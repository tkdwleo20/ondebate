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

