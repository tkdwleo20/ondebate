-- OnDebate nickname-change rules. Run this once after supabase-schema.sql.
-- First change may be made any time; subsequent changes require three months.

alter table public.profiles
  add column if not exists nickname_change_count integer not null default 0 check (nickname_change_count >= 0),
  add column if not exists nickname_changed_at timestamptz;

-- Browser clients must use the RPC below, so the interval rule cannot be bypassed
-- by directly updating the profiles table.
drop policy if exists "Users update their own profile" on public.profiles;

create or replace function public.set_nickname(p_nickname text, p_is_change boolean default false)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_nickname text := btrim(p_nickname);
  v_profile public.profiles%rowtype;
  v_next_change_at timestamptz;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if char_length(v_nickname) < 2 or char_length(v_nickname) > 20 then
    raise exception '닉네임은 2~20자로 입력해 주세요.';
  end if;

  select * into v_profile from public.profiles where id = v_user_id for update;

  if p_is_change then
    if not found then
      raise exception '먼저 닉네임을 설정해 주세요.';
    end if;
    if lower(v_profile.nickname) = lower(v_nickname) then
      raise exception '현재 사용 중인 닉네임입니다.';
    end if;
    if v_profile.nickname_change_count >= 1 and v_profile.nickname_changed_at is not null then
      v_next_change_at := v_profile.nickname_changed_at + interval '3 months';
      if now() < v_next_change_at then
        raise exception '닉네임은 % 이후에 다시 변경할 수 있습니다.', to_char(v_next_change_at at time zone 'Asia/Seoul', 'YYYY년 MM월 DD일');
      end if;
    end if;

    update public.profiles
      set nickname = v_nickname,
          nickname_change_count = v_profile.nickname_change_count + 1,
          nickname_changed_at = now()
      where id = v_user_id;
  elsif not found then
    insert into public.profiles (id, nickname) values (v_user_id, v_nickname);
  elsif v_profile.nickname ~ '^토론자[0-9a-f]{6}$' then
    update public.profiles set nickname = v_nickname where id = v_user_id;
  else
    raise exception '닉네임 변경은 마이페이지에서 해주세요.';
  end if;

  return v_nickname;
end;
$$;

grant execute on function public.set_nickname(text, boolean) to authenticated;

