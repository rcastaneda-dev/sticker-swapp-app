import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function renderHtml(
  title: string,
  message: string,
  isSuccess: boolean
): string {
  const color = isSuccess ? "#2E7D32" : "#BA1A1A";
  const icon = isSuccess ? "&#10003;" : "&#10007;";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title} - Sticker Swapp</title>
  <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700&family=Inter:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Inter', Arial, sans-serif;
      background: #F8F9FF;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: white;
      border-radius: 16px;
      padding: 48px 32px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 3px 12px rgba(0,0,0,0.08);
    }
    .brand {
      font-family: 'Montserrat', sans-serif;
      color: #0A1F44;
      font-size: 28px;
      font-weight: 700;
      margin-bottom: 32px;
    }
    .icon {
      width: 64px;
      height: 64px;
      border-radius: 50%;
      background: ${color}15;
      color: ${color};
      font-size: 32px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 24px;
    }
    h1 {
      font-family: 'Montserrat', sans-serif;
      color: #0A1F44;
      font-size: 24px;
      margin-bottom: 12px;
    }
    p {
      color: #74777F;
      line-height: 1.6;
      font-size: 16px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">Sticker Swapp</div>
    <div class="icon">${icon}</div>
    <h1>${title}</h1>
    <p>${message}</p>
  </div>
</body>
</html>`;
}

serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = new URL(req.url);
  const token = url.searchParams.get("token");

  if (!token) {
    return new Response(
      renderHtml(
        "Invalid Link",
        "This consent link is invalid. Please ask your child to resend the consent request from the Sticker Swapp app.",
        false
      ),
      { status: 400, headers: { "Content-Type": "text/html; charset=utf-8" } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data, error } = await supabase.rpc("confirm_parental_consent", {
    p_token: token,
  });

  if (error) {
    console.error("confirm_parental_consent RPC error:", error);
    return new Response(
      renderHtml(
        "Something Went Wrong",
        "We encountered an error processing your consent. Please try again later or contact support.",
        false
      ),
      { status: 500, headers: { "Content-Type": "text/html; charset=utf-8" } }
    );
  }

  const result = data as { success: boolean; error?: string };

  if (!result.success) {
    const messages: Record<string, { title: string; message: string }> = {
      invalid_token: {
        title: "Invalid Link",
        message:
          "This consent link is not valid. Please ask your child to resend the consent request from the Sticker Swapp app.",
      },
      already_used: {
        title: "Already Confirmed",
        message:
          "This consent has already been confirmed. Your child can now use Sticker Swapp. You can close this page.",
      },
      expired: {
        title: "Link Expired",
        message:
          "This consent link has expired (links are valid for 7 days). Please ask your child to resend the consent request from the Sticker Swapp app.",
      },
    };

    const msg = messages[result.error || ""] || {
      title: "Error",
      message: "An unexpected error occurred.",
    };

    const isAlreadyUsed = result.error === "already_used";
    return new Response(
      renderHtml(msg.title, msg.message, isAlreadyUsed),
      {
        status: isAlreadyUsed ? 200 : 400,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      }
    );
  }

  return new Response(
    renderHtml(
      "Consent Granted!",
      "Thank you! Your child can now use all features of Sticker Swapp. You can close this page.",
      true
    ),
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
});
