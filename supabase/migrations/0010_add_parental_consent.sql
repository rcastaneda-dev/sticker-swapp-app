-- Parental consent flow: tokens table, request/confirm RPCs, immutability extension.
-- The parental_consent_at column already exists in user_profiles (migration 0004).

-- 1. Add parent_email to user_profiles (nullable; only populated for under-13 users)
alter table user_profiles
  add column parent_email text;

-- 2. Consent tokens table — single-use, time-limited tokens
create table parental_consent_tokens (
  id           bigint generated always as identity primary key,
  token        text        not null unique,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  parent_email text        not null,
  expires_at   timestamptz not null,
  consumed_at  timestamptz,           -- null until used; set once on confirmation
  created_at   timestamptz not null default now()
);

-- Fast lookup of unconsumed tokens (the primary query path from Edge Function)
create index idx_consent_token on parental_consent_tokens (token)
  where consumed_at is null;

-- User lookup (checking if user has pending/valid token)
create index idx_consent_token_user on parental_consent_tokens (user_id);

-- RLS: no direct client writes. All mutations go through SECURITY DEFINER RPCs.
alter table parental_consent_tokens enable row level security;

create policy "users_read_own_consent_tokens"
  on parental_consent_tokens for select
  to authenticated
  using (auth.uid() = user_id);

-- 3. RPC: request_parental_consent
--    Called by the under-13 user after entering their parent's email.
--    Generates a cryptographic token, invalidates prior tokens, returns token string.
create or replace function request_parental_consent(p_parent_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid;
  v_is_under_13 boolean;
  v_consent_at  timestamptz;
  v_token       text;
begin
  v_user_id := auth.uid();

  -- Must be under-13 and not already consented
  select is_under_13, parental_consent_at
  into v_is_under_13, v_consent_at
  from user_profiles
  where user_id = v_user_id;

  if v_is_under_13 is null or v_is_under_13 = false then
    raise exception 'Parental consent is only required for users under 13';
  end if;

  if v_consent_at is not null then
    raise exception 'Parental consent has already been granted';
  end if;

  -- Invalidate any existing unconsumed tokens (only latest request is valid)
  update parental_consent_tokens
  set consumed_at = now()
  where user_id = v_user_id
    and consumed_at is null;

  -- Generate 32-byte cryptographically random token (64 hex chars)
  v_token := encode(gen_random_bytes(32), 'hex');

  -- Insert with 7-day expiry
  insert into parental_consent_tokens (token, user_id, parent_email, expires_at)
  values (v_token, v_user_id, p_parent_email, now() + interval '7 days');

  -- Store parent_email on user_profiles for reference
  update user_profiles
  set parent_email = p_parent_email
  where user_id = v_user_id;

  return v_token;
end;
$$;

revoke execute on function request_parental_consent from public;
revoke execute on function request_parental_consent from anon;
grant execute on function request_parental_consent to authenticated;
grant execute on function request_parental_consent to service_role;

-- 4. RPC: confirm_parental_consent
--    Called by the confirm-consent Edge Function (service_role) when parent clicks the link.
create or replace function confirm_parental_consent(p_token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record  record;
  v_user_id uuid;
begin
  -- Look up the token
  select * into v_record
  from parental_consent_tokens
  where token = p_token;

  if v_record is null then
    return json_build_object('success', false, 'error', 'invalid_token');
  end if;

  if v_record.consumed_at is not null then
    return json_build_object('success', false, 'error', 'already_used');
  end if;

  if v_record.expires_at < now() then
    return json_build_object('success', false, 'error', 'expired');
  end if;

  v_user_id := v_record.user_id;

  -- Mark token as consumed
  update parental_consent_tokens
  set consumed_at = now()
  where id = v_record.id;

  -- Stamp parental_consent_at on user_profiles
  update user_profiles
  set parental_consent_at = now()
  where user_id = v_user_id;

  -- Mirror to user metadata so JWT reflects consent status
  update auth.users
  set raw_user_meta_data = raw_user_meta_data ||
    jsonb_build_object(
      'parental_consent_at',
      to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    )
  where id = v_user_id;

  return json_build_object('success', true, 'user_id', v_user_id::text);
end;
$$;

revoke execute on function confirm_parental_consent from public;
revoke execute on function confirm_parental_consent from anon;
revoke execute on function confirm_parental_consent from authenticated;
grant execute on function confirm_parental_consent to service_role;

-- 5. Extend immutability trigger to also protect parental consent fields
create or replace function prevent_under13_mutation()
returns trigger
language plpgsql
as $$
begin
  -- Lock age verification fields once verified (existing from migration 0009)
  if old.age_verified_at is not null then
    if new.date_of_birth    is distinct from old.date_of_birth
       or new.is_under_13   is distinct from old.is_under_13
       or new.age_verified_at is distinct from old.age_verified_at then
      raise exception 'Age verification fields cannot be changed once verified';
    end if;
  end if;

  -- Lock parental consent fields once consent is granted
  if old.parental_consent_at is not null then
    if new.parental_consent_at is distinct from old.parental_consent_at then
      raise exception 'Parental consent timestamp cannot be changed once set';
    end if;
    if new.parent_email is distinct from old.parent_email then
      raise exception 'Parent email cannot be changed after consent is granted';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

-- The existing trigger trg_user_profiles_before_update already calls
-- prevent_under13_mutation(), so replacing the function body is sufficient.
