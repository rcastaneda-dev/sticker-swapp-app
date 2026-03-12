-- User inventory: tracks each user's sticker collection status

create type inventory_status as enum ('OWNED', 'NEEDED', 'DUPLICATE');

create table user_inventory (
  id          bigint generated always as identity primary key,
  user_id     uuid             not null references auth.users(id) on delete cascade,
  sticker_id  int              not null references stickers(id) on delete cascade,
  status      inventory_status not null default 'NEEDED',
  quantity    smallint         not null default 1
                               check (quantity >= 1),
  created_at  timestamptz      not null default now(),
  updated_at  timestamptz      not null default now(),

  unique (user_id, sticker_id)
);

create index idx_user_inventory_user   on user_inventory (user_id);
create index idx_user_inventory_status on user_inventory (user_id, status);

-- Auto-update updated_at on row change
create or replace function update_user_inventory_timestamp()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

create trigger trg_user_inventory_before_update
  before update on user_inventory
  for each row
  execute function update_user_inventory_timestamp();

-- RLS: users read/write own inventory only
alter table user_inventory enable row level security;

create policy "users_read_own_inventory"
  on user_inventory for select
  using (auth.uid() = user_id);

create policy "users_insert_own_inventory"
  on user_inventory for insert
  with check (auth.uid() = user_id);

create policy "users_update_own_inventory"
  on user_inventory for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users_delete_own_inventory"
  on user_inventory for delete
  using (auth.uid() = user_id);
