import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/config/provider_config.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/core/signal_core.dart';

import '../pages/login/login_begin_page.dart';
import '../pages/login/register_page.dart';
import '../pages/login/signal_captcha_page.dart';
import '../pages/root/root_page.dart';
import 'local_store.dart';
import 'signal_bridge_client.dart';

class ImLoginManager {
  static Future<void> init(BuildContext context) async {}

  static Future<Map<String, dynamic>> requestCode(String phoneRaw,
      {void Function(String)? onLog}) async {
    final String phone = _normalizarTelefone(phoneRaw);
    onLog?.call('Verificando status de $phone...');

    final statusAtual = await SignalBridgeClient.status(phone);
    onLog?.call('status() -> $statusAtual');

    if (statusAtual['registrado'] == true) {
      return {'sucesso': true, 'jaRegistrado': true, 'phone': phone};
    }

    onLog?.call('Chamando register($phone)...');
    var resultado = await SignalBridgeClient.register(phone);
    onLog?.call('register() -> $resultado');

    if (resultado['sucesso'] == false && resultado['precisaCaptcha'] == true) {
      onLog?.call('Precisa de captcha — abrindo WebView...');
      showToast('O Signal pediu uma verificação extra — resolva a tela que vai abrir.');
      final String? token = await Get.to<String?>(() => SignalCaptchaPage());
      onLog?.call('Token do captcha: ${token ?? "NENHUM (usuário fechou ou falhou)"}');

      if (token == null || token.isEmpty) {
        return {'sucesso': false, 'erro': 'Verificação não concluída', 'phone': phone};
      }

      onLog?.call('Chamando register($phone, captchaToken)...');
      resultado = await SignalBridgeClient.register(phone, captchaToken: token);
      onLog?.call('register() com captcha -> $resultado');
    }

    return {...resultado, 'phone': phone};
  }

  static Future<void> login(String phoneRaw, BuildContext context,
      {void Function(String)? onLog}) async {
    final String phone = _normalizarTelefone(phoneRaw);

    try {
      onLog?.call('Checando sessão local salva...');
      final String? sessaoAtual = await SharedUtil.instance.getString(Keys.account);
      final bool sessaoValida =
          sessaoAtual == phone && await SharedUtil.instance.getBoolean(Keys.hasLogged);

      if (sessaoValida) {
        onLog?.call('Sessão local válida — entrando direto.');
        await SignalCore().inicializarCasulo(meuUserId: phone);
        await Get.offAll(() => RootPage());
        return;
      }

      final resultadoRegistro = await requestCode(phone, onLog: onLog);
      onLog?.call('requestCode() final: $resultadoRegistro');
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

      // Já registrado antes (ex: reinstalou o app) — o Casulo publica
      // um bundle novo (as chaves antigas ficaram só no aparelho anterior,
      // não tem como recuperar) e entra direto, sem pedir SMS de novo.
      if (resultadoRegistro['jaRegistrado'] == true) {
        onLog?.call('Já registrado no Signal — inicializando Casulo e entrando direto...');
        await SignalCore().inicializarCasulo(meuUserId: phone);
        await SharedUtil.instance.saveString(Keys.account, phone);
        await SharedUtil.instance.saveBoolean(Keys.hasLogged, true);
        await Get.offAll(() => RootPage());
        return;
      }

      await SharedUtil.instance.saveString(Keys.account, phone);
      await SharedUtil.instance.saveBoolean(Keys.hasLogged, false);

      showToast('Enviamos um SMS pro $phone com o código de verificação.');
      onLog?.call('Indo pra tela de código...');
      await Get.to(() => ProviderConfig.getInstance().getLoginPage(RegisterPage()));
    } catch (e, stack) {
      onLog?.call('EXCEÇÃO em login(): $e');
      onLog?.call('$stack');
      showToast('Falha ao falar com o servidor Signal: $e');
    }
  }

  static Future<void> verify(String phone, String code, BuildContext context) async {
    final model = Provider.of<GlobalModel>(context, listen: false);

    try {
      final resultado = await SignalBridgeClient.verify(phone, code);
      if (resultado['sucesso'] != true) {
        showToast('Código inválido: ${resultado['erro'] ?? ''}');
        return;
      }

      await SignalCore().inicializarCasulo(meuUserId: phone);

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
    if (apenasDigitos.startsWith('+')) return apenasDigitos;
    return '+55$apenasDigitos';
  }
}
