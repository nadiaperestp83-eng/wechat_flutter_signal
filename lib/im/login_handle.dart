import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import '../pages/login/login_begin_page.dart';
import '../pages/login/register_page.dart';
import '../pages/root/root_page.dart';
import 'local_store.dart';
import 'signal_bridge_client.dart';

/// Mantém os mesmos nomes de método que a UI original já chama
/// (login_page.dart chama ImLoginManager.login(...), mine chama
/// ImLoginManager.loginOut(...)) — só o que acontece por dentro mudou.
class ImLoginManager {
  /// Não existe SDK pra inicializar aqui (é HTTP puro), mas mantemos o
  /// método pra não quebrar quem já chama ImLoginManager.init em algum lugar.
  static Future<void> init(BuildContext context) async {}

  /// Extraído pra ser reaproveitado tanto pelo login_page.dart (via login())
  /// quanto pela RegisterPage direto (quando o usuário chega por ali sem
  /// passar pelo login_page.dart — ex: botão "Cadastre-se" da tela inicial).
  /// Garante que o número está registrado no signal-cli e que o SMS foi
  /// disparado, sem duplicar envio se já está registrado.
  static Future<Map<String, dynamic>> requestCode(String phoneRaw) async {
    final String phone = _normalizarTelefone(phoneRaw);

    final statusAtual = await SignalBridgeClient.status(phone);
    if (statusAtual['registrado'] == true) {
      return {'sucesso': true, 'jaRegistrado': true, 'phone': phone};
    }

    final resultado = await SignalBridgeClient.register(phone);
    return {...resultado, 'phone': phone};
  }

  /// Chamado pelo botão "próximo passo" da tela de login com o número
  /// digitado. Registra o número no Signal (via bridge) e manda o usuário
  /// pra tela de código (reaproveitando RegisterPage).
  static Future<void> login(String phoneRaw, BuildContext context) async {
    final String phone = _normalizarTelefone(phoneRaw);

    try {
      // Já verificado localmente neste aparelho -> pula direto pra dentro.
      final String? sessaoAtual = await SharedUtil.instance.getString(Keys.account);
      final bool sessaoValida =
          sessaoAtual == phone && await SharedUtil.instance.getBoolean(Keys.hasLogged);

      if (sessaoValida) {
        await Get.offAll(() => RootPage());
        return;
      }

      final resultadoRegistro = await requestCode(phone);
      if (resultadoRegistro['sucesso'] == false) {
        if (resultadoRegistro['precisaCaptcha'] == true) {
          showToast(
            'O Signal pediu verificação extra (captcha) pra esse número. '
            'Abra ${resultadoRegistro['captchaUrl']} e tente de novo depois.',
          );
          return;
        }
        showToast('Falha ao registrar: ${resultadoRegistro['erro'] ?? 'erro desconhecido'}');
        return;
      }

      // Guarda o número "pendente" (aguardando código) — RegisterPage lê
      // isso pra saber pra quem enviar o verify().
      await SharedUtil.instance.saveString(Keys.account, phone);
      await SharedUtil.instance.saveBoolean(Keys.hasLogged, false);

      showToast('Enviamos um SMS pro $phone com o código de verificação.');
      await Get.to(() => RegisterPage());
    } catch (e) {
      showToast('Falha ao falar com o servidor Signal: $e');
    }
  }

  /// Chamado pela RegisterPage (reaproveitada como tela de código) depois
  /// que o usuário digita o SMS recebido.
  static Future<void> verify(String phone, String code, BuildContext context) async {
    final model = Provider.of<GlobalModel>(context, listen: false);

    try {
      final resultado = await SignalBridgeClient.verify(phone, code);
      if (resultado['sucesso'] != true) {
        showToast('Código inválido: ${resultado['erro'] ?? ''}');
        return;
      }

      model.account = phone;
      model.goToLogin = false;
      await SharedUtil.instance.saveString(Keys.account, phone);
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
    model.goToLogin = true;
    model.refresh();
    await SharedUtil.instance.saveBoolean(Keys.hasLogged, false);
    await Get.offAll(() => LoginBeginPage());
    showToast('Sessão encerrada');
  }

  static String _normalizarTelefone(String texto) {
    final apenasDigitos = texto.replaceAll(RegExp(r'[^0-9+]'), '');
    return apenasDigitos.startsWith('+') ? apenasDigitos : '+$apenasDigitos';
  }
}
