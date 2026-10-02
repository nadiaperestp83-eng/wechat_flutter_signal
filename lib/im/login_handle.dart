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
import 'info_handle.dart';
import 'local_store.dart';

class ImLoginManager {
  static Future<void> init(BuildContext context) async {}

  static SupabaseClient get _supabase => Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // SMS (fluxo original — sem alterações)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // E-MAIL + SENHA (novo)
  //
  // O identificador do usuário no app inteiro (Signal, Firestore, tabelas
  // signal_*) é uma String guardada em Keys.account. No SMS é o telefone;
  // aqui é o e-mail em minúsculas. Nada mais no app precisa mudar.
  //
  // Requer no painel do Supabase:
  //   Authentication → Providers → Email: habilitado
  //   "Confirm email": DESATIVADO (pra entrar direto após cadastrar)
  // ---------------------------------------------------------------------------

  /// Cria a conta com e-mail + senha + apelido e já entra no app.
  static Future<void> registerWithEmail(
    String emailRaw,
    String password,
    String nickname,
    BuildContext context, {
    void Function(String)? onLog,
  }) async {
    final String email = _normalizarEmail(emailRaw);
    final String apelido = nickname.trim();

    if (apelido.isEmpty) {
      showToast('Digite um apelido');
      return;
    }
    if (!_emailValido(email)) {
      showToast('Digite um e-mail válido');
      return;
    }
    if (password.length < 6) {
      showToast('A senha precisa ter pelo menos 6 caracteres');
      return;
    }

    try {
      onLog?.call('Criando conta no Supabase Auth: $email ...');
      final resposta = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'nickname': apelido},
      );

      if (resposta.session == null) {
        onLog?.call('signUp OK, mas sem sessão: "Confirm email" está ATIVADO no Supabase.');
        showToast('Conta criada, mas o Supabase exige confirmação de e-mail. '
            'Desative "Confirm email" em Authentication → Providers → Email.');
        return;
      }

      onLog?.call('Conta criada com sessão ativa. Finalizando...');
      await _concluirLoginEmail(
        email: email,
        apelido: apelido,
        context: context,
        onLog: onLog,
      );
    } on AuthException catch (e) {
      onLog?.call('AuthException em registerWithEmail(): ${e.message}');
      showToast(_traduzirErroAuth(e));
    } catch (e, stack) {
      onLog?.call('EXCEÇÃO em registerWithEmail(): $e');
      onLog?.call('$stack');
      showToast('Falha ao cadastrar: $e');
    }
  }

  /// Entra com e-mail + senha de uma conta já existente.
  static Future<void> loginWithEmail(
    String emailRaw,
    String password,
    BuildContext context, {
    void Function(String)? onLog,
  }) async {
    final String email = _normalizarEmail(emailRaw);

    if (!_emailValido(email)) {
      showToast('Digite um e-mail válido');
      return;
    }
    if (password.isEmpty) {
      showToast('Digite a senha');
      return;
    }

    try {
      onLog?.call('Entrando no Supabase Auth: $email ...');
      final resposta = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (resposta.session == null) {
        onLog?.call('signInWithPassword sem sessão.');
        showToast('Não foi possível entrar. Tente novamente.');
        return;
      }

      final metadado = resposta.user?.userMetadata?['nickname'];
      final String? apelido =
          metadado is String && metadado.trim().isNotEmpty ? metadado.trim() : null;

      onLog?.call('Login OK. Finalizando...');
      await _concluirLoginEmail(
        email: email,
        apelido: apelido,
        context: context,
        onLog: onLog,
      );
    } on AuthException catch (e) {
      onLog?.call('AuthException em loginWithEmail(): ${e.message}');
      showToast(_traduzirErroAuth(e));
    } catch (e, stack) {
      onLog?.call('EXCEÇÃO em loginWithEmail(): $e');
      onLog?.call('$stack');
      showToast('Falha ao entrar: $e');
    }
  }

  /// Passos comuns após autenticar por e-mail (cadastro ou login):
  /// inicia o SignalCore, grava a conta local, salva o apelido e abre o app.
  static Future<void> _concluirLoginEmail({
    required String email,
    required String? apelido,
    required BuildContext context,
    void Function(String)? onLog,
  }) async {
    final model = Provider.of<GlobalModel>(context, listen: false);

    // Se havia outra conta ativa nesta execução do app, reinicia o Casulo
    // com o novo identificador (inicializarCasulo ignora chamadas repetidas).
    await SignalCore().encerrarCasulo();

    onLog?.call('Iniciando SignalCore (bundle/prekeys no Supabase)...');
    await SignalCore().inicializarCasulo(meuUserId: email);

    // A conta precisa ser salva ANTES do hasLogged: SharedUtil usa a conta
    // como sufixo das demais chaves.
    await SharedUtil.instance.saveString(Keys.account, email);
    await SharedUtil.instance.saveBoolean(Keys.hasLogged, true);

    if (apelido != null && apelido.isNotEmpty) {
      await SharedUtil.instance.saveString(Keys.nickName, apelido);

      final perfil = SignalLocalStore.getSelfProfile(email) ?? <String, dynamic>{};
      perfil['name'] = apelido;
      await SignalLocalStore.saveSelfProfile(email, perfil);

      // Publica o apelido em signal_accounts (a coluna "phone" guarda o
      // identificador da conta, que aqui é o e-mail).
      final ok = await setUsersProfileMethod(context, nickNameStr: apelido);
      onLog?.call(ok
          ? 'Apelido salvo em signal_accounts.'
          : 'AVISO: não consegui salvar o apelido em signal_accounts (veja as policies/RLS).');
      model.nickName = apelido;
    }

    model.account = email;
    model.goToLogin = false;
    model.refresh();

    showToast('Bem-vindo(a)!');
    await Get.offAll(() => RootPage());
  }

  // ---------------------------------------------------------------------------

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

  static String _normalizarEmail(String texto) => texto.trim().toLowerCase();

  static bool _emailValido(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  static String _traduzirErroAuth(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (msg.contains('already registered') || msg.contains('already been registered')) {
      return 'Esse e-mail já está cadastrado. Use "Entrar com e-mail".';
    }
    if (msg.contains('password')) {
      return 'Senha inválida: ${e.message}';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Muitas tentativas. Aguarde um pouco e tente de novo.';
    }
    if (msg.contains('email not confirmed')) {
      return 'E-mail não confirmado. Desative "Confirm email" no Supabase.';
    }
    if (msg.contains('signups not allowed') || msg.contains('provider is not enabled')) {
      return 'Login por e-mail não está habilitado no Supabase.';
    }
    return e.message;
  }
}
