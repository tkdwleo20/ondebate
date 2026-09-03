-- OnDebate policy consent records.
-- Run once in Supabase SQL Editor before deploying the matching frontend.

create table if not exists public.user_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  terms_accepted_at timestamptz not null,
  privacy_accepted_at timestamptz not null,
  consent_source text not null check (consent_source in ('email_signup', 'oauth_nickname', 'renewal', 'legacy_metadata')),
  updated_at timestamptz not null default now()
);

alter table public.user_consents enable row level security;

drop policy if exists "No direct consent access" on public.user_consents;
create policy "No direct consent access" on public.user_consents
  as restrictive for all using (false) with check (false);

create or replace function public.capture_email_signup_consent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.raw_user_meta_data ? 'terms_accepted_at'
     and new.raw_user_meta_data ? 'privacy_accepted_at' then
    insert into public.user_consents (
      user_id, terms_version, privacy_version,
      terms_accepted_at, privacy_accepted_at, consent_source
    ) values (
      new.id, '2026-08-31', '2026-08-31',
      (new.raw_user_meta_data ->> 'terms_accepted_at')::timestamptz,
      (new.raw_user_meta_data ->> 'privacy_accepted_at')::timestamptz,
      'email_signup'
    )
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_signup_consent on auth.users;
create trigger on_auth_user_email_signup_consent
  after insert on auth.users
  for each row execute function public.capture_email_signup_consent();

insert into public.user_consents (
  user_id, terms_version, privacy_version,
  terms_accepted_at, privacy_accepted_at, consent_source
)
select
  u.id, '2026-08-31', '2026-08-31',
  coalesce((u.raw_user_meta_data ->> 'terms_accepted_at')::timestamptz, u.created_at),
  coalesce((u.raw_user_meta_data ->> 'privacy_accepted_at')::timestamptz, u.created_at),
  'legacy_metadata'
from auth.users u
where u.raw_user_meta_data ? 'terms_accepted_at'
  and u.raw_user_meta_data ? 'privacy_accepted_at'
on conflict (user_id) do nothing;

create or replace function public.has_current_policy_consent()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_consents c
    where c.user_id = auth.uid()
      and c.terms_version = '2026-08-31'
      and c.privacy_version = '2026-08-31'
      and c.terms_accepted_at is not null
      and c.privacy_accepted_at is not null
  );
$$;

create or replace function public.accept_current_policies(p_source text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_source not in ('email_signup', 'oauth_nickname', 'renewal') then
    raise exception '올바르지 않은 동의 경로입니다.';
  end if;

  insert into public.user_consents (
    user_id, terms_version, privacy_version,
    terms_accepted_at, privacy_accepted_at, consent_source, updated_at
  ) values (
    v_user_id, '2026-08-31', '2026-08-31',
    v_now, v_now, p_source, v_now
  )
  on conflict (user_id) do update set
    terms_version = excluded.terms_version,
    privacy_version = excluded.privacy_version,
    terms_accepted_at = excluded.terms_accepted_at,
    privacy_accepted_at = excluded.privacy_accepted_at,
    consent_source = excluded.consent_source,
    updated_at = excluded.updated_at;
end;
$$;

revoke all on table public.user_consents from public, anon, authenticated;
revoke all on function public.has_current_policy_consent() from public, anon, authenticated;
revoke all on function public.accept_current_policies(text) from public, anon, authenticated;
revoke all on function public.capture_email_signup_consent() from public, anon, authenticated;
grant execute on function public.has_current_policy_consent() to authenticated;
grant execute on function public.accept_current_policies(text) to authenticated;
