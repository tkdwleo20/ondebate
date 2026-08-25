-- OnDebate scalable listing/search queries.
-- Run this AFTER supabase-schema.sql. These functions return only one page at a time.

create extension if not exists pg_trgm;

create index if not exists debates_visible_created_idx
  on public.debates (created_at desc, id desc) where status <> 'hidden';
create index if not exists debates_category_visible_created_idx
  on public.debates (category, created_at desc, id desc) where status <> 'hidden';
create index if not exists debate_messages_author_created_idx
  on public.debate_messages (author_id, created_at desc);
create index if not exists debate_comments_author_created_idx
  on public.debate_comments (author_id, created_at desc);
create index if not exists message_comments_author_created_idx
  on public.message_comments (author_id, created_at desc);
create index if not exists votes_debate_created_idx
  on public.votes (debate_id, created_at desc);
create index if not exists debates_title_trgm_idx
  on public.debates using gin (title gin_trgm_ops) where status <> 'hidden';
create index if not exists debate_messages_body_trgm_idx
  on public.debate_messages using gin (body gin_trgm_ops);

create or replace function public.list_debates_page(
  p_category text default null,
  p_page integer default 1,
  p_page_size integer default 20
)
returns table (
  id uuid, title text, category text, status text, ends_at timestamptz,
  created_at timestamptz, opening_preview text, total_count bigint
)
language sql stable security definer set search_path = public as $$
  with filtered as (
    select d.*, count(*) over() as total_count
    from public.debates d
    where d.status <> 'hidden'
      and (p_category is null or d.category = p_category)
  )
  select f.id, f.title, f.category, f.status, f.ends_at, f.created_at,
    coalesce((select m.body from public.debate_messages m where m.debate_id = f.id order by m.created_at asc limit 1), '') as opening_preview,
    f.total_count
  from filtered f
  order by f.created_at desc, f.id desc
  offset greatest(0, p_page - 1) * least(greatest(p_page_size, 1), 50)
  limit least(greatest(p_page_size, 1), 50);
$$;

create or replace function public.search_debates_page(
  p_query text,
  p_page integer default 1,
  p_page_size integer default 20
)
returns table (
  id uuid, title text, category text, status text, ends_at timestamptz,
  created_at timestamptz, opening_preview text, total_count bigint
)
language sql stable security definer set search_path = public as $$
  with filtered as (
    select d.*, count(*) over() as total_count
    from public.debates d
    where d.status <> 'hidden'
      and (
        d.title ilike '%' || trim(p_query) || '%'
        or exists (
          select 1 from public.debate_messages m
          where m.debate_id = d.id and m.body ilike '%' || trim(p_query) || '%'
        )
      )
  )
  select f.id, f.title, f.category, f.status, f.ends_at, f.created_at,
    coalesce((select m.body from public.debate_messages m where m.debate_id = f.id order by m.created_at asc limit 1), '') as opening_preview,
    f.total_count
  from filtered f
  order by f.created_at desc, f.id desc
  offset greatest(0, p_page - 1) * least(greatest(p_page_size, 1), 50)
  limit least(greatest(p_page_size, 1), 50);
$$;

create or replace function public.popular_debates(p_hours integer)
returns table (
  id uuid, title text, category text, status text, ends_at timestamptz,
  created_at timestamptz, opening_preview text, vote_count bigint
)
language sql stable security definer set search_path = public as $$
  select d.id, d.title, d.category, d.status, d.ends_at, d.created_at,
    coalesce((select m.body from public.debate_messages m where m.debate_id = d.id order by m.created_at asc limit 1), '') as opening_preview,
    count(v.id) as vote_count
  from public.debates d
  join public.votes v on v.debate_id = d.id and v.created_at >= now() - make_interval(hours => least(greatest(p_hours, 1), 24 * 31))
  where d.status <> 'hidden'
  group by d.id
  order by count(v.id) desc, d.created_at desc
  limit 5;
$$;

create or replace function public.my_debates_page(
  p_page integer default 1,
  p_page_size integer default 5
)
returns table (
  id uuid, title text, category text, status text, created_at timestamptz,
  creator_id uuid, opponent_id uuid, total_count bigint
)
language sql stable security definer set search_path = public as $$
  with mine as (
    select d.*, count(*) over() as total_count
    from public.debates d
    where auth.uid() is not null and d.status <> 'hidden' and (d.creator_id = auth.uid() or d.opponent_id = auth.uid())
  )
  select id, title, category, status, created_at, creator_id, opponent_id, total_count
  from mine
  order by created_at desc, id desc
  offset greatest(0, p_page - 1) * least(greatest(p_page_size, 1), 50)
  limit least(greatest(p_page_size, 1), 50);
$$;

create or replace function public.my_comments_page(
  p_page integer default 1,
  p_page_size integer default 5
)
returns table (
  debate_id uuid, debate_title text, body text, created_at timestamptz, total_count bigint
)
language sql stable security definer set search_path = public as $$
  with mine as (
    select dm.debate_id, d.title as debate_title, mc.body, mc.created_at
    from public.message_comments mc
    join public.debate_messages dm on dm.id = mc.message_id
    join public.debates d on d.id = dm.debate_id
    where mc.author_id = auth.uid() and d.status <> 'hidden'
    union all
    select dc.debate_id, d.title as debate_title, dc.body, dc.created_at
    from public.debate_comments dc
    join public.debates d on d.id = dc.debate_id
    where dc.author_id = auth.uid() and d.status <> 'hidden'
  ), numbered as (
    select mine.*, count(*) over() as total_count from mine
  )
  select debate_id, debate_title, body, created_at, total_count
  from numbered
  order by created_at desc, debate_id desc
  offset greatest(0, p_page - 1) * least(greatest(p_page_size, 1), 50)
  limit least(greatest(p_page_size, 1), 50);
$$;

revoke all on function public.list_debates_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.search_debates_page(text, integer, integer) from public, anon, authenticated;
revoke all on function public.popular_debates(integer) from public, anon, authenticated;
revoke all on function public.my_debates_page(integer, integer) from public, anon;
revoke all on function public.my_comments_page(integer, integer) from public, anon;
grant execute on function public.list_debates_page(text, integer, integer) to anon, authenticated;
grant execute on function public.search_debates_page(text, integer, integer) to anon, authenticated;
grant execute on function public.popular_debates(integer) to anon, authenticated;
grant execute on function public.my_debates_page(integer, integer) to authenticated;
grant execute on function public.my_comments_page(integer, integer) to authenticated;

