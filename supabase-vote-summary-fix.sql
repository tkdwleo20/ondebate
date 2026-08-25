-- Fix the spectator vote total: a debate with no vote rows must return 0,
-- not 1 from the debate's LEFT JOIN row.
create or replace function public.get_debate_vote_summary(p_debate_id uuid)
returns table (left_votes bigint, right_votes bigint, total_votes bigint, my_chosen_side text)
language sql stable security definer set search_path = public as $$
  select
    count(v.id) filter (where v.chosen_side = 'left'),
    count(v.id) filter (where v.chosen_side = 'right'),
    count(v.id),
    max(v.chosen_side) filter (where v.voter_id = auth.uid())
  from public.debates d
  left join public.votes v on v.debate_id = d.id
  where d.id = p_debate_id and d.status <> 'hidden';
$$;

revoke all on function public.get_debate_vote_summary(uuid) from public, anon, authenticated;
grant execute on function public.get_debate_vote_summary(uuid) to anon, authenticated;
