-- OnDebate admin and report tools. Run once in Supabase SQL Editor.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated;

create or replace function public.submit_debate_report(p_debate_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare report_id uuid; current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception '로그인이 필요합니다.'; end if;
  if char_length(trim(p_reason)) < 5 or char_length(trim(p_reason)) > 1000 then raise exception '신고 사유는 5~1000자로 입력해 주세요.'; end if;
  if not exists (select 1 from public.debates where id = p_debate_id and status <> 'hidden') then raise exception '신고할 토론을 찾을 수 없습니다.'; end if;
  if exists (select 1 from public.reports where reporter_id = current_user_id and debate_id = p_debate_id and status = 'open') then raise exception '이미 검토 중인 신고가 있습니다.'; end if;
  insert into public.reports (reporter_id, debate_id, reason) values (current_user_id, p_debate_id, trim(p_reason)) returning id into report_id;
  return report_id;
end; $$;
grant execute on function public.submit_debate_report(uuid, text) to authenticated;

create or replace function public.admin_reports()
returns table (id uuid, debate_id uuid, title text, category text, reason text, status text, created_at timestamptz, reporter_nickname text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  return query select r.id, r.debate_id, d.title, d.category, r.reason, r.status, r.created_at, coalesce(p.nickname, '탈퇴한 사용자')
  from public.reports r join public.debates d on d.id = r.debate_id left join public.profiles p on p.id = r.reporter_id
  order by case when r.status = 'open' then 0 else 1 end, r.created_at desc;
end; $$;
grant execute on function public.admin_reports() to authenticated;

create or replace function public.admin_hide_debate(p_debate_id uuid, p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.debates set status = 'hidden' where id = p_debate_id;
  update public.reports set status = 'reviewed' where id = p_report_id and debate_id = p_debate_id;
end; $$;
grant execute on function public.admin_hide_debate(uuid, uuid) to authenticated;

create or replace function public.admin_dismiss_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '관리자 권한이 필요합니다.'; end if;
  update public.reports set status = 'dismissed' where id = p_report_id;
end; $$;
grant execute on function public.admin_dismiss_report(uuid) to authenticated;

-- Make your existing account an administrator. Replace the nickname before running.
-- insert into public.admin_users (user_id) select id from public.profiles where nickname = '내 닉네임';

