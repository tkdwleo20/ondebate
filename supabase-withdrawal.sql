-- Run once in Supabase Dashboard > SQL Editor before deploying delete-account.
-- Keeps posts and comments when their author deletes the account.
alter table public.debates alter column creator_id drop not null;
alter table public.debate_messages alter column author_id drop not null;
alter table public.message_comments alter column author_id drop not null;
alter table public.debate_comments alter column author_id drop not null;

alter table public.debates drop constraint if exists debates_creator_id_fkey;
alter table public.debates add constraint debates_creator_id_fkey foreign key (creator_id) references public.profiles(id) on delete set null;
alter table public.debates drop constraint if exists debates_opponent_id_fkey;
alter table public.debates add constraint debates_opponent_id_fkey foreign key (opponent_id) references public.profiles(id) on delete set null;
alter table public.debate_messages drop constraint if exists debate_messages_author_id_fkey;
alter table public.debate_messages add constraint debate_messages_author_id_fkey foreign key (author_id) references public.profiles(id) on delete set null;
alter table public.message_comments drop constraint if exists message_comments_author_id_fkey;
alter table public.message_comments add constraint message_comments_author_id_fkey foreign key (author_id) references public.profiles(id) on delete set null;
alter table public.debate_comments drop constraint if exists debate_comments_author_id_fkey;
alter table public.debate_comments add constraint debate_comments_author_id_fkey foreign key (author_id) references public.profiles(id) on delete set null;

