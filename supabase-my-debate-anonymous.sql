-- Show the current user's anonymous/public setting in their own debate list.
-- This exposes no other participant identity information.

create or replace function public.my_debates_page(
  p_page integer default 1,
  p_page_size integer default 5
)
returns table (
  id uuid, title text, category text, status text, created_at timestamptz,
  creator_id uuid, opponent_id uuid,
  creator_is_anonymous boolean, opponent_is_anonymous boolean,
  total_count bigint
)
language sql stable security definer set search_path = public as $$
  with mine as (
    select d.*, count(*) over() as total_count
    from public.debates d
    where auth.uid() is not null
      and d.status <> 'hidden'
      and (d.creator_id = auth.uid() or d.opponent_id = auth.uid())
  )
  select id, title, category, status, created_at, creator_id, opponent_id,
    creator_is_anonymous, opponent_is_anonymous, total_count
  from mine
  order by created_at desc, id desc
  offset greatest(0, p_page - 1) * least(greatest(p_page_size, 1), 50)
  limit least(greatest(p_page_size, 1), 50);
$$;

revoke all on function public.my_debates_page(integer, integer) from public, anon;
grant execute on function public.my_debates_page(integer, integer) to authenticated;

