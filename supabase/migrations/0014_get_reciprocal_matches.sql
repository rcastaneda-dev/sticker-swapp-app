-- Reciprocal match discovery: given a list of nearby user IDs (from
-- find_nearby_traders()), return those who are true reciprocal matches —
-- they have DUPLICATE stickers the caller NEEDs AND the caller has
-- DUPLICATE stickers they NEED.
--
-- SECURITY DEFINER is required because user_inventory RLS restricts
-- SELECT to own rows only. This function must read other users'
-- inventories to compute set intersections.

create or replace function get_reciprocal_matches(
  p_nearby_ids uuid[]
)
returns table (
  user_id          uuid,
  they_have_i_need bigint,
  i_have_they_need bigint,
  match_score      bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid;
begin
  v_caller_id := auth.uid();

  -- Guard: caller must be authenticated
  if v_caller_id is null then
    raise exception 'Authentication required';
  end if;

  -- Guard: null or empty array → return empty result (not an error)
  if p_nearby_ids is null or array_length(p_nearby_ids, 1) is null then
    return;
  end if;

  -- Guard: clamp array to 50 entries (matches find_nearby_traders limit)
  if array_length(p_nearby_ids, 1) > 50 then
    p_nearby_ids := p_nearby_ids[1:50];
  end if;

  -- Guard: remove caller from array if accidentally included
  p_nearby_ids := array_remove(p_nearby_ids, v_caller_id);

  return query
  with
    -- Caller's stickers they NEED (what they're looking for)
    my_needed as (
      select ui.sticker_id
      from user_inventory ui
      where ui.user_id = v_caller_id
        and ui.status = 'NEEDED'
    ),
    -- Caller's stickers they have as DUPLICATE (what they can offer)
    my_duplicates as (
      select ui.sticker_id
      from user_inventory ui
      where ui.user_id = v_caller_id
        and ui.status = 'DUPLICATE'
    ),
    -- Direction A: for each nearby user, count their DUPLICATEs ∩ my NEEDs
    they_have as (
      select
        ui.user_id,
        count(*) as cnt
      from user_inventory ui
      inner join my_needed mn on mn.sticker_id = ui.sticker_id
      where ui.user_id = any(p_nearby_ids)
        and ui.status = 'DUPLICATE'
      group by ui.user_id
    ),
    -- Direction B: for each nearby user, count their NEEDs ∩ my DUPLICATEs
    they_need as (
      select
        ui.user_id,
        count(*) as cnt
      from user_inventory ui
      inner join my_duplicates md on md.sticker_id = ui.sticker_id
      where ui.user_id = any(p_nearby_ids)
        and ui.status = 'NEEDED'
      group by ui.user_id
    )
  -- Only return true reciprocal matches (both directions have >= 1)
  select
    th.user_id,
    th.cnt                         as they_have_i_need,
    tn.cnt                         as i_have_they_need,
    least(th.cnt, tn.cnt)          as match_score
  from they_have th
  inner join they_need tn on tn.user_id = th.user_id
  order by least(th.cnt, tn.cnt) desc, greatest(th.cnt, tn.cnt) desc;
end;
$$;

-- Only authenticated users may call this RPC
revoke all on function get_reciprocal_matches(uuid[]) from public;
revoke all on function get_reciprocal_matches(uuid[]) from anon;
grant execute on function get_reciprocal_matches(uuid[]) to authenticated;
