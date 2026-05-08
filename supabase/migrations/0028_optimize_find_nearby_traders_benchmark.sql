-- Benchmark migration: three optimization variants of find_nearby_traders().
--
-- The original RPC (migration 0015) has a server-side p95 of 191.61 ms due to
-- an inline GROUP BY on user_inventory for ALL users. These three variants
-- each eliminate that bottleneck differently.
--
-- After benchmarking, the winner replaces the original in migration 0029.
-- The variant functions created here are temporary and will be dropped.

-- ============================================================
-- VARIANT A: LATERAL subquery
-- ============================================================
-- Strategy: Filter by ST_DWithin first (uses GiST index, returns ~50 users),
-- then compute inventory counts ONLY for those matched users via LATERAL.

drop function if exists find_nearby_traders_lateral(double precision, double precision, int);
create function find_nearby_traders_lateral(
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
    nearby.user_id,
    nearby.distance_m,
    nearby.display_name,
    inv.duplicate_count,
    inv.needed_count,
    nearby.location_updated_at
  from (
    -- Step 1: Spatial filter (GiST-indexed) — returns ~50 candidates
    select
      ul.user_id,
      st_distance(
        ul.location,
        st_setsrid(st_makepoint(lng, lat), 4326)::geography
      ) as distance_m,
      up.display_name,
      ul.updated_at as location_updated_at
    from user_locations ul
    inner join user_profiles up on up.user_id = ul.user_id
    where
      ul.user_id <> auth.uid()
      and up.is_under_13 = false
      and st_dwithin(
        ul.location,
        st_setsrid(st_makepoint(lng, lat), 4326)::geography,
        radius_m
      )
    order by ul.location <-> st_setsrid(st_makepoint(lng, lat), 4326)::geography
    limit 50
  ) nearby
  inner join lateral (
    -- Step 2: Aggregate inventory ONLY for the ~50 nearby users
    select
      count(*) filter (where ui.status = 'DUPLICATE') as duplicate_count,
      count(*) filter (where ui.status = 'NEEDED')    as needed_count
    from user_inventory ui
    where ui.user_id = nearby.user_id
  ) inv on inv.duplicate_count > 0
  order by nearby.distance_m;
end;
$$;

revoke all on function find_nearby_traders_lateral(double precision, double precision, int) from public;
revoke all on function find_nearby_traders_lateral(double precision, double precision, int) from anon;
grant execute on function find_nearby_traders_lateral(double precision, double precision, int) to authenticated;


-- ============================================================
-- VARIANT B: Denormalized columns on user_profiles
-- ============================================================
-- Strategy: Maintain duplicate_count / needed_count directly on user_profiles
-- via triggers on user_inventory. The RPC joins to user_profiles with zero
-- aggregation at query time.

-- Add columns (default 0 for existing users)
alter table user_profiles add column if not exists inventory_duplicate_count int not null default 0;
alter table user_profiles add column if not exists inventory_needed_count int not null default 0;

-- Populate from existing data
update user_profiles up
set
  inventory_duplicate_count = coalesce(inv.dup, 0),
  inventory_needed_count = coalesce(inv.need, 0)
from (
  select
    ui.user_id,
    count(*) filter (where ui.status = 'DUPLICATE') as dup,
    count(*) filter (where ui.status = 'NEEDED')    as need
  from user_inventory ui
  group by ui.user_id
) inv
where inv.user_id = up.user_id;

-- Trigger function to maintain counts on INSERT/UPDATE/DELETE
create or replace function maintain_inventory_counts()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' or tg_op = 'UPDATE' then
    -- Decrement old counts
    update user_profiles
    set
      inventory_duplicate_count = inventory_duplicate_count
        - case when OLD.status = 'DUPLICATE' then 1 else 0 end,
      inventory_needed_count = inventory_needed_count
        - case when OLD.status = 'NEEDED' then 1 else 0 end
    where user_id = OLD.user_id;
  end if;

  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    -- Increment new counts
    update user_profiles
    set
      inventory_duplicate_count = inventory_duplicate_count
        + case when NEW.status = 'DUPLICATE' then 1 else 0 end,
      inventory_needed_count = inventory_needed_count
        + case when NEW.status = 'NEEDED' then 1 else 0 end
    where user_id = NEW.user_id;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trg_maintain_inventory_counts on user_inventory;
create trigger trg_maintain_inventory_counts
  after insert or update of status or delete
  on user_inventory
  for each row
  execute function maintain_inventory_counts();

-- Variant function using denormalized columns
drop function if exists find_nearby_traders_denormalized(double precision, double precision, int);
create function find_nearby_traders_denormalized(
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

revoke all on function find_nearby_traders_denormalized(double precision, double precision, int) from public;
revoke all on function find_nearby_traders_denormalized(double precision, double precision, int) from anon;
grant execute on function find_nearby_traders_denormalized(double precision, double precision, int) to authenticated;


-- ============================================================
-- VARIANT C: Materialized view
-- ============================================================
-- Strategy: Pre-compute per-user inventory stats in a materialized view.
-- Refreshed via trigger on user_inventory changes.

drop materialized view if exists trader_inventory_stats;
create materialized view trader_inventory_stats as
select
  ui.user_id,
  count(*) filter (where ui.status = 'DUPLICATE') as duplicate_count,
  count(*) filter (where ui.status = 'NEEDED')    as needed_count
from user_inventory ui
group by ui.user_id
having count(*) filter (where ui.status = 'DUPLICATE') > 0;

create unique index idx_trader_inventory_stats_user on trader_inventory_stats (user_id);

-- Trigger function to refresh matview on inventory changes.
-- Uses CONCURRENTLY to avoid locking reads during refresh.
create or replace function refresh_trader_inventory_stats()
returns trigger
language plpgsql
as $$
begin
  refresh materialized view concurrently trader_inventory_stats;
  return null;
end;
$$;

-- Fire once per statement (not per row) to batch refreshes
drop trigger if exists trg_refresh_trader_stats on user_inventory;
create trigger trg_refresh_trader_stats
  after insert or update of status or delete
  on user_inventory
  for each statement
  execute function refresh_trader_inventory_stats();

-- Variant function joining to matview
drop function if exists find_nearby_traders_matview(double precision, double precision, int);
create function find_nearby_traders_matview(
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
    inv.duplicate_count,
    inv.needed_count,
    ul.updated_at as location_updated_at
  from user_locations ul
  inner join user_profiles up on up.user_id = ul.user_id
  inner join trader_inventory_stats inv on inv.user_id = ul.user_id
  where
    ul.user_id <> auth.uid()
    and up.is_under_13 = false
    and st_dwithin(
      ul.location,
      st_setsrid(st_makepoint(lng, lat), 4326)::geography,
      radius_m
    )
  order by ul.location <-> st_setsrid(st_makepoint(lng, lat), 4326)::geography
  limit 50;
end;
$$;

revoke all on function find_nearby_traders_matview(double precision, double precision, int) from public;
revoke all on function find_nearby_traders_matview(double precision, double precision, int) from anon;
grant execute on function find_nearby_traders_matview(double precision, double precision, int) to authenticated;
