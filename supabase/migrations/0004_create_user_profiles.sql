-- User profiles: age safeguards, trust score, preferences

create table user_profiles (
  user_id              uuid        primary key references auth.users(id) on delete cascade,
  display_name         text,
  is_under_13          boolean     not null default false,
  parental_consent_at  timestamptz,
  trust_score          smallint    not null default 50
                                   check (trust_score between 0 and 100),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- Prevent is_under_13 from being changed once set to true
create or replace function prevent_under13_mutation()
returns trigger as $$
begin
  if old.is_under_13 = true and new.is_under_13 is distinct from old.is_under_13 then
    raise exception 'is_under_13 cannot be changed once set to true';
  end if;
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

create trigger trg_user_profiles_before_update
  before update on user_profiles
  for each row
  execute function prevent_under13_mutation();

-- RLS: users can only read and write their own row
alter table user_profiles enable row level security;

create policy "users_read_own_profile"
  on user_profiles for select
  using (auth.uid() = user_id);

create policy "users_insert_own_profile"
  on user_profiles for insert
  with check (auth.uid() = user_id);

create policy "users_update_own_profile"
  on user_profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
