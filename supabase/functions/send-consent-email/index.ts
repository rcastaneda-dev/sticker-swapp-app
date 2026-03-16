import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

function buildEmailHtml(
  confirmUrl: string,
  childDisplayName: string
): string {
  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8" /></head>
<body style="font-family: Inter, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px;">
  <div style="text-align: center; margin-bottom: 32px;">
    <h1 style="color: #0A1F44; font-family: Montserrat, sans-serif;">Sticker Swapp</h1>
  </div>
  <h2 style="color: #0A1F44;">Parental Consent Request</h2>
  <p>Hello,</p>
  <p><strong>${childDisplayName}</strong> has signed up for <strong>Sticker Swapp</strong>,
     a World Cup 2026 sticker collecting and trading app.</p>
  <p>Because they are under 13, we need your permission before they can use certain features
     (location-based discovery and chat with other traders).</p>
  <p>If you approve, please click the button below:</p>
  <div style="text-align: center; margin: 32px 0;">
    <a href="${confirmUrl}"
       style="background-color: #0A1F44; color: white; padding: 14px 32px;
              text-decoration: none; border-radius: 999px; font-weight: 600;
              font-family: Montserrat, sans-serif; display: inline-block;">
      Grant Consent
    </a>
  </div>
  <p style="color: #74777F; font-size: 14px;">
    This link expires in 7 days. If you did not expect this email, you can safely ignore it.
  </p>
  <hr style="border: none; border-top: 1px solid #C4C6D0; margin: 32px 0;" />
  <p style="color: #74777F; font-size: 12px;">
    Sticker Swapp &mdash; World Cup 2026 Sticker Trading
  </p>
</body>
</html>`;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify caller is authenticated
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();

  if (authError || !user) {
    return new Response(
      JSON.stringify({ error: "Invalid token" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const { parent_email, token, child_display_name } = await req.json();

  if (!parent_email || !token) {
    return new Response(
      JSON.stringify({ error: "parent_email and token are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const confirmUrl = `${SUPABASE_URL}/functions/v1/confirm-consent?token=${encodeURIComponent(token)}`;
  const displayName = child_display_name || "Your child";
  const emailHtml = buildEmailHtml(confirmUrl, displayName);

  if (RESEND_API_KEY) {
    // Production: send via Resend API
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Sticker Swapp <noreply@stickerswapp.com>",
        to: [parent_email],
        subject: "Parental Consent Required - Sticker Swapp",
        html: emailHtml,
      }),
    });

    if (!emailRes.ok) {
      const errBody = await emailRes.text();
      console.error("Resend API error:", errBody);
      return new Response(
        JSON.stringify({ error: "Failed to send email" }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }
  } else {
    // Local dev: log the confirmation URL for testing
    // Emails can be viewed in Inbucket at http://localhost:54324
    console.log(`[DEV] Consent email for: ${parent_email}`);
    console.log(`[DEV] Confirmation URL: ${confirmUrl}`);
    console.log(`[DEV] No RESEND_API_KEY set — email not actually sent.`);
    console.log(`[DEV] Use the confirmation URL above to test the flow.`);
  }

  return new Response(
    JSON.stringify({ success: true }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
