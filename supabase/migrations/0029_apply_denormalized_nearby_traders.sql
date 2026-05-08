-- Apply winning optimization: denormalized inventory counts on user_profiles.
--
-- Benchmark results (200 samples, 1000 users, 5 km radius):
--   Baseline:           p95 = 188.2 ms (FAIL)
--   A: LATERAL:         p95 =   1.4 ms (PASS)
--   B: Denormalized:    p95 =   0.9 ms (PASS) ← WINNER
--   C: Materialized:    p95 =   1.0 ms (PASS)
--
-- The denormalized approach stores inventory_duplicate_count and
-- inventory_needed_count directly on user_profiles, maintained by a
-- row-level trigger on user_inventory. This eliminates the expensive
-- GROUP BY aggregation from the hot query path entirely.
--
-- The columns and trigger were already created in migration 0028
-- (benchmark setup). This migration:
--   1. Replaces find_nearby_traders() with the denormalized variant
--   2. Drops the temporary benchmark variant functions
--   3. Drops the materialized view and its trigger (not needed)

-- ============================================================
-- Step 1: Replace find_nearby_traders() with denormalized version
-- ============================================================
-- PostgreSQL does not allow CREATE OR REPLACE to change the body of a
-- SECURITY DEFINER function that references different tables, but since
-- the return type is the same we can use CREATE OR REPLACE.

drop function if exists find_nearby_traders(double precision, double precision, int);

create function find_nearby_traders(
  lat       double precision,
  lng       double precision,
  radius_m  int default 5000
)
returns table (
  user_id              uuid,
  distance_m           double precision,
  display_name         text,
  duplicate_count      bigint,
  needed_count         bigint,
  location_updated_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
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
    up.inventory_duplicate_count::bigint as duplicate_count,
    up.inventory_needed_count::bigint    as needed_count,
    ul.updated_at as location_updated_at
  from user_locations ul
  inner join user_profiles up on up.user_id = ul.user_id
  where
    ul.user_id <> auth.uid()
    and up.is_under_13 = false
    and up.inventory_duplicate_count > 0
    and st_dwithin(
      ul.location,
      st_setsrid(st_makepoint(lng, lat), 4326)::geography,
      radius_m
    )
  order by ul.location <-> st_setsrid(st_makepoint(lng, lat), 4326)::geography
  limit 50;
end;
$$;

revoke all on function find_nearby_traders(double precision, double precision, int) from public;
revoke all on function find_nearby_traders(double precision, double precision, int) from anon;
grant execute on function find_nearby_traders(double precision, double precision, int) to authenticated;

-- ============================================================
-- Step 2: Drop temporary benchmark variant functions
-- ============================================================
drop function if exists find_nearby_traders_lateral(double precision, double precision, int);
drop function if exists find_nearby_traders_denormalized(double precision, double precision, int);
drop function if exists find_nearby_traders_matview(double precision, double precision, int);

-- ============================================================
-- Step 3: Drop materialized view and its trigger (not needed)
-- ============================================================
drop trigger if exists trg_refresh_trader_stats on user_inventory;
drop function if exists refresh_trader_inventory_stats();
drop materialized view if exists trader_inventory_stats;
