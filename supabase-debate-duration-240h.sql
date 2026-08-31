-- Allow debate durations from 1 to 240 hours.
-- Run once in Supabase Dashboard > SQL Editor.

alter table public.debates
  drop constraint if exists debates_duration_hours_check;

alter table public.debates
  add constraint debates_duration_hours_check
  check (duration_hours between 1 and 240);

create or replace function public.create_debate(
  p_title text,
  p_category text,
  p_duration_hours smallint,
  p_opening text,
  p_is_anonymous boolean
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_debate_id uuid;
  v_user_id uuid := auth.uid();
  v_code text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  perform public.assert_write_allowed(v_user_id);
  if p_duration_hours not between 1 and 240 then
    raise exception '토론 시간은 1~240시간으로 설정해야 합니다.';
  end if;
  if p_category not in ('일상', '사회 · 정치', '연애', '문화 · 취미', '게임 · 스포츠', '학교 · 직장') then raise exception '올바른 카테고리를 선택해 주세요.'; end if;
  if char_length(trim(p_title)) not between 2 and 100 then raise exception '제목은 2~100자로 작성해 주세요.'; end if;
  if char_length(trim(p_opening)) not between 1 and 3000 then raise exception '첫 발언은 1~3,000자로 작성해 주세요.'; end if;
  if coalesce(p_is_anonymous, false) then perform public.assert_anonymous_write_allowed(v_user_id); end if;

  insert into public.debates(creator_id, creator_is_anonymous, title, category, duration_hours, ends_at)
  values(v_user_id, coalesce(p_is_anonymous, false), trim(p_title), p_category, p_duration_hours, now() + make_interval(hours => p_duration_hours))
  returning id into v_debate_id;

  if coalesce(p_is_anonymous, false) then
    v_code := public.anonymous_code_for(v_debate_id, v_user_id);
  end if;

  insert into public.debate_messages(debate_id, author_id, side, body, is_anonymous, anonymous_code)
  values(v_debate_id, v_user_id, 'left', trim(p_opening), coalesce(p_is_anonymous, false), v_code);

  return v_debate_id;
end;
$$;

revoke all on function public.create_debate(text, text, smallint, text, boolean) from public, anon;
grant execute on function public.create_debate(text, text, smallint, text, boolean) to authenticated;

