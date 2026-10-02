import { Webhook } from 'https://esm.sh/standardwebhooks@1.0.0';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const HOOK_SECRET = Deno.env.get('SEND_SMS_HOOK_SECRET') ?? '';
const SMSDEV_API_KEY = Deno.env.get('SMSDEV_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const LIMITE_HORAS = 24;

Deno.serve(async (req: Request) => {
  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);

  const wh = new Webhook(HOOK_SECRET);
  let dados: any;
  try {
    dados = wh.verify(payload, headers);
  } catch (erro) {
    return new Response(
      JSON.stringify({ error: { http_code: 401, message: 'Assinatura inválida' } }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const telefone: string = dados.user?.phone;
  const otp: string = dados.sms?.otp;

  if (!telefone || !otp) {
    return new Response(
      JSON.stringify({ error: { http_code: 400, message: 'Payload incompleto' } }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: registroAnterior } = await supabaseAdmin
    .from('sms_rate_limit')
    .select('last_sent_at')
    .eq('phone', telefone)
    .maybeSingle();

  if (registroAnterior) {
    const ultimoEnvio = new Date(registroAnterior.last_sent_at).getTime();
    const horasPassadas = (Date.now() - ultimoEnvio) / (1000 * 60 * 60);

    if (horasPassadas < LIMITE_HORAS) {
      const horasRestantes = Math.ceil(LIMITE_HORAS - horasPassadas);
      return new Response(
        JSON.stringify({
          error: {
            http_code: 429,
            message: `Limite de SMS atingido. Tente de novo em ${horasRestantes}h.`,
          },
        }),
        { status: 429, headers: { 'Content-Type': 'application/json' } },
      );
    }
  }

  const numeroLimpo = telefone.replace(/[^0-9]/g, '');
  const mensagem = `Seu codigo de verificacao e: ${otp}`;

  const urlSmsdev = new URL('https://api.smsdev.com.br/v1/send');
  urlSmsdev.searchParams.set('key', SMSDEV_API_KEY);
  urlSmsdev.searchParams.set('type', '9');
  urlSmsdev.searchParams.set('number', numeroLimpo);
  urlSmsdev.searchParams.set('msg', mensagem);

  const respostaSmsdev = await fetch(urlSmsdev.toString());
  const resultadoSmsdev = await respostaSmsdev.json();

  if (resultadoSmsdev.situacao !== 'OK') {
    return new Response(
      JSON.stringify({
        error: {
          http_code: 500,
          message: `SMSdev recusou o envio: ${JSON.stringify(resultadoSmsdev)}`,
        },
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  await supabaseAdmin
    .from('sms_rate_limit')
    .upsert({ phone: telefone, last_sent_at: new Date().toISOString() });

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
