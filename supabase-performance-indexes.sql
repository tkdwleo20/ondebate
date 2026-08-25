-- OnDebate foreign-key indexes. Run once after the schema migrations.
-- These indexes keep deletion, withdrawal, moderation, and joins fast as data grows.

create index if not exists debate_comment_likes_user_idx on public.debate_comment_likes(user_id);
create index if not exists debate_comments_debate_idx on public.debate_comments(debate_id);
create index if not exists debate_comments_parent_idx on public.debate_comments(parent_id);
create index if not exists debates_creator_idx on public.debates(creator_id);
create index if not exists debates_opponent_idx on public.debates(opponent_id);
create index if not exists message_comment_likes_user_idx on public.message_comment_likes(user_id);
create index if not exists message_comments_message_idx on public.message_comments(message_id);
create index if not exists message_comments_parent_idx on public.message_comments(parent_id);
create index if not exists message_likes_user_idx on public.message_likes(user_id);
create index if not exists notifications_actor_idx on public.notifications(actor_id);
create index if not exists notifications_debate_idx on public.notifications(debate_id);
create index if not exists point_ledger_user_created_idx on public.point_ledger(user_id, created_at desc);
create index if not exists point_ledger_debate_idx on public.point_ledger(debate_id);
create index if not exists reports_reporter_idx on public.reports(reporter_id);
create index if not exists reports_debate_idx on public.reports(debate_id);
create index if not exists reports_message_idx on public.reports(message_id);
create index if not exists reports_comment_idx on public.reports(comment_id);
create index if not exists reports_reported_user_idx on public.reports(reported_user_id);
create index if not exists votes_voter_idx on public.votes(voter_id);

