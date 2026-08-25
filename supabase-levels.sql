-- OnDebate levels and voting reward adjustment.
-- Run this after supabase-points.sql in the Supabase SQL Editor.

-- A vote earns +10P for the first five votes made that day (Asia/Seoul),
-- then +1P for every later vote. The reward is granted immediately.
create or replace function public.cast_debate_vote(p_debate_id uuid, p_chosen_side text)
returns text language plpgsql security definer set search_path = public as $$
declare
  current_user_id uuid := auth.uid();
  target_debate public.debates%rowtype;
  vote_count_today integer;
  reward_amount integer;
  vote_id uuid;
  today_kst date := (now() at time zone 'Asia/Seoul')::date;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_chosen_side not in ('left', 'right') then raise exception '잘못된 투표 선택입니다.'; end if;
  select * into target_debate from public.debates where id = p_debate_id;
  if not found then raise exception '토론을 찾을 수 없습니다.'; end if;
  if target_debate.ends_at <= now() or target_debate.status in ('ended', 'hidden') then raise exception '종료된 토론에는 투표할 수 없습니다.'; end if;
  if current_user_id = target_debate.creator_id or current_user_id = target_debate.opponent_id then raise exception '토론 참가자는 투표할 수 없습니다.'; end if;
  if exists (select 1 from public.votes where debate_id = p_debate_id and voter_id = current_user_id) then raise exception '이미 투표하셨습니다.'; end if;

  insert into public.votes (debate_id, voter_id, chosen_side)
  values (p_debate_id, current_user_id, p_chosen_side)
  returning id into vote_id;

  select count(*) into vote_count_today
  from public.point_ledger
  where user_id = current_user_id
    and reason = 'vote_participation'
    and (created_at at time zone 'Asia/Seoul')::date = today_kst;
  reward_amount := case when vote_count_today < 5 then 10 else 1 end;
  perform public.award_points(current_user_id, reward_amount, 'vote_participation', p_debate_id, 'vote:' || vote_id::text);
  return p_chosen_side;
end; $$;

grant execute on function public.cast_debate_vote(uuid, text) to authenticated;

-- Vote rewards used to be settled at debate close. Remove that legacy loop so
-- users are not rewarded twice after installing this update.
create or replace function public.settle_debate_points(p_debate_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.debates%rowtype; left_votes integer; right_votes integer; total_votes integer; creator_messages integer; opponent_messages integer;
begin
  select * into d from public.debates where id=p_debate_id for update;
  if not found or d.status='hidden' or d.ends_at>now() then return; end if;
  update public.debates set status='ended' where id=p_debate_id and status<>'hidden';
  if d.opponent_id is null then perform public.award_points(d.creator_id,150,'no_opponent_refund',p_debate_id,'refund:'||p_debate_id::text); return; end if;
  select count(*) filter(where chosen_side='left'),count(*) filter(where chosen_side='right'),count(*) into left_votes,right_votes,total_votes from public.votes where debate_id=p_debate_id;
  if left_votes>right_votes then perform public.award_points(d.creator_id,300,'debate_win',p_debate_id,'win:'||p_debate_id::text); elsif right_votes>left_votes then perform public.award_points(d.opponent_id,300,'debate_win',p_debate_id,'win:'||p_debate_id::text); end if;
  select count(*) filter(where author_id=d.creator_id),count(*) filter(where author_id=d.opponent_id) into creator_messages,opponent_messages from public.debate_messages where debate_id=p_debate_id;
  if total_votes>=10 and creator_messages>=2 and opponent_messages>=2 then perform public.award_points(d.creator_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':creator'); perform public.award_points(d.opponent_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':opponent'); end if;
end; $$;

revoke all on function public.settle_debate_points(uuid) from public, anon;
grant execute on function public.settle_debate_points(uuid) to authenticated;

