-- OnDebate notification expansion. Run once after the existing migrations.
-- Adds debate-end/result, report-result, and level-change notifications.

alter table public.notifications add column if not exists event_key text;
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  type in ('opponent_message', 'message_comment', 'debate_comment', 'debate_ended', 'debate_result', 'report_result', 'level_change')
);
create unique index if not exists notifications_event_key_unique
  on public.notifications(event_key) where event_key is not null;

create or replace function public.create_notification(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_debate_id uuid,
  p_type text,
  p_body text,
  p_event_key text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_recipient_id is null then return; end if;
  insert into public.notifications(recipient_id, actor_id, debate_id, type, body, event_key)
  values (p_recipient_id, p_actor_id, p_debate_id, p_type, p_body, p_event_key)
  on conflict do nothing;
end;
$$;

-- A point change may cross a level boundary in either direction.
create or replace function public.award_points(
  p_user_id uuid, p_amount integer, p_reason text,
  p_debate_id uuid default null, p_event_key text default null
)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_rows integer; v_old_points integer; v_new_points integer; v_old_level integer; v_new_level integer;
begin
  insert into public.point_ledger(user_id, amount, reason, debate_id, event_key)
  values(p_user_id, p_amount, p_reason, p_debate_id, p_event_key)
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return false; end if;

  select points into v_old_points from public.profiles where id = p_user_id for update;
  if v_old_points is null or v_old_points + p_amount < 0 then raise exception '포인트가 부족합니다.'; end if;
  update public.profiles set points = points + p_amount where id = p_user_id returning points into v_new_points;
  v_old_level := greatest(1, floor(v_old_points / 1000.0)::integer);
  v_new_level := greatest(1, floor(v_new_points / 1000.0)::integer);
  if v_old_level <> v_new_level then
    perform public.create_notification(
      p_user_id, null, p_debate_id, 'level_change',
      format('레벨이 Lv.%s에서 Lv.%s로 변동했습니다.', v_old_level, v_new_level),
      'level:' || coalesce(p_event_key, gen_random_uuid()::text)
    );
  end if;
  return true;
end;
$$;

create or replace function public.settle_debate_points(p_debate_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.debates%rowtype; left_votes integer; right_votes integer; total_votes integer; creator_messages integer; opponent_messages integer;
begin
  select * into d from public.debates where id=p_debate_id for update;
  if not found or d.status='hidden' or d.ends_at>now() then return; end if;
  update public.debates set status='ended' where id=p_debate_id and status<>'hidden';

  perform public.create_notification(d.creator_id, null, p_debate_id, 'debate_ended', '참여한 토론이 종료되었습니다: ' || d.title, 'ended:' || p_debate_id::text || ':creator');
  if d.opponent_id is not null then
    perform public.create_notification(d.opponent_id, null, p_debate_id, 'debate_ended', '참여한 토론이 종료되었습니다: ' || d.title, 'ended:' || p_debate_id::text || ':opponent');
  end if;

  if d.opponent_id is null then
    perform public.award_points(d.creator_id,150,'no_opponent_refund',p_debate_id,'refund:'||p_debate_id::text);
    return;
  end if;

  select count(*) filter(where chosen_side='left'), count(*) filter(where chosen_side='right'), count(*)
  into left_votes, right_votes, total_votes from public.votes where debate_id=p_debate_id;
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

  select count(*) filter(where author_id=d.creator_id), count(*) filter(where author_id=d.opponent_id)
  into creator_messages, opponent_messages from public.debate_messages where debate_id=p_debate_id;
  if total_votes>=10 and creator_messages>=2 and opponent_messages>=2 then
    perform public.award_points(d.creator_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':creator');
    perform public.award_points(d.opponent_id,50,'audience_bonus',p_debate_id,'audience:'||p_debate_id::text||':opponent');
  end if;
end;
$$;

-- Notify the reporting user whenever an administrator handles the report.
create or replace function public.admin_hide_debate(p_debate_id uuid, p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_reporter_id uuid; v_title text;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  select r.reporter_id, d.title into v_reporter_id, v_title from public.reports r join public.debates d on d.id=r.debate_id where r.id=p_report_id and r.debate_id=p_debate_id;
  update public.debates set status = 'hidden' where id = p_debate_id;
  update public.reports set status = 'reviewed' where id = p_report_id and debate_id = p_debate_id;
  perform public.create_notification(v_reporter_id, auth.uid(), p_debate_id, 'report_result', '신고가 처리되어 게시물이 숨김 처리되었습니다: ' || coalesce(v_title, '토론'), 'report:' || p_report_id::text || ':reviewed');
end;
$$;

create or replace function public.admin_dismiss_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_reporter_id uuid; v_debate_id uuid; v_title text;
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  select r.reporter_id, r.debate_id, d.title into v_reporter_id, v_debate_id, v_title from public.reports r left join public.debates d on d.id=r.debate_id where r.id=p_report_id;
  update public.reports set status = 'dismissed' where id = p_report_id;
  perform public.create_notification(v_reporter_id, auth.uid(), v_debate_id, 'report_result', '신고 검토 결과, 조치하지 않기로 결정되었습니다: ' || coalesce(v_title, '토론'), 'report:' || p_report_id::text || ':dismissed');
end;
$$;

revoke all on function public.create_notification(uuid, uuid, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.award_points(uuid, integer, text, uuid, text) from public, anon, authenticated;
revoke all on function public.settle_debate_points(uuid) from public, anon;
revoke all on function public.admin_hide_debate(uuid, uuid) from public, anon;
revoke all on function public.admin_dismiss_report(uuid) from public, anon;
grant execute on function public.settle_debate_points(uuid) to authenticated;
grant execute on function public.admin_hide_debate(uuid, uuid) to authenticated;
grant execute on function public.admin_dismiss_report(uuid) to authenticated;

