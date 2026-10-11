 import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/im/local_store.dart';

/// Autorrecuperação de sessão do Signal (Session Self-Healing).
///
/// Quando este aparelho não consegue decifrar uma mensagem (reinstalação,
/// ratchet fora de sincronia...), ele pede ao remetente, por um canal
/// VOLÁTIL do Supabase Realtime (`heal:<email>`), que renegocie a sessão.
/// Nada é gravado em tabela: o canal é só um relé cego e em tempo real.
///
///  1. Quem não conseguiu decifrar  -> manda `reset` ao remetente original.
///  2. O remetente descarta a sessão, abre uma nova (PreKey Bundle que o
///     próprio destinatário já publica), manda um pacote de inicialização e
///     reenvia as mensagens ainda não entregues.
///  3. Ao chegar o pacote novo, a sessão é gravada no Hive e o aviso
///     "Restaurando conexão segura…" some sozinho.
///
/// Proteções: o pedido só é atendido para quem já é contato/conversa, no
/// máximo 1 a cada 2 minutos por pessoa e [_maxPorHora] por hora.
class SessionHealing {
  SessionHealing._();
  static final SessionHealing instance = SessionHealing._();

  static const Duration _intervalo = Duration(minutes: 2);
  static const int _maxPorHora = 4;
  static const int _umaHoraMs = 60 * 60 * 1000;

  String _meuId = '';
  bool _ativo = false;
  RealtimeChannel? _entrada;

  /// pessoa -> quando (ms) começou a falha atual (ainda sem restauração).
  final Map<String, int> _inicioFalha = <String, int>{};

  /// Pedidos que EU fiz (por pessoa) e pedidos que EU atendi.
  final Map<String, List<int>> _pedidosFeitos = <String, List<int>>{};
  final Map<String, List<int>> _pedidosAtendidos = <String, List<int>>{};
  final Map<String, Timer> _novaTentativa = <String, Timer>{};

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Há falha ainda não restaurada com [pessoa]?
  bool temPendencia(String pessoa) => _inicioFalha.containsKey(pessoa);

  // ------------------------------------------------------------------ ciclo

  Future<void> iniciar(String meuId) async {
    final String id = meuId.trim().toLowerCase();
    if (id.isEmpty) return;
    if (_ativo && _meuId == id) return;
    if (_ativo) await parar();

    _meuId = id;
    _ativo = true;

    // Se o app foi fechado no meio de uma recuperação, o aviso ainda está na
    // conversa: retoma o pedido.
    final List<String> pendentes = <String>[];
    for (final Map<String, dynamic> c in SignalLocalStore.getConversations()) {
      final dynamic pessoa = c['conversationID'];
      final dynamic ultima = c['lastMessage'];
      if (pessoa is String &&
          ultima is Map &&
          ((ultima['msgID'] as String?) ?? '').startsWith('heal_')) {
        _inicioFalha[pessoa] = DateTime.now().millisecondsSinceEpoch;
        pendentes.add(pessoa);
      }
    }

    _escutar();
    for (final String pessoa in pendentes) {
      unawaited(_pedirReinicio(pessoa));
    }
  }

  Future<void> reconectar() async {
    if (_ativo) _escutar();
  }

  Future<void> parar() async {
    _ativo = false;
    _meuId = '';
    for (final Timer t in _novaTentativa.values) {
      t.cancel();
    }
    _novaTentativa.clear();
    _inicioFalha.clear();
    _pedidosFeitos.clear();
    _pedidosAtendidos.clear();
    final RealtimeChannel? canal = _entrada;
    _entrada = null;
    if (canal != null) {
      try {
        await _supabase.removeChannel(canal);
      } catch (_) {}
    }
  }

  void _escutar() {
    final RealtimeChannel? antigo = _entrada;
    if (antigo != null) {
      try {
        _supabase.removeChannel(antigo);
      } catch (_) {}
    }
    try {
      _entrada = _supabase
          .channel('heal:$_meuId')
          .onBroadcast(
              event: 'reset',
              callback: (dynamic p) => _aoReceberPedido(_corpo(p)))
          .subscribe();
    } catch (e) {
      debugPrint('[Healing] não consegui escutar o canal: $e');
    }
  }

  Map<String, dynamic> _corpo(dynamic bruto) {
    final Map<String, dynamic> m = Map<String, dynamic>.from(bruto as Map);
    final dynamic interno = m['payload'];
    if (interno is Map && m.containsKey('event')) {
      return Map<String, dynamic>.from(interno);
    }
    return m;
  }

  // ----------------------------------------------- lado de quem não decifrou

  /// O SignalCore chama isto quando uma mensagem de [remetente] não abriu.
  /// Não espera nada demorado: só registra e dispara o pedido.
  void aoFalharDecifrar(String remetente, {int? criadoEm}) {
    if (!_ativo) return;
    final int agora = DateTime.now().millisecondsSinceEpoch;
    final int inicio = criadoEm ?? agora;
    final int? antigo = _inicioFalha[remetente];
    _inicioFalha[remetente] = antigo == null ? inicio : min(antigo, inicio);
    unawaited(_pedirReinicio(remetente));
  }

  /// Uma mensagem de [remetente] abriu: a sessão voltou.
  void aoRestaurar(String remetente) {
    _inicioFalha.remove(remetente);
    _novaTentativa.remove(remetente)?.cancel();
  }

  Future<void> _pedirReinicio(String remetente) async {
    if (!_ativo || !_inicioFalha.containsKey(remetente)) return;

    final int agora = DateTime.now().millisecondsSinceEpoch;
    final List<int> feitos =
        _pedidosFeitos.putIfAbsent(remetente, () => <int>[]);
    feitos.removeWhere((int t) => agora - t > _umaHoraMs);

    final bool respeitaIntervalo =
        feitos.isEmpty || agora - feitos.last >= _intervalo.inMilliseconds;
    if (!respeitaIntervalo || feitos.length >= _maxPorHora) return;
    feitos.add(agora);

    try {
      await _enviar(remetente, 'reset', <String, dynamic>{
        'from': _meuId,
        // O remetente reenvia o que foi enviado a partir de pouco antes da
        // primeira falha.
        'desde': (_inicioFalha[remetente] ?? agora) - 60 * 1000,
        'ts': agora,
      });
    } catch (e) {
      debugPrint('[Healing] não consegui pedir a $remetente: $e');
    }

    // Se o outro lado estiver offline, tenta de novo daqui a pouco.
    _novaTentativa[remetente]?.cancel();
    _novaTentativa[remetente] = Timer(
      _intervalo + const Duration(seconds: 10),
      () => _pedirReinicio(remetente),
    );
  }

  // --------------------------------------------- lado do remetente original

  Future<void> _aoReceberPedido(Map<String, dynamic> m) async {
    final String? de = (m['from'] as String?)?.trim().toLowerCase();
    if (!_ativo || de == null || de.isEmpty || de == _meuId) return;

    // O canal é público: só atende quem já é contato ou conversa.
    if (!_conhecido(de)) return;

    final int agora = DateTime.now().millisecondsSinceEpoch;
    final List<int> atendidos =
        _pedidosAtendidos.putIfAbsent(de, () => <int>[]);
    atendidos.removeWhere((int t) => agora - t > _umaHoraMs);
    if (atendidos.isNotEmpty &&
        agora - atendidos.last < _intervalo.inMilliseconds - 5000) {
      return;
    }
    if (atendidos.length >= _maxPorHora + 2) return;
    atendidos.add(agora);

    final int? desde = (m['desde'] as num?)?.toInt();
    try {
      await SignalCore().renegociarSessao(de, desde: desde);
    } catch (e) {
      debugPrint('[Healing] não consegui renegociar com $de: $e');
    }
  }

  bool _conhecido(String id) {
    for (final Map<String, dynamic> c in SignalLocalStore.getContacts()) {
      if (c['phone'] == id) return true;
    }
    for (final Map<String, dynamic> c in SignalLocalStore.getConversations()) {
      if (c['conversationID'] == id) return true;
    }
    return false;
  }

  // ------------------------------------------------------------- transporte

  /// Entra no canal da outra pessoa só pelo tempo de enviar e sai.
  Future<void> _enviar(
      String destino, String evento, Map<String, dynamic> payload) async {
    final RealtimeChannel canal = _supabase.channel('heal:$destino');
    final Completer<void> pronto = Completer<void>();
    canal.subscribe((RealtimeSubscribeStatus status, Object? erro) {
      if (pronto.isCompleted) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        pronto.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        pronto.completeError(erro ?? StateError('canal: $status'));
      }
    });
    try {
      await pronto.future.timeout(const Duration(seconds: 8));
      await canal.sendBroadcastMessage(event: evento, payload: payload);
    } finally {
      try {
        await _supabase.removeChannel(canal);
      } catch (_) {}
    }
  }
}
