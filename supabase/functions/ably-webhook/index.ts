import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ABLY_API_KEY = Deno.env.get("ABLY_API_KEY")!;

// Extract the key secret (portion after ':') for HMAC verification
const ABLY_KEY_SECRET = ABLY_API_KEY.split(":")[1];

// Channel pattern: "match:{uuid}"
const MATCH_CHANNEL_REGEX =
  /^match:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$/;

// UUID validation for clientId (sender)
const UUID_REGEX =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

// Event names to persist (filter out system events like match.created)
const PERSISTABLE_EVENTS = new Set(["chat.message"]);

// Must match DB CHECK constraint
const MAX_CONTENT_LENGTH = 4000;

interface AblyMessage {
  id: string;
  name: string;
  data: string;
  clientId?: string;
  timestamp: number;
  encoding?: string;
}

interface AblyWebhookEnvelope {
  source: string;
  appId: string;
  channel: string;
  site: string;
  ruleId: string;
  messages: AblyMessage[];
}

async function verifyAblySignature(
  body: string,
  signature: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(ABLY_KEY_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const computed = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Constant-time comparison
  if (computed.length !== signature.length) return false;
  let result = 0;
  for (let i = 0; i < computed.length; i++) {
    result |= computed.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return result === 0;
}

function extractContent(data: string): string {
  // Chat messages are expected as JSON {text: "..."} but handle other formats.
  try {
    const parsed = JSON.parse(data);
    if (typeof parsed === "string") return parsed;
    if (typeof parsed.text === "string") return parsed.text;
    return JSON.stringify(parsed);
  } catch {
    // Not JSON — treat as plain text
    return data;
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Read raw body for signature verification
  const rawBody = await req.text();

  // Verify HMAC signature from Ably
  const signature = req.headers.get("X-Ably-Signature");
  if (!signature) {
    console.error("Missing X-Ably-Signature header");
    return new Response(JSON.stringify({ error: "Missing signature" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const isValid = await verifyAblySignature(rawBody, signature);
  if (!isValid) {
    console.error("Invalid Ably webhook signature");
    return new Response(JSON.stringify({ error: "Invalid signature" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Parse payload (Ably may send single envelope or array)
  let envelopes: AblyWebhookEnvelope[];
  try {
    const parsed = JSON.parse(rawBody);
    envelopes = Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    console.error("Invalid JSON payload");
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Process each envelope
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  let processed = 0;
  let skipped = 0;
  let duplicates = 0;
  let errors = 0;

  for (const envelope of envelopes) {
    // Only process channel.message source
    if (envelope.source !== "channel.message") {
      skipped++;
      continue;
    }

    // Extract match_id from channel name
    const channelMatch = MATCH_CHANNEL_REGEX.exec(envelope.channel);
    if (!channelMatch) {
      skipped++;
      continue;
    }
    const matchId = channelMatch[1];

    for (const msg of envelope.messages) {
      // Filter: only persist user chat messages
      if (!PERSISTABLE_EVENTS.has(msg.name)) {
        skipped++;
        continue;
      }

      // Validate clientId (sender) is a UUID
      if (!msg.clientId || !UUID_REGEX.test(msg.clientId)) {
        console.warn(`Skipping message with invalid clientId: ${msg.clientId}`);
        skipped++;
        continue;
      }

      // Extract text content
      const content = extractContent(msg.data || "");
      if (!content || content.length === 0) {
        console.warn(`Skipping empty message: ${msg.id}`);
        skipped++;
        continue;
      }

      // Truncate to max length if needed
      const truncatedContent = content.slice(0, MAX_CONTENT_LENGTH);

      // Convert Ably timestamp (ms) to ISO string
      const ablyTimestamp = new Date(msg.timestamp).toISOString();

      // Insert via SECURITY DEFINER RPC
      const { data, error } = await supabase.rpc("insert_message", {
        p_ably_message_id: msg.id,
        p_match_id: matchId,
        p_sender_id: msg.clientId,
        p_content: truncatedContent,
        p_event_name: msg.name,
        p_ably_timestamp: ablyTimestamp,
      });

      if (error) {
        console.error(`insert_message RPC error for ${msg.id}:`, error);
        errors++;
        continue;
      }

      const result = data as {
        success: boolean;
        duplicate?: boolean;
        error?: string;
      };
      if (!result.success) {
        console.error(`insert_message failed for ${msg.id}: ${result.error}`);
        errors++;
        continue;
      }

      if (result.duplicate) {
        duplicates++;
      } else {
        processed++;
      }
    }
  }

  // Always return 200 to Ably to prevent retries for partial failures.
  // Idempotency handles legitimate retries; persistent errors should be
  // caught via monitoring/logging.
  return new Response(
    JSON.stringify({ processed, skipped, duplicates, errors }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
