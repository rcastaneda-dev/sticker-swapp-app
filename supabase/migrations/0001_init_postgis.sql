create extension if not exists postgis;
create extension if not exists postgis_topology;

create table user_locations (
  user_id uuid primary key references auth.users(id),
  location geography(point, 4326),
  updated_at timestamptz default now(),
  accuracy_m int
);

-- Without this the proximity queries will be slow
create index idx_user_locations_geo
on user_locations
using gist(location);