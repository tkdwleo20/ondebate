-- OnDebate MVP schema. Run this once in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null unique check (char_length(nickname) between 2 and 20),
  points integer not null default 0 check (points >= 0),
  nickname_change_count integer not null default 0 check (nickname_change_count >= 0),
  nickname_changed_at timestamptz,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.debates (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  opponent_id uuid references public.profiles(id) on delete set null,
  title text not null check (char_length(title) between 2 and 100),
  category text not null,
  duration_hours smallint not null check (duration_hours between 1 and 24),
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  status text not null default 'waiting' check (status in ('waiting', 'active', 'ended', 'hidden')),
  created_at timestamptz not null default now()
);

create table public.debate_messages (
  id uuid primary key default gen_random_uuid(),
  debate_id uuid not null references public.debates(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  side text not null check (side in ('left', 'right')),
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now()
);

create table public.message_comments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.debate_messages(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table public.debate_comments (
  id uuid primary key default gen_random_uuid(),
  debate_id uuid not null references public.debates(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table public.votes (
  id uuid primary key default gen_random_uuid(),
  debate_id uuid not null references public.debates(id) on delete cascade,
  voter_id uuid not null references public.profiles(id) on delete cascade,
  chosen_side text not null check (chosen_side in ('left', 'right')),
  created_at timestamptz not null default now(),
  unique (debate_id, voter_id)
);

create table public.point_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null,
  reason text not null check (reason in ('daily_checkin', 'debate_entry', 'mutual_agreement', 'vote_win', 'moderation_penalty')),
  debate_id uuid references public.debates(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  debate_id uuid references public.debates(id) on delete cascade,
  message_id uuid references public.debate_messages(id) on delete cascade,
  comment_id uuid references public.debate_comments(id) on delete cascade,
  reason text not null check (char_length(reason) between 5 and 1000),
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now(),
  check (num_nonnulls(debate_id, message_id, comment_id) = 1)
);

create index debates_status_end_idx on public.debates(status, ends_at);
create index debate_messages_debate_created_idx on public.debate_messages(debate_id, created_at);
create index votes_debate_idx on public.votes(debate_id);
create unique index profiles_nickname_case_insensitive_idx on public.profiles (lower(nickname));

alter table public.profiles enable row level security;
alter table public.debates enable row level security;
alter table public.debate_messages enable row level security;
alter table public.message_comments enable row level security;
alter table public.debate_comments enable row level security;
alter table public.votes enable row level security;
alter table public.point_ledger enable row level security;
alter table public.reports enable row level security;

create policy "Public profiles are readable" on public.profiles for select using (true);
create policy "Users create their own profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);

create policy "Visible debates are readable" on public.debates for select using (status <> 'hidden');
create policy "Users create their own debate" on public.debates for insert to authenticated with check ((select auth.uid()) = creator_id and ends_at = started_at + make_interval(hours => duration_hours));
create policy "Creator can update waiting debate" on public.debates for update to authenticated using ((select auth.uid()) = creator_id and status = 'waiting') with check ((select auth.uid()) = creator_id);

create policy "Messages are readable" on public.debate_messages for select using (true);
create policy "Comments on messages are readable" on public.message_comments for select using (true);
create policy "Signed-in users add message comments" on public.message_comments for insert to authenticated with check ((select auth.uid()) = author_id);
create policy "Debate comments are readable" on public.debate_comments for select using (true);
create policy "Signed-in users add debate comments" on public.debate_comments for insert to authenticated with check ((select auth.uid()) = author_id);

create policy "Votes are readable" on public.votes for select using (true);
create policy "A non-participant votes once" on public.votes for insert to authenticated with check (
  (select auth.uid()) = voter_id and not exists (
    select 1 from public.debates d where d.id = debate_id and ((select auth.uid()) = d.creator_id or (select auth.uid()) = d.opponent_id)
  )
);

create policy "Users read their own point history" on public.point_ledger for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users submit reports" on public.reports for insert to authenticated with check ((select auth.uid()) = reporter_id);
create policy "Users read their own reports" on public.reports for select to authenticated using ((select auth.uid()) = reporter_id);

-- Message insertion, opponent joining, point awards, and moderator actions will use
-- database functions in the next implementation step. Keeping these operations out
-- of browser-side inserts prevents point and participation rules from being bypassed.

