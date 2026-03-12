-- Trade audit log: immutable, append-only trade history
-- No direct INSERT/UPDATE/DELETE; writes only via record_trade() function

create type trade_status as enum ('COMPLETED', 'CANCELLED', 'EXPIRED');

create table trade_audit_log (
  id                   bigint generated always as identity primary key,
  trade_id             uuid             not null default gen_random_uuid() unique,
  initiator_id         uuid             not null references auth.users(id),
  responder_id         uuid             not null references auth.users(id),
  initiator_sticker_ids int[]           not null check (array_length(initiator_sticker_ids, 1) >= 1),
  responder_sticker_ids int[]           not null check (array_length(responder_sticker_ids, 1) >= 1),
  status               trade_status     not null,
  idempotency_key      uuid             not null unique,
  created_at           timestamptz      not null default now(),

  check (initiator_id <> responder_id)
);

create index idx_trade_audit_initiator on trade_audit_log (initiator_id);
create index idx_trade_audit_responder on trade_audit_log (responder_id);
create index idx_trade_audit_created   on trade_audit_log (created_at);

-- RLS: read-only for participants, no direct writes
alter table trade_audit_log enable row level security;

create policy "users_read_own_trades"
  on trade_audit_log for select
  using (auth.uid() in (initiator_id, responder_id));

-- No INSERT/UPDATE/DELETE policies — direct writes are blocked by RLS

-- Stored procedure: the only way to write to trade_audit_log
-- SECURITY DEFINER runs as the function owner (bypasses RLS)
create or replace function record_trade(
  p_initiator_id         uuid,
  p_responder_id         uuid,
  p_initiator_sticker_ids int[],
  p_responder_sticker_ids int[],
  p_status               trade_status,
  p_idempotency_key      uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trade_id uuid;
begin
  insert into trade_audit_log (
    initiator_id,
    responder_id,
    initiator_sticker_ids,
    responder_sticker_ids,
    status,
    idempotency_key
  )
  values (
    p_initiator_id,
    p_responder_id,
    p_initiator_sticker_ids,
    p_responder_sticker_ids,
    p_status,
    p_idempotency_key
  )
  on conflict (idempotency_key) do nothing
  returning trade_id into v_trade_id;

  return v_trade_id;
end;
$$;

-- Revoke direct execute from public; only the Go service role should call this
revoke execute on function record_trade from public;
revoke execute on function record_trade from anon;
revoke execute on function record_trade from authenticated;
grant execute on function record_trade to service_role;
