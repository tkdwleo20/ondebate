-- OnDebate notification state. Run once after the notification migrations.
-- Cleared notifications stay hidden, and debate settlement notifications are emitted only once.

alter table public.notifications add column if not exists deleted_at timestamptz;
alter table public.debates add column if not exists settled_at timestamptz;
update public.debates set settled_at = ends_at where status = 'ended' and settled_at is null;

create or replace function public.clear_my_notifications()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  update public.notifications set deleted_at = now(), is_read = true
  where recipient_id = auth.uid() and deleted_at is null;
end;
$$;

create or replace function public.settle_debate_points(p_debate_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.debates%rowtype; left_votes integer; right_votes integer; total_votes integer; creator_messages integer; opponent_messages integer;
begin
  select * into d from public.debates where id=p_debate_id for update;
  if not found or d.status='hidden' or d.ends_at>now() or d.settled_at is not null then return; end if;
  update public.debates set status='ended', settled_at=now() where id=p_debate_id;
  perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_ended', '참여한 토론이 종료되었습니다: ' || d.title, 'ended:' || p_debate_id::text || ':creator');
  if d.opponent_id is not null then perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_ended', '참여한 토론이 종료되었습니다: ' || d.title, 'ended:' || p_debate_id::text || ':opponent'); end if;
  if d.opponent_id is null then perform public.award_points(d.creator_id,150,'no_opponent_refund',p_debate_id,'refund:'||p_debate_id::text); return; end if;
  select count(*) filter(where chosen_side='left'), count(*) filter(where chosen_side='right'), count(*) into left_votes, right_votes, total_votes from public.votes where debate_id=p_debate_id;
  if left_votes > right_votes then
    perform public.award_points(d.creator_id,300,'debate_win',p_debate_id,'win:'||p_debate_id::text);
    perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_result', '투표 결과, 승리했습니다: ' || d.title, 'result:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_result', '투표 결과, 패배했습니다: ' || d.title, 'result:' || p_debate_id::text || ':opponent');
  elsif right_votes > left_votes then
    perform public.award_points(d.opponent_id,300,'debate_win',p_debate_id,'win:'||p_debate_id::text);
    perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_result', '투표 결과, 패배했습니다: ' || d.title, 'result:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_result', '투표 결과, 승리했습니다: ' || d.title, 'result:' || p_debate_id::text || ':opponent');
  else
    perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_result', '투표 결과, 무승부입니다: ' || d.title, 'result:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_result', '투표 결과, 무승부입니다: ' || d.title, 'result:' || p_debate_id::text || ':opponent');
  end if;
  select count(*) filter(where author_id=d.creator_id), count(*) filter(where author_id=d.opponent_id) into creator_messages, opponent_messages from public.debate_messages where debate_id=p_debate_id;
  if total_votes>=10 and creator_messages>=2 and opponent_messages>=2 then
    perform public.award_points(d.creator_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':creator');
    perform public.award_points(d.opponent_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':opponent');
  end if;
end;
$$;

revoke all on function public.clear_my_notifications() from public, anon, authenticated;
revoke all on function public.settle_debate_points(uuid) from public, anon;
grant execute on function public.clear_my_notifications() to authenticated;
grant execute on function public.settle_debate_points(uuid) to authenticated;
