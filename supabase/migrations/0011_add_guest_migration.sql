-- Guest-to-member inventory migration: tracking table + SECURITY DEFINER RPC.
-- When a guest user signs up, their locally-stored sticker inventory is migrated
-- to the cloud via this RPC. Idempotent: duplicate (device_uuid, user_id) calls
-- return the previous result without re-processing.

-- 1. Tracking table — records completed migrations for idempotency
create table guest_migrations (
  id           bigint generated always as identity primary key,
  device_uuid  text        not null,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  items_sent   int         not null,
  items_written int        not null,
  created_at   timestamptz not null default now(),

  unique (device_uuid, user_id)
);

create index idx_guest_migrations_user   on guest_migrations (user_id);
create index idx_guest_migrations_device on guest_migrations (device_uuid);

-- RLS: no direct client writes. All mutations via SECURITY DEFINER RPC.
alter table guest_migrations enable row level security;

create policy "users_read_own_migrations"
  on guest_migrations for select
  to authenticated
  using (auth.uid() = user_id);

-- 2. RPC: migrate_guest_inventory
--    Called by the migrate-guest-inventory Edge Function after auth + validation.
--    Receives a device UUID and a JSONB array of inventory items.
--    Upserts into user_inventory with conflict resolution:
--      Status priority: DUPLICATE > OWNED > NEEDED (higher wins)
--      Quantity: GREATEST(incoming, existing)
--    Records migration in guest_migrations for idempotency.
create or replace function migrate_guest_inventory(
  p_device_uuid text,
  p_items       jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid;
  v_items_count  int;
  v_written      int;
  v_existing     record;
begin
  v_user_id := auth.uid();

  -- Guard: device_uuid required
  if p_device_uuid is null or length(trim(p_device_uuid)) = 0 then
    return json_build_object('success', false, 'error', 'device_uuid_required');
  end if;

  -- Guard: items must be a non-empty array, max 980
  if p_items is null or jsonb_array_length(p_items) = 0 then
    return json_build_object('success', false, 'error', 'empty_items');
  end if;

  v_items_count := jsonb_array_length(p_items);

  if v_items_count > 980 then
    return json_build_object('success', false, 'error', 'too_many_items');
  end if;

  -- Idempotency: check if this device already migrated to this user
  select * into v_existing
  from guest_migrations
  where device_uuid = p_device_uuid
    and user_id = v_user_id;

  if v_existing is not null then
    return json_build_object(
      'success',          true,
      'items_sent',       v_existing.items_sent,
      'items_written',    v_existing.items_written,
      'already_migrated', true
    );
  end if;

  -- Set-based upsert: JOIN to stickers validates IDs exist, skips invalid ones.
  -- Status priority via numeric rank: DUPLICATE(3) > OWNED(2) > NEEDED(1).
  with incoming as (
    select
      (item->>'sticker_id')::int              as sticker_id,
      (item->>'status')::inventory_status     as status,
      greatest(1, (item->>'quantity')::smallint) as quantity
    from jsonb_array_elements(p_items) as item
  )
  insert into user_inventory (user_id, sticker_id, status, quantity)
  select v_user_id, i.sticker_id, i.status, i.quantity
  from incoming i
  join stickers s on s.id = i.sticker_id
  on conflict (user_id, sticker_id) do update
  set status = case
        when (case excluded.status
                when 'DUPLICATE' then 3 when 'OWNED' then 2 else 1
              end)
           > (case user_inventory.status
                when 'DUPLICATE' then 3 when 'OWNED' then 2 else 1
              end)
        then excluded.status
        else user_inventory.status
      end,
      quantity = greatest(excluded.quantity, user_inventory.quantity);

  get diagnostics v_written = row_count;

  -- Record migration for idempotency tracking
  insert into guest_migrations (device_uuid, user_id, items_sent, items_written)
  values (p_device_uuid, v_user_id, v_items_count, v_written);

  return json_build_object(
    'success',          true,
    'items_sent',       v_items_count,
    'items_written',    v_written,
    'already_migrated', false
  );
end;
$$;

revoke execute on function migrate_guest_inventory from public;
revoke execute on function migrate_guest_inventory from anon;
grant execute on function migrate_guest_inventory to authenticated;
grant execute on function migrate_guest_inventory to service_role;
