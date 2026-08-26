-- OnDebate debate outcome point rules. Run after the existing point migrations.
-- No opening or joining fee. Win +200P, loss -150P. Balances never go below 0.

alter table public.point_ledger drop constraint if exists point_ledger_reason_check;
alter table public.point_ledger add constraint point_ledger_reason_check check (reason in (
  'signup_bonus', 'daily_checkin', 'debate_create', 'debate_join', 'debate_started',
  'debate_win', 'debate_loss', 'vote_participation', 'audience_bonus',
  'no_opponent_refund', 'moderation_penalty', 'debate_entry', 'mutual_agreement', 'vote_win'
));

-- A penalty is capped at the user's current balance, so a settled debate can
-- never make a profile's point balance negative.
create or replace function public.award_points(p_user_id uuid, p_amount integer, p_reason text, p_debate_id uuid default null, p_event_key text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_rows integer; v_points integer; v_amount integer := p_amount;
begin
  select points into v_points from public.profiles where id = p_user_id for update;
  if not found then raise exception '사용자를 찾을 수 없습니다.'; end if;
  if p_amount < 0 then v_amount := greatest(p_amount, -v_points); end if;
  if v_amount = 0 then return false; end if;
  insert into public.point_ledger(user_id, amount, reason, debate_id, event_key)
  values(p_user_id, v_amount, p_reason, p_debate_id, p_event_key)
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return false; end if;
  update public.profiles set points = points + v_amount where id = p_user_id;
  return true;
end;
$$;

create or replace function public.create_debate(p_title text, p_category text, p_duration_hours smallint, p_opening text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_debate_id uuid; current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_duration_hours not between 1 and 24 then raise exception '토론 시간은 1~24시간으로 설정해야 합니다.'; end if;
  if char_length(trim(p_title)) not between 2 and 100 then raise exception '제목은 2~100자로 작성해 주세요.'; end if;
  if char_length(trim(p_opening)) not between 1 and 3000 then raise exception '첫 발언은 1~3,000자로 작성해 주세요.'; end if;
  insert into public.debates(creator_id,title,category,duration_hours,ends_at)
  values(current_user_id,trim(p_title),p_category,p_duration_hours,now()+make_interval(hours=>p_duration_hours))
  returning id into new_debate_id;
  insert into public.debate_messages(debate_id,author_id,side,body)
  values(new_debate_id,current_user_id,'left',trim(p_opening));
  return new_debate_id;
end;
$$;

create or replace function public.post_debate_message(p_debate_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare current_user_id uuid := auth.uid(); target_debate public.debates%rowtype; message_side text; new_message_id uuid;
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_body)) not between 1 and 3000 then raise exception '발언은 1~3,000자로 작성해 주세요.'; end if;
  select * into target_debate from public.debates where id = p_debate_id for update;
  if not found then raise exception '토론을 찾을 수 없습니다.'; end if;
  if target_debate.status in ('ended','hidden') or target_debate.ends_at <= now() then raise exception '이미 종료된 토론입니다.'; end if;
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
  insert into public.debate_messages(debate_id,author_id,side,body)
  values(p_debate_id,current_user_id,message_side,trim(p_body)) returning id into new_message_id;
  return new_message_id;
end;
$$;

create or replace function public.settle_debate_points(p_debate_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.debates%rowtype; left_votes integer; right_votes integer; total_votes integer; creator_messages integer; opponent_messages integer;
begin
  select * into d from public.debates where id = p_debate_id for update;
  if not found or d.status = 'hidden' or d.ends_at > now() or d.settled_at is not null then return; end if;
  update public.debates set status = 'ended', settled_at = now() where id = p_debate_id;
  perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_ended', '참여한 토론이 종료되었습니다: ' || d.title, 'ended:' || p_debate_id::text || ':creator');
  if d.opponent_id is not null then
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_ended', '참여한 토론이 종료되었습니다: ' || d.title, 'ended:' || p_debate_id::text || ':opponent');
  end if;
  if d.opponent_id is null then
    perform public.award_points(d.creator_id, 150, 'no_opponent_refund', p_debate_id, 'refund:' || p_debate_id::text);
    return;
  end if;
  select count(*) filter(where chosen_side = 'left'), count(*) filter(where chosen_side = 'right'), count(*) into left_votes, right_votes, total_votes
  from public.votes where debate_id = p_debate_id;
  if left_votes > right_votes then
    perform public.award_points(d.creator_id, 200, 'debate_win', p_debate_id, 'win:' || p_debate_id::text);
    perform public.award_points(d.opponent_id, -150, 'debate_loss', p_debate_id, 'loss:' || p_debate_id::text);
    perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_result', '투표 결과, 승리했습니다: ' || d.title, 'result:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_result', '투표 결과, 패배했습니다: ' || d.title, 'result:' || p_debate_id::text || ':opponent');
  elsif right_votes > left_votes then
    perform public.award_points(d.opponent_id, 200, 'debate_win', p_debate_id, 'win:' || p_debate_id::text);
    perform public.award_points(d.creator_id, -150, 'debate_loss', p_debate_id, 'loss:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_result', '투표 결과, 패배했습니다: ' || d.title, 'result:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_result', '투표 결과, 승리했습니다: ' || d.title, 'result:' || p_debate_id::text || ':opponent');
  else
    perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_result', '투표 결과, 무승부입니다: ' || d.title, 'result:' || p_debate_id::text || ':creator');
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_result', '투표 결과, 무승부입니다: ' || d.title, 'result:' || p_debate_id::text || ':opponent');
  end if;
  select count(*) filter(where author_id = d.creator_id), count(*) filter(where author_id = d.opponent_id) into creator_messages, opponent_messages
  from public.debate_messages where debate_id = p_debate_id;
  if total_votes >= 10 and creator_messages >= 2 and opponent_messages >= 2 then
    perform public.award_points(d.creator_id, 50, 'audience_bonus', p_debate_id, 'audience:' || p_debate_id::text || ':creator');
    perform public.award_points(d.opponent_id, 50, 'audience_bonus', p_debate_id, 'audience:' || p_debate_id::text || ':opponent');
  end if;
end;
$$;

revoke all on function public.award_points(uuid, integer, text, uuid, text) from public, anon, authenticated;
revoke all on function public.create_debate(text, text, smallint, text) from public, anon;
revoke all on function public.post_debate_message(uuid, text) from public, anon;
revoke all on function public.settle_debate_points(uuid) from public, anon;
grant execute on function public.create_debate(text, text, smallint, text) to authenticated;
grant execute on function public.post_debate_message(uuid, text) to authenticated;
grant execute on function public.settle_debate_points(uuid) to authenticated;
