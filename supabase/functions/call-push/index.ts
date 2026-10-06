import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Acorda o aparelho de quem está sendo chamado (app fechado) com um push FCM
// só de dados. O servidor NÃO guarda nada e NÃO lê nada: o campo "c" é o
// convite já cifrado na sessão Signal (opaco aqui).
const CONTA = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64Url(dados: Uint8Array | string): string {
  const bytes = typeof dados === "string" ? new TextEncoder().encode(dados) : dados;
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
