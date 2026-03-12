-- Enable RLS on user_locations (missed in 0001_init_postgis.sql)

alter table user_locations enable row level security;

-- SELECT: authenticated users can read all locations (needed for proximity discovery)
-- The Go matchmaking engine uses service_role (bypasses RLS), but this allows
-- direct Supabase queries from authenticated clients for nearby-user features.
create policy "authenticated_read_locations"
  on user_locations for select
  to authenticated
  using (true);

-- INSERT: users can only insert their own location
create policy "users_insert_own_location"
  on user_locations for insert
  to authenticated
  with check (auth.uid() = user_id);

-- UPDATE: users can only update their own location
create policy "users_update_own_location"
  on user_locations for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- DELETE: users can remove their own location (opt out / under-13 cleanup)
create policy "users_delete_own_location"
  on user_locations for delete
  to authenticated
  using (auth.uid() = user_id);

-- ============================================================
-- AUDIT: verify ALL public tables have RLS enabled
-- This will raise an exception if any table is unprotected.
-- ============================================================
do $$
declare
  unprotected text;
begin
  select string_agg(tablename, ', ')
  into unprotected
  from pg_tables
  where schemaname = 'public'
    and tablename not like 'pg_%'
    and tablename not in ('spatial_ref_sys', 'geometry_columns', 'geography_columns',
                          'raster_columns', 'raster_overviews',
                          'topology', 'layer')  -- PostGIS system tables
    and tablename not in (
      select relname::text
      from pg_class
      where relrowsecurity = true
        and relnamespace = 'public'::regnamespace
    );

  if unprotected is not null then
    raise exception 'RLS AUDIT FAILED — tables without RLS: %', unprotected;
  end if;

  raise notice 'RLS AUDIT PASSED — all public tables have RLS enabled';
end $$;
