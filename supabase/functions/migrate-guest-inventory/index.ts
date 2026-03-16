import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const VALID_STATUSES = new Set(["OWNED", "NEEDED", "DUPLICATE"]);
const MAX_ITEMS = 980;
const MAX_QUANTITY = 9999;

interface InventoryItem {
  sticker_id: number;
  status: string;
  quantity: number;
}

interface MigrateRequest {
  device_uuid: string;
  items: InventoryItem[];
}

function validateRequest(body: unknown): {
  valid: boolean;
  error?: string;
  data?: MigrateRequest;
} {
  const req = body as MigrateRequest;

  if (
    !req.device_uuid ||
    typeof req.device_uuid !== "string" ||
    req.device_uuid.trim().length === 0
  ) {
    return {
      valid: false,
      error: "device_uuid is required and must be a non-empty string",
    };
  }
  if (req.device_uuid.length > 255) {
    return {
      valid: false,
      error: "device_uuid must be 255 characters or fewer",
    };
  }

  if (!Array.isArray(req.items)) {
    return { valid: false, error: "items must be an array" };
  }
  if (req.items.length === 0) {
    return { valid: false, error: "items array must not be empty" };
  }
  if (req.items.length > MAX_ITEMS) {
    return {
      valid: false,
      error: `items array must not exceed ${MAX_ITEMS} entries`,
    };
  }

  const seen = new Set<number>();
  for (let i = 0; i < req.items.length; i++) {
    const item = req.items[i];

    if (
      typeof item.sticker_id !== "number" ||
      !Number.isInteger(item.sticker_id) ||
      item.sticker_id < 1 ||
      item.sticker_id > 980
    ) {
      return {
        valid: false,
        error: `items[${i}].sticker_id must be an integer between 1 and 980`,
      };
    }

    if (!VALID_STATUSES.has(item.status)) {
      return {
        valid: false,
        error: `items[${i}].status must be one of: OWNED, NEEDED, DUPLICATE`,
      };
    }

    if (
      typeof item.quantity !== "number" ||
      !Number.isInteger(item.quantity) ||
      item.quantity < 1 ||
      item.quantity > MAX_QUANTITY
    ) {
      return {
        valid: false,
        error: `items[${i}].quantity must be an integer between 1 and ${MAX_QUANTITY}`,
      };
    }

    if (seen.has(item.sticker_id)) {
      return {
        valid: false,
        error: `Duplicate sticker_id ${item.sticker_id} at items[${i}]`,
      };
    }
    seen.add(item.sticker_id);
  }

  return { valid: true, data: req };
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Auth check (same pattern as send-consent-email)
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Parse and validate request body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const validation = validateRequest(body);
  if (!validation.valid) {
    return new Response(JSON.stringify({ error: validation.error }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { device_uuid, items } = validation.data!;

  // Delegate to SECURITY DEFINER RPC (runs as the authenticated user)
  const { data, error } = await userClient.rpc("migrate_guest_inventory", {
    p_device_uuid: device_uuid,
    p_items: items,
  });

  if (error) {
    console.error("migrate_guest_inventory RPC error:", error);
    return new Response(JSON.stringify({ error: "Migration failed" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const result = data as {
    success: boolean;
    error?: string;
    items_sent?: number;
    items_written?: number;
    already_migrated?: boolean;
  };

  if (!result.success) {
    return new Response(JSON.stringify({ error: result.error }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({
      success: true,
      items_sent: result.items_sent,
      items_written: result.items_written,
      already_migrated: result.already_migrated,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
