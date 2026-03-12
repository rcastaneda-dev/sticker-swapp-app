-- Auto-create user_profiles row when a new user signs up via any provider.
-- For email signup: is_under_13 comes from user_metadata (set by the client).
-- For social providers (Google/Apple): defaults to false (DOB collected in onboarding).

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.user_profiles (user_id, display_name, is_under_13)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'display_name',
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1)
    ),
    coalesce((new.raw_user_meta_data->>'is_under_13')::boolean, false)
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
