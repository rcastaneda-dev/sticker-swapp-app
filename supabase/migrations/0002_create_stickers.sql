-- Sticker catalog table for the 980-sticker World Cup 2026 album

create type sticker_type as enum ('player', 'stadium', 'legend');

create table stickers (
  id            serial        primary key,
  sticker_number smallint     not null unique
                              check (sticker_number between 1 and 980),
  title         text          not null,
  team          text,         -- null for host-venue / special stickers
  page          smallint      not null
                              check (page between 1 and 112),
  type          sticker_type  not null,
  image_url     text,         -- CDN URL, populated later
  created_at    timestamptz   not null default now()
);

create index idx_stickers_team on stickers (team);
create index idx_stickers_page on stickers (page);
create index idx_stickers_type on stickers (type);

-- RLS: public read, no anonymous writes
alter table stickers enable row level security;

create policy "stickers_public_read"
  on stickers for select
  using (true);
