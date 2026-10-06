import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/core/call_service.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Segundo plano do chat:
///  - ao abrir o app já logado, liga o SignalCore (chaves + Realtime);
///  - registra o token FCM no Supabase pra receber "Nova mensagem" com o app fechado;
///  - ao voltar pro primeiro plano, reconecta o Realtime e busca o que chegou.
class PushService with WidgetsBindingObserver {
  PushService._();
  static final PushService instance = PushService._();

  bool _observando = false;
  String? _token;
  StreamSubscription<String>? _subTroca;
  StreamSubscription<RemoteMessage>? _subMensagem;

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Chamado pela RootPage (usuário logado).
  Future<void> iniciar() async {
    if (!_observando) {
      WidgetsBinding.instance.addObserver(this);
      _observando = true;
    }

    // 1) Reabriu o app já logado: o login não roda de novo, então liga aqui.
    try {
      final String? conta = await SharedUtil.instance.getString(Keys.account);
      if (!SignalCore().estaInicializado &&
          conta != null &&
          conta.isNotEmpty &&
          _supabase.auth.currentSession != null) {
        await SignalCore().inicializarCasulo(meuUserId: conta);
      }
      // Chamadas de voz/vídeo: escuta convites (Broadcast + tela cheia).
      if (conta != null &&
          conta.isNotEmpty &&
          _supabase.auth.currentSession != null) {
        await CallService.instance.iniciar(conta);
      }
    } catch (e) {
      print('Erro ao iniciar o SignalCore: $e');
    }

    // 2) Push
    await _registrarPush();
  }

  Future<void> _registrarPush() async {
    try {
      final FirebaseMessaging fm = FirebaseMessaging.instance;
      await fm.requestPermission(); // Android 13+: pede permissão de notificação
      final String? token = await fm.getToken();
      if (token != null) await _salvarToken(token);
      _subTroca ??= fm.onTokenRefresh.listen(_salvarToken);
      // Push de chamada com o app aberto (com o app fechado, quem trata é o
      // chamadasFirebaseBackground, registrado no main.dart).
      _subMensagem ??=
          FirebaseMessaging.onMessage.listen(CallService.instance.aoReceberPush);
    } catch (e) {
      print('Push indisponível: $e');
    }
  }

  Future<void> _salvarToken(String token) async {
    _token = token;
    try {
      await _supabase.rpc('register_push_token',
          params: <String, dynamic>{'p_token': token, 'p_platform': 'android'});
    } catch (e) {
      print('Erro ao registrar token de push: $e');
    }
  }

  /// No logout: este aparelho para de receber avisos da conta que saiu.
  /// Precisa rodar ANTES do signOut (a função exige usuário autenticado).
  Future<void> parar() async {
    final String? token = _token;
    _token = null;
    await _subTroca?.cancel();
    _subTroca = null;
    await _subMensagem?.cancel();
    _subMensagem = null;
    await CallService.instance.parar();
    try {
      if (token != null) {
        await _supabase.rpc('unregister_push_token',
            params: <String, dynamic>{'p_token': token});
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      print('Erro ao remover token de push: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O Android derruba o Realtime em segundo plano: ao voltar, reconecta e
    // busca o que chegou enquanto o app estava parado.
    if (state == AppLifecycleState.resumed) {
      SignalCore().reconectarSeNecessario();
    }
  }
}
