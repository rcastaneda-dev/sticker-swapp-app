-- Add location_updated_at to find_nearby_traders() return type.
-- The updated_at field from user_locations serves as a natural proxy for
-- user activity — actively trading users update their location frequently.
-- The Go matchmaking scoring engine uses this for the Activity sub-score.
--
-- PostgreSQL does not allow CREATE OR REPLACE to change the return type
-- of an existing function, so we must DROP + CREATE.

drop function if exists find_nearby_traders(double precision, double precision, int);

create function find_nearby_traders(
  lat       double precision,
  lng       double precision,
  radius_m  int default 5000       -- 5 km default
)
returns table (
  user_id              uuid,
  distance_m           double precision,
  display_name         text,
  duplicate_count      bigint,
  needed_count         bigint,
  location_updated_at  timestamptz       -- activity proxy (new)
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

  return query
  select
    ul.user_id,
    st_distance(
      ul.location,
      st_setsrid(st_makepoint(lng, lat), 4326)::geography
    ) as distance_m,
    up.display_name,
    inv.duplicate_count,
    inv.needed_count,
    ul.updated_at as location_updated_at
  from user_locations ul
  inner join user_profiles up on up.user_id = ul.user_id
  inner join (
    -- Pre-aggregate inventory counts per user; only keep users with duplicates
    select
      ui.user_id,
      count(*) filter (where ui.status = 'DUPLICATE') as duplicate_count,
      count(*) filter (where ui.status = 'NEEDED')    as needed_count
    from user_inventory ui
    group by ui.user_id
    having count(*) filter (where ui.status = 'DUPLICATE') > 0
  ) inv on inv.user_id = ul.user_id
  where
    -- Exclude the calling user
    ul.user_id <> auth.uid()
    -- Under-13 users are excluded from location/trade features
    and up.is_under_13 = false
    -- PostGIS indexed proximity filter
    and st_dwithin(
      ul.location,
      st_setsrid(st_makepoint(lng, lat), 4326)::geography,
      radius_m
    )
  -- KNN index-accelerated ordering via <-> operator
  order by ul.location <-> st_setsrid(st_makepoint(lng, lat), 4326)::geography
  limit 50;
end;
$$;

-- Restore permissions (DROP removed them)
revoke all on function find_nearby_traders(double precision, double precision, int) from public;
revoke all on function find_nearby_traders(double precision, double precision, int) from anon;
grant execute on function find_nearby_traders(double precision, double precision, int) to authenticated;
