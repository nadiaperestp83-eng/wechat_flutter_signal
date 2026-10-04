import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEGREDO = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const CONTA = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function base64Url(dados: Uint8Array | string): string {
  const bytes = typeof dados === "string"
    ? new TextEncoder().encode(dados)
    : dados;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemParaBytes(pem: string): Uint8Array {
  const limpo = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const bin = atob(limpo);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

let cache: { token: string; expiraEm: number } | null = null;

// Troca a conta de serviço por um token de acesso do Google (OAuth2, JWT RS256).
async function tokenGoogle(): Promise<string> {
  const agora = Math.floor(Date.now() / 1000);
  if (cache && cache.expiraEm - 60 > agora) return cache.token;

  const cabecalho = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const corpo = base64Url(JSON.stringify({
    iss: CONTA.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: agora,
    exp: agora + 3600,
  }));

  const chave = await crypto.subtle.importKey(
    "pkcs8",
    pemParaBytes(CONTA.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const assinatura = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      chave,
      new TextEncoder().encode(`${cabecalho}.${corpo}`),
    ),
  );
  const jwt = `${cabecalho}.${corpo}.${base64Url(assinatura)}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) throw new Error(`OAuth Google falhou: ${await resp.text()}`);

  const dados = await resp.json();
  cache = { token: dados.access_token, expiraEm: agora + (dados.expires_in ?? 3600) };
  return cache.token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("método não permitido", { status: 405 });
  }
  if (!SEGREDO || req.headers.get("x-webhook-secret") !== SEGREDO) {
    return new Response("não autorizado", { status: 401 });
  }

  let destinatario: string | undefined;
  try {
    destinatario = (await req.json()).recipient_id;
  } catch {
    return new Response("json inválido", { status: 400 });
  }
  if (!destinatario) return new Response("sem recipient_id", { status: 400 });

  const { data: linhas, error } = await supabase
    .from("signal_push_tokens")
    .select("token")
    .eq("user_id", destinatario);
  if (error) return new Response(error.message, { status: 500 });
  if (!linhas || linhas.length === 0) {
    return new Response("sem tokens", { status: 200 });
  }

  const acesso = await tokenGoogle();
  let enviados = 0;

  await Promise.all(linhas.map(async ({ token }) => {
    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${CONTA.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${acesso}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            // Genérico de propósito: sem remetente e sem texto.
            notification: { title: "WeChat", body: "Nova mensagem" },
            android: {
              priority: "HIGH",
              notification: { channel_id: "mensagens", tag: "nova_mensagem" },
            },
          },
        }),
      },
    );

    if (resp.ok) {
      enviados++;
      return;
    }
    const texto = await resp.text();
    // Token inválido/desinstalado: limpa da tabela.
    if (resp.status === 404 || texto.includes("UNREGISTERED")) {
      await supabase.from("signal_push_tokens").delete().eq("token", token);
    } else {
      console.error("FCM falhou:", resp.status, texto);
    }
  }));

  return new Response(JSON.stringify({ enviados }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
