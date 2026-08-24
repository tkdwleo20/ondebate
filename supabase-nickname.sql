-- Run once in Supabase SQL Editor. Prevents case-only duplicate nicknames.
create unique index if not exists profiles_nickname_case_insensitive_idx on public.profiles (lower(nickname));

