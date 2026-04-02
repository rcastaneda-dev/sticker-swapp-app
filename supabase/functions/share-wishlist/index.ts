import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface WishlistSticker {
  sticker_number: number;
  title: string;
  team: string | null;
  type: string;
  image_url: string | null;
}

function renderErrorHtml(title: string, message: string): string {
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
      background: #BA1A1A15;
      color: #BA1A1A;
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
    <div class="icon">&#10007;</div>
    <h1>${title}</h1>
    <p>${message}</p>
  </div>
</body>
</html>`;
}

function renderWishlistHtml(
  displayName: string,
  stickerCount: number,
  stickers: WishlistSticker[]
): string {
  // Group stickers by team
  const grouped = new Map<string, WishlistSticker[]>();
  for (const s of stickers) {
    const team = s.team ?? "Special";
    if (!grouped.has(team)) grouped.set(team, []);
    grouped.get(team)!.push(s);
  }

  // Sort teams alphabetically, "Special" last
  const sortedTeams = [...grouped.keys()].sort((a, b) => {
    if (a === "Special") return 1;
    if (b === "Special") return -1;
    return a.localeCompare(b);
  });

  const teamSections = sortedTeams
    .map((team) => {
      const teamStickers = grouped.get(team)!;
      const stickerItems = teamStickers
        .map(
          (s) =>
            `<div class="sticker">
              <span class="sticker-num">#${s.sticker_number}</span>
              <span class="sticker-title">${s.title}</span>
            </div>`
        )
        .join("\n");
      return `
      <div class="team-section">
        <h3 class="team-name">${team} <span class="team-count">(${teamStickers.length})</span></h3>
        <div class="sticker-grid">
          ${stickerItems}
        </div>
      </div>`;
    })
    .join("\n");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${displayName}'s Wishlist - Sticker Swapp</title>
  <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700&family=Inter:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Inter', Arial, sans-serif;
      background: #F8F9FF;
      min-height: 100vh;
      padding: 24px;
    }
    .container {
      max-width: 720px;
      margin: 0 auto;
    }
    .header {
      background: white;
      border-radius: 16px;
      padding: 32px 24px;
      text-align: center;
      box-shadow: 0 3px 12px rgba(0,0,0,0.08);
      margin-bottom: 24px;
    }
    .brand {
      font-family: 'Montserrat', sans-serif;
      color: #0A1F44;
      font-size: 28px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .subtitle {
      color: #74777F;
      font-size: 16px;
      margin-bottom: 16px;
    }
    .count-badge {
      display: inline-block;
      background: #C89B3C20;
      color: #C89B3C;
      font-weight: 600;
      padding: 8px 20px;
      border-radius: 999px;
      font-size: 18px;
    }
    .team-section {
      background: white;
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 16px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.06);
    }
    .team-name {
      font-family: 'Montserrat', sans-serif;
      color: #0A1F44;
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 12px;
      padding-bottom: 8px;
      border-bottom: 2px solid #F0F0F5;
    }
    .team-count {
      color: #74777F;
      font-size: 14px;
      font-weight: 400;
    }
    .sticker-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
      gap: 8px;
    }
    .sticker {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      background: #F8F9FF;
      border-radius: 8px;
      font-size: 14px;
    }
    .sticker-num {
      font-weight: 600;
      color: #0A1F44;
      min-width: 40px;
    }
    .sticker-title {
      color: #44474E;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .footer {
      text-align: center;
      color: #74777F;
      font-size: 14px;
      margin-top: 24px;
      padding: 16px;
    }
    .footer a {
      color: #2E7D32;
      text-decoration: none;
      font-weight: 500;
    }
    @media (max-width: 480px) {
      .sticker-grid {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="brand">Sticker Swapp</div>
      <div class="subtitle">${displayName}'s Wishlist</div>
      <div class="count-badge">${stickerCount} stickers needed</div>
    </div>
    ${teamSections}
    <div class="footer">
      Help them complete their World Cup 2026 album!
    </div>
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
      renderErrorHtml(
        "Invalid Link",
        "This wishlist link is not valid. Please ask the collector to share a new link from the Sticker Swapp app."
      ),
      { status: 400, headers: { "Content-Type": "text/html; charset=utf-8" } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data, error } = await supabase.rpc("get_shared_wishlist", {
    p_token: token,
  });

  if (error) {
    console.error("get_shared_wishlist RPC error:", error);
    return new Response(
      renderErrorHtml(
        "Something Went Wrong",
        "We encountered an error loading this wishlist. Please try again later."
      ),
      { status: 500, headers: { "Content-Type": "text/html; charset=utf-8" } }
    );
  }

  const result = data as {
    success: boolean;
    error?: string;
    display_name?: string;
    sticker_count?: number;
    stickers?: WishlistSticker[];
  };

  if (!result.success) {
    const messages: Record<string, { title: string; message: string }> = {
      invalid_token: {
        title: "Invalid Link",
        message:
          "This wishlist link is not valid. Please ask the collector to share a new link from the Sticker Swapp app.",
      },
      expired: {
        title: "Link Expired",
        message:
          "This wishlist link has expired. Please ask the collector to share a new link from the Sticker Swapp app.",
      },
    };

    const msg = messages[result.error || ""] || {
      title: "Error",
      message: "An unexpected error occurred.",
    };

    return new Response(renderErrorHtml(msg.title, msg.message), {
      status: 400,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }

  return new Response(
    renderWishlistHtml(
      result.display_name || "Collector",
      result.sticker_count || 0,
      result.stickers || []
    ),
    { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
});
