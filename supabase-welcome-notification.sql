-- Send each new member one welcome notification when their profile is created.

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  type in (
    'opponent_message', 'message_comment', 'debate_comment',
    'debate_ended', 'debate_result', 'report_result', 'level_change', 'welcome'
  )
);

create or replace function public.notify_new_profile_welcome()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (
    recipient_id, actor_id, debate_id, type, body, event_key
  ) values (
    new.id,
    null,
    null,
    'welcome',
    'OnDebate에 오신 것을 환영합니다! 첫 토론을 열어보세요.',
    'welcome:' || new.id::text
  )
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists profiles_welcome_notification on public.profiles;
create trigger profiles_welcome_notification
after insert on public.profiles
for each row execute function public.notify_new_profile_welcome();

revoke all on function public.notify_new_profile_welcome() from public, anon, authenticated;

