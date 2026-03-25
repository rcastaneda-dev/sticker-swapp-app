-- Replace broad authenticated SELECT on user_locations with a SECURITY DEFINER
-- RPC so clients cannot dump the full table.  Reads now go through
-- find_nearby_users(lat, lon, radius_m, max_results) which enforces proximity
-- bounds, excludes under-13 users, and excludes the caller.

-- 1. Drop the permissive SELECT policy added in 0007
drop policy if exists "authenticated_read_locations" on user_locations;

-- 2. Create the proximity-search RPC
--    Returns nearby users within `radius_m` metres, ordered closest-first.
--    SECURITY DEFINER runs as the function owner (postgres) so it can read
--    user_locations despite having no SELECT policy for authenticated users.
create or replace function find_nearby_users(
  lat       double precision,
  lon       double precision,
  radius_m  int default 5000,       -- 5 km default
  max_results int default 50
)
returns table (
  user_id     uuid,
  distance_m  double precision,
  accuracy_m  int,
  updated_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Clamp radius to 50 km to prevent full-table scans
  if radius_m > 50000 then
    radius_m := 50000;
  end if;

  -- Clamp max_results to 100
  if max_results > 100 then
    max_results := 100;
  end if;

  return query
  select
    ul.user_id,
    st_distance(
      ul.location,
      st_setsrid(st_makepoint(lon, lat), 4326)::geography
    ) as distance_m,
    ul.accuracy_m,
    ul.updated_at
  from user_locations ul
  inner join user_profiles up on up.user_id = ul.user_id
  where
    -- Exclude the calling user
    ul.user_id <> auth.uid()
    -- Under-13 users are excluded from location features
    and up.is_under_13 = false
    -- PostGIS indexed proximity filter (uses GiST index)
    and st_dwithin(
      ul.location,
      st_setsrid(st_makepoint(lon, lat), 4326)::geography,
      radius_m
    )
  order by distance_m
  limit max_results;
end;
$$;

-- 3. Only authenticated users may call the RPC
revoke all on function find_nearby_users(double precision, double precision, int, int) from public;
revoke all on function find_nearby_users(double precision, double precision, int, int) from anon;
grant execute on function find_nearby_users(double precision, double precision, int, int) to authenticated;
