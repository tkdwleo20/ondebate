-- Structured report reasons with an optional detail field.
-- Existing free-form reports stay readable as "기존 신고" entries.

alter table public.reports add column if not exists reason_type text;
alter table public.reports alter column reason drop not null;

do $$
begin
  if exists (select 1 from pg_constraint where conname = 'reports_reason_check' and conrelid = 'public.reports'::regclass) then
    alter table public.reports drop constraint reports_reason_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'reports_reason_type_check' and conrelid = 'public.reports'::regclass) then
    alter table public.reports add constraint reports_reason_type_check check (
      reason_type is null or reason_type in (
        '욕설, 모욕', '혐오, 차별 표현', '성적, 불쾌한 내용',
        '허위 정보, 사실 왜곡', '도배, 광고, 홍보', '기타'
      )
    );
  end if;
end;
$$;

alter table public.reports add constraint reports_reason_check
  check (reason is null or char_length(trim(reason)) between 5 and 1000);

create or replace function public.submit_debate_report(
  p_debate_id uuid,
  p_reason_type text,
  p_reason_detail text,
  p_target_side text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_user_id uuid := auth.uid(); v_target_id uuid; v_detail text;
begin
  if v_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if p_target_side not in ('left', 'right') then raise exception '신고 대상을 선택해 주세요.'; end if;
  if p_reason_type not in ('욕설, 모욕', '혐오, 차별 표현', '성적, 불쾌한 내용', '허위 정보, 사실 왜곡', '도배, 광고, 홍보', '기타') then
    raise exception '신고 사유를 선택해 주세요.';
  end if;

  v_detail := nullif(trim(coalesce(p_reason_detail, '')), '');
  if v_detail is not null and char_length(v_detail) > 1000 then raise exception '상세 설명은 1,000자 이내로 입력해 주세요.'; end if;
  if p_reason_type = '기타' and (v_detail is null or char_length(v_detail) < 5) then
    raise exception '기타 사유는 상세 설명을 5자 이상 입력해 주세요.';
  end if;

  select case when p_target_side = 'left' then creator_id else opponent_id end
  into v_target_id from public.debates where id = p_debate_id and status <> 'hidden';
  if v_target_id is null then raise exception '신고할 참가자를 찾을 수 없습니다.'; end if;
  if exists (select 1 from public.reports where reporter_id = v_user_id and debate_id = p_debate_id and status = 'open') then
    raise exception '이미 검토 중인 신고가 있습니다.';
  end if;

  insert into public.reports(reporter_id, debate_id, reported_user_id, reason_type, reason)
  values(v_user_id, p_debate_id, v_target_id, p_reason_type, v_detail)
  returning id into v_id;
  return v_id;
end;
$$;

drop function if exists public.admin_reports();
create function public.admin_reports()
returns table (
  id uuid, debate_id uuid, title text, category text, reason text,
  reason_type text, reason_detail text, status text, created_at timestamptz,
  reporter_nickname text, reported_nickname text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query
  select r.id, r.debate_id, d.title, d.category, r.reason, r.reason_type, r.reason, r.status, r.created_at,
    '익명 ' || public.anonymous_code_for(r.debate_id, r.reporter_id),
    case when coalesce((select m.is_anonymous from public.debate_messages m where m.debate_id = d.id and m.author_id = r.reported_user_id order by m.created_at limit 1), false)
      then '익명 ' || coalesce((select m.anonymous_code from public.debate_messages m where m.debate_id = d.id and m.author_id = r.reported_user_id order by m.created_at limit 1), '사용자')
      else coalesce(target.nickname, '탈퇴한 사용자') end
  from public.reports r join public.debates d on d.id = r.debate_id
  left join public.profiles target on target.id = r.reported_user_id
  order by case when r.status = 'open' then 0 else 1 end, r.created_at desc;
end;
$$;

revoke all on function public.submit_debate_report(uuid, text, text, text) from public, anon;
grant execute on function public.submit_debate_report(uuid, text, text, text) to authenticated;
grant execute on function public.admin_reports() to authenticated;

