import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { RtcRole, RtcTokenBuilder } from "npm:agora-token@2.0.5";

// Gera o token do Agora para UMA chamada. Nada é gravado: a função só assina
// o token (a App Certificate fica aqui, nunca no app).
const APP_ID = Deno.env.get("AGORA_APP_ID") ?? "";
const CERTIFICADO = Deno.env.get("AGORA_APP_CERTIFICATE") ?? "";
const VALIDADE_SEGUNDOS = 2 * 60 * 60; // o app renova antes de vencer

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "método não permitido" }, 405);
  if (!APP_ID || !CERTIFICADO) return json({ erro: "Agora não configurado" }, 500);

  // Só usuário logado pede token.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data } = await supabase.auth.getUser();
  if (!data?.user) return json({ erro: "não autorizado" }, 401);

  let canal = "";
  let uid = 0;
  try {
    const corpo = await req.json();
