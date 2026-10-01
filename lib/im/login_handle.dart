import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/config/provider_config.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/core/signal_core.dart';

import '../pages/login/login_begin_page.dart';
import '../pages/login/register_page.dart';
import '../pages/root/root_page.dart';
import 'local_store.dart';

class ImLoginManager {
  static Future<void> init(BuildContext context) async {}

  static SupabaseClient get _supabase => Supabase.instance.client;

  /// Pede ao Supabase Auth pra mandar o SMS de verificação pro número.
  /// Exige provedor de SMS configurado no painel (Authentication → Phone).
  static Future<void> login(String phoneRaw, BuildContext context,
      {void Function(String)? onLog}) async {
    final String phone = _normalizarTelefone(phoneRaw);

    try {
      onLog?.call('Checando sessão Supabase já ativa...');
      final sessaoAtual = _supabase.auth.currentSession;

      if (sessaoAtual != null && _supabase.auth.currentUser?.phone == phone.replaceFirst('+', '')) {
        onLog?.call('Sessão Supabase válida — entrando direto.');
        await SignalCore().inicializarCasulo(meuUserId: phone);
        await Get.offAll(() => RootPage());
        return;
      }

      onLog?.call('Enviando OTP via Supabase Auth pra $phone...');
      await _supabase.auth.signInWithOtp(phone: phone);
      onLog?.call('OTP enviado com sucesso.');

      await SharedUtil.instance.saveString(Keys.account, phone);
      await SharedUtil.instance.saveBoolean(Keys.hasLogged, false);

      showToast('Enviamos um SMS pro $phone com o código de verificação.');
      onLog?.call('Indo pra tela de código...');
      await Get.to(() => ProviderConfig.getInstance().getLoginPage(RegisterPage()));
    } catch (e, stack) {
      onLog?.call('EXCEÇÃO em login(): $e');
      onLog?.call('$stack');
      showToast('Falha ao enviar código: $e');
    }
  }

  /// Confirma o código de 6 dígitos recebido por SMS junto ao Supabase Auth.
  static Future<void> verify(String phone, String code, BuildContext context) async {
    final model = Provider.of<GlobalModel>(context, listen: false);

    try {
      final telefoneNormalizado = _normalizarTelefone(phone);

      final resposta = await _supabase.auth.verifyOTP(
        type: OtpType.sms,
        phone: telefoneNormalizado,
        token: code,
      );

      if (resposta.session == null) {
        showToast('Código inválido ou expirado.');
        return;
      }

      await SignalCore().inicializarCasulo(meuUserId: telefoneNormalizado);

      model.account = telefoneNormalizado;
      model.goToLogin = false;
      await SharedUtil.instance.saveString(Keys.account, telefoneNormalizado);
      await SharedUtil.instance.saveBoolean(Keys.hasLogged, true);
      model.refresh();

      showToast('Número verificado com sucesso');
      await Get.offAll(() => RootPage());
    } catch (e) {
      showToast('Falha ao verificar: $e');
    }
  }

  static Future<void> loginOut(BuildContext context) async {
    final model = Provider.of<GlobalModel>(context, listen: false);
    await _supabase.auth.signOut();
    model.goToLogin = true;
    model.refresh();
    await SharedUtil.instance.saveBoolean(Keys.hasLogged, false);
    await Get.offAll(() => LoginBeginPage());
    showToast('Sessão encerrada');
  }

  static String _normalizarTelefone(String texto) {
    final apenasDigitos = texto.replaceAll(RegExp(r'[^0-9+]'), '');
    if (apenasDigitos.startsWith('+')) return apenasDigitos;
    return '+55$apenasDigitos';
  }
}
