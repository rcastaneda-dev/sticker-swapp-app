-- Age verification: add DOB + verified timestamp, server-side verify_age() RPC,
-- and stronger immutability trigger that locks all age fields after verification.

-- 1. Add columns to user_profiles
alter table user_profiles
  add column date_of_birth date,
  add column age_verified_at timestamptz;

-- 2. Server-side age verification RPC.
--    Takes a date of birth, calculates is_under_13 on the server (prevents
--    client-side tampering), and stamps age_verified_at.  Raises an exception
--    if the user has already verified (immutability guarantee).
create or replace function verify_age(p_date_of_birth date)
returns boolean
language plpgsql
security definer
as $$
declare
  v_is_under_13 boolean;
  v_age         int;
begin
  -- Prevent re-verification
  if exists (
    select 1 from user_profiles
    where user_id = auth.uid() and age_verified_at is not null
  ) then
    raise exception 'Age has already been verified and cannot be changed';
  end if;

  -- Calculate age server-side
  v_age := extract(year from age(current_date, p_date_of_birth));
  v_is_under_13 := v_age < 13;

  -- Update the caller's profile
  update user_profiles
  set date_of_birth    = p_date_of_birth,
      is_under_13      = v_is_under_13,
      age_verified_at  = now()
  where user_id = auth.uid();

  return v_is_under_13;
end;
$$;

-- 3. Replace the old prevent_under13_mutation() trigger with a broader one
--    that locks date_of_birth, is_under_13, AND age_verified_at once
--    age_verified_at is set.
create or replace function prevent_under13_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.age_verified_at is not null then
    if new.date_of_birth    is distinct from old.date_of_birth
       or new.is_under_13   is distinct from old.is_under_13
       or new.age_verified_at is distinct from old.age_verified_at then
      raise exception 'Age verification fields cannot be changed once verified';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- The existing trigger trg_user_profiles_before_update already calls
-- prevent_under13_mutation(), so replacing the function body is sufficient.
-- No need to drop/recreate the trigger.
