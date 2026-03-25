# RLS Policy Reference — Sticker Swapp

All public tables **must** have Row Level Security (RLS) enabled. Migration `0007` includes a runtime audit that raises an exception if any public table lacks RLS.

## Policy Matrix

### `user_locations`
| Operation | Policy Name | Rule | Role |
|-----------|-------------|------|------|
| SELECT | — | Blocked by RLS (no policy). Reads via `find_nearby_users()` RPC only | — |
| INSERT | `users_insert_own_location` | `auth.uid() = user_id` | `authenticated` |
| UPDATE | `users_update_own_location` | `auth.uid() = user_id` | `authenticated` |
| DELETE | `users_delete_own_location` | `auth.uid() = user_id` | `authenticated` |

**Notes:** Direct SELECT is blocked. All reads go through SECURITY DEFINER RPCs which bypass RLS:
- `find_nearby_users(lat, lon, radius_m, max_results)` (migration `0012`) — returns nearby users within radius. 50 km max, 100-result cap, excludes under-13 and caller.
- `find_nearby_traders(lat, lng, radius_m)` (migration `0013`) — returns nearby users who have at least one DUPLICATE sticker. 50 km max, 50-result cap, excludes under-13 and caller. Uses `<->` KNN operator for index-accelerated nearest-neighbour ordering. Returns `user_id`, `distance_m`, `display_name`, `duplicate_count`, `needed_count`.

The Go matchmaking engine queries via `service_role` which bypasses RLS.

### `stickers`
| Operation | Policy Name | Rule | Role |
|-----------|-------------|------|------|
| SELECT | `stickers_public_read` | `true` (public catalog) | all |
| INSERT | — | Blocked by RLS (no policy) | — |
| UPDATE | — | Blocked by RLS (no policy) | — |
| DELETE | — | Blocked by RLS (no policy) | — |

**Notes:** Read-only catalog. Sticker data is seeded via migration (`0003`). No client writes permitted.

### `user_profiles`
| Operation | Policy Name | Rule | Role |
|-----------|-------------|------|------|
| SELECT | `users_read_own_profile` | `auth.uid() = user_id` | all |
| INSERT | `users_insert_own_profile` | `auth.uid() = user_id` | all |
| UPDATE | `users_update_own_profile` | `auth.uid() = user_id` | all |
| DELETE | — | Blocked by RLS (no policy) | — |

**Notes:** `is_under_13` is immutable once set to `true` (enforced by trigger `trg_user_profiles_before_update`). Profiles cannot be deleted via RLS; account deletion is handled by Supabase Auth cascade.

### `user_inventory`
| Operation | Policy Name | Rule | Role |
|-----------|-------------|------|------|
| SELECT | `users_read_own_inventory` | `auth.uid() = user_id` | all |
| INSERT | `users_insert_own_inventory` | `auth.uid() = user_id` | all |
| UPDATE | `users_update_own_inventory` | `auth.uid() = user_id` | all |
| DELETE | `users_delete_own_inventory` | `auth.uid() = user_id` | all |

**Notes:** Full own-row CRUD. Unique constraint on `(user_id, sticker_id)` prevents duplicate entries. Cross-user inventory reads are performed exclusively through SECURITY DEFINER RPCs which bypass RLS:
- `find_nearby_traders(lat, lng, radius_m)` (migration `0013`) — aggregates DUPLICATE/NEEDED counts per nearby user.
- `get_reciprocal_matches(p_nearby_ids)` (migration `0014`) — given up to 50 nearby user IDs, computes reciprocal match scores by intersecting their DUPLICATE stickers with the caller's NEEDED stickers, and vice versa. Returns `user_id`, `they_have_i_need`, `i_have_they_need`, `match_score`. Authenticated only.

### `trade_audit_log`
| Operation | Policy Name | Rule | Role |
|-----------|-------------|------|------|
| SELECT | `users_read_own_trades` | `auth.uid() IN (initiator_id, responder_id)` | all |
| INSERT | — | Blocked by RLS (no policy) | — |
| UPDATE | — | Blocked by RLS (no policy) | — |
| DELETE | — | Blocked by RLS (no policy) | — |

**Notes:** Append-only. Writes are exclusively through the `record_trade()` SECURITY DEFINER function, which is only granted to `service_role`. Direct INSERT/UPDATE/DELETE are blocked for all client roles.

## Audit Mechanism

Migration `0007_enable_rls_user_locations.sql` includes a `DO` block that queries `pg_class.relrowsecurity` for all public tables (excluding PostGIS system tables). If any table lacks RLS, the migration **fails** with:

```
RLS AUDIT FAILED — tables without RLS: <table_list>
```

This audit runs on every `supabase db reset` (`make migrate`) and on any fresh deployment, providing a safety net against future tables being added without RLS.

## Adding New Tables

When creating a new table:

1. Always include `ALTER TABLE <name> ENABLE ROW LEVEL SECURITY;` in the migration
2. Define explicit policies for each operation (SELECT/INSERT/UPDATE/DELETE)
3. If a table should only be written by the backend, use a SECURITY DEFINER function with `service_role` grants
4. Update this document with the new table's policy matrix
5. The audit in migration `0007` will catch any omission at deploy time
