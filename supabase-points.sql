-- OnDebate point economy. Run this AFTER supabase-functions.sql.
-- All rewards are recorded once in the ledger and applied atomically to profiles.points.

alter table public.point_ledger add column if not exists event_key text;
alter table public.point_ledger drop constraint if exists point_ledger_reason_check;
alter table public.point_ledger add constraint point_ledger_reason_check check (reason in ('signup_bonus','daily_checkin','debate_create','debate_join','debate_started','debate_win','vote_participation','audience_bonus','no_opponent_refund','moderation_penalty','debate_entry','mutual_agreement','vote_win'));
create unique index if not exists point_ledger_event_key_unique on public.point_ledger(user_id, event_key) where event_key is not null;

create or replace function public.award_points(p_user_id uuid, p_amount integer, p_reason text, p_debate_id uuid default null, p_event_key text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_rows integer;
begin
  insert into public.point_ledger(user_id, amount, reason, debate_id, event_key)
  values(p_user_id, p_amount, p_reason, p_debate_id, p_event_key)
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return false; end if;
  update public.profiles set points = points + p_amount where id = p_user_id and points + p_amount >= 0;
  if not found then raise exception '포인트가 부족합니다.'; end if;
  return true;
end; $$;
revoke all on function public.award_points(uuid, integer, text, uuid, text) from public, anon, authenticated;

create or replace function public.grant_signup_points()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.award_points(new.id, 1000, 'signup_bonus', null, 'signup:' || new.id::text);
  return new;
end; $$;
revoke all on function public.grant_signup_points() from public, anon, authenticated;
drop trigger if exists profiles_signup_points on public.profiles;
create trigger profiles_signup_points after insert on public.profiles for each row execute function public.grant_signup_points();

-- Existing profiles receive the same one-time membership grant when this migration is first run.
do $$ declare p record; begin for p in select id from public.profiles loop perform public.award_points(p.id, 1000, 'signup_bonus', null, 'signup:' || p.id::text); end loop; end $$;

create or replace function public.daily_checkin()
returns boolean language plpgsql security definer set search_path = public as $$
declare v_user_id uuid := auth.uid(); v_day text := (now() at time zone 'Asia/Seoul')::date::text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  return public.award_points(v_user_id, 100, 'daily_checkin', null, 'daily:' || v_day);
end; $$;
revoke all on function public.daily_checkin() from public, anon;
grant execute on function public.daily_checkin() to authenticated;

create or replace function public.create_debate(p_title text, p_category text, p_duration_hours smallint, p_opening text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_debate_id uuid; current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_duration_hours not between 1 and 24 then raise exception '토론 시간은 1~24시간으로 설정해야 합니다.'; end if;
  if char_length(trim(p_title)) not between 2 and 100 then raise exception '제목은 2~100자로 작성해 주세요.'; end if;
  if char_length(trim(p_opening)) not between 1 and 3000 then raise exception '첫 발언은 1~3,000자로 작성해 주세요.'; end if;
  insert into public.debates(creator_id,title,category,duration_hours,ends_at) values(current_user_id,trim(p_title),p_category,p_duration_hours,now()+make_interval(hours=>p_duration_hours)) returning id into new_debate_id;
  perform public.award_points(current_user_id,-200,'debate_create',new_debate_id,'create:'||new_debate_id::text);
  insert into public.debate_messages(debate_id,author_id,side,body) values(new_debate_id,current_user_id,'left',trim(p_opening));
  return new_debate_id;
end; $$;

create or replace function public.post_debate_message(p_debate_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare current_user_id uuid := auth.uid(); target_debate public.debates%rowtype; message_side text; new_message_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 3000 then raise exception '발언은 1~3,000자로 작성해 주세요.'; end if;
  select * into target_debate from public.debates where id=p_debate_id for update;
  if not found then raise exception '토론을 찾을 수 없습니다.'; end if;
  if target_debate.status in ('ended','hidden') or target_debate.ends_at <= now() then raise exception '이미 종료된 토론입니다.'; end if;
  if current_user_id=target_debate.creator_id then message_side:='left';
  elsif current_user_id=target_debate.opponent_id then message_side:='right';
  elsif target_debate.opponent_id is null then
    perform public.award_points(current_user_id,-100,'debate_join',p_debate_id,'join:'||p_debate_id::text);
    perform public.award_points(target_debate.creator_id,100,'debate_started',p_debate_id,'started:'||p_debate_id::text);
    update public.debates set opponent_id=current_user_id,status='active' where id=p_debate_id; message_side:='right';
  else raise exception '참가자만 발언을 남길 수 있습니다.'; end if;
  insert into public.debate_messages(debate_id,author_id,side,body) values(p_debate_id,current_user_id,message_side,trim(p_body)) returning id into new_message_id;
  return new_message_id;
end; $$;

create or replace function public.settle_debate_points(p_debate_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.debates%rowtype; left_votes integer; right_votes integer; total_votes integer; voter record; creator_messages integer; opponent_messages integer;
begin
  select * into d from public.debates where id=p_debate_id for update;
  if not found or d.status='hidden' or d.ends_at>now() then return; end if;
  update public.debates set status='ended' where id=p_debate_id and status<>'hidden';
  if d.opponent_id is null then perform public.award_points(d.creator_id,150,'no_opponent_refund',p_debate_id,'refund:'||p_debate_id::text); return; end if;
  select count(*) filter(where chosen_side='left'),count(*) filter(where chosen_side='right'),count(*) into left_votes,right_votes,total_votes from public.votes where debate_id=p_debate_id;
  if left_votes>right_votes then perform public.award_points(d.creator_id,300,'debate_win',p_debate_id,'win:'||p_debate_id::text); elsif right_votes>left_votes then perform public.award_points(d.opponent_id,300,'debate_win',p_debate_id,'win:'||p_debate_id::text); end if;
  -- Vote points are granted at the moment of voting, not during settlement.
  select count(*) filter(where author_id=d.creator_id),count(*) filter(where author_id=d.opponent_id) into creator_messages,opponent_messages from public.debate_messages where debate_id=p_debate_id;
  if total_votes>=10 and creator_messages>=2 and opponent_messages>=2 then perform public.award_points(d.creator_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':creator'); perform public.award_points(d.opponent_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':opponent'); end if;
end; $$;
revoke all on function public.settle_debate_points(uuid) from public, anon;
grant execute on function public.settle_debate_points(uuid) to authenticated;

create or replace function public.settle_expired_debates()
returns void language plpgsql security definer set search_path = public as $$
declare d record; begin for d in select id from public.debates where ends_at<=now() and status<>'hidden' order by ends_at limit 100 loop perform public.settle_debate_points(d.id); end loop; end $$;
revoke all on function public.settle_expired_debates() from public, anon;
grant execute on function public.settle_expired_debates() to authenticated;

