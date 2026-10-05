import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/tools/shared_util.dart';

/// Estado de presença de um contato.
class PresencaContato {
  final bool carregado;
  final bool online;
  final DateTime? ultimaVez;

  const PresencaContato({
    this.carregado = false,
    this.online = false,
    this.ultimaVez,
  });
}

class _Observacao {
  final ValueNotifier<PresencaContato> valor =
      ValueNotifier<PresencaContato>(const PresencaContato());
  RealtimeChannel? canal;
  Timer? temporizador;
  bool online = false;
  DateTime? ultima;
  int referencias = 0;
  bool encerrado = false;
}

/// Presença real via Supabase.
///
///  - "online": Realtime Presence no canal `presence:<email>`. Enquanto o app
///    está aberto, o aparelho fica registrado nesse canal.
///  - "visto por último": coluna `last_seen` em `signal_accounts`, gravada
///    quando o app abre, a cada 60 s e ao ir para segundo plano.
///
/// Se o usuário desligar o compartilhamento (Configurações), ele sai do canal
/// e apaga o `last_seen`: ninguém vê o status dele.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const String _chavePrefOculto = 'ocultarPresenca';
  static const Duration _intervalo = Duration(seconds: 60);

  /// true = mostro meu status para os outros.
  final ValueNotifier<bool> compartilhando = ValueNotifier<bool>(true);

  String _meuId = '';
  bool _ativo = false;
  bool _observandoCiclo = false;
  RealtimeChannel? _canal;
  Timer? _batimento;
  final Map<String, _Observacao> _observacoes = <String, _Observacao>{};

  SupabaseClient get _supabase => Supabase.instance.client;

  // ---------------------------------------------------------------- meu status

  Future<void> iniciar(String meuId) async {
    final String id = meuId.trim().toLowerCase();
    if (id.isEmpty) return;
    if (_ativo && _meuId == id) return;
    if (_ativo) await parar();

    _meuId = id;
    _ativo = true;
    final bool oculto = await SharedUtil.instance.getBoolean(_chavePrefOculto);
    compartilhando.value = !oculto;

    if (!_observandoCiclo) {
      WidgetsBinding.instance.addObserver(this);
      _observandoCiclo = true;
    }
    if (compartilhando.value) await _entrarOnline();
  }

  /// Chamar no logout, ANTES do signOut do Supabase.
  Future<void> parar() async {
    if (!_ativo) return;
    if (compartilhando.value) await _sairOnline(apagarUltimaVez: false);
    _ativo = false;
    _meuId = '';
    if (_observandoCiclo) {
      WidgetsBinding.instance.removeObserver(this);
      _observandoCiclo = false;
    }
    for (final _Observacao o in _observacoes.values) {
      _encerrarObservacao(o);
    }
    _observacoes.clear();
  }

  Future<void> definirCompartilhamento(bool valor) async {
    await SharedUtil.instance.saveBoolean(_chavePrefOculto, !valor);
    compartilhando.value = valor;
    if (!_ativo) return;
    if (valor) {
      await _entrarOnline();
    } else {
      await _sairOnline(apagarUltimaVez: true);
    }
  }

  Future<void> _entrarOnline() async {
    if (!_ativo || !compartilhando.value) return;
    await _fecharCanal();
    try {
      final RealtimeChannel canal = _supabase.channel('presence:$_meuId');
      _canal = canal;
      canal.subscribe((RealtimeSubscribeStatus status, Object? erro) async {
        if (status == RealtimeSubscribeStatus.subscribed &&
            identical(_canal, canal)) {
          await _marcarPresente(canal);
        }
      });
    } catch (e) {
      debugPrint('[PresenceService] falha ao entrar no canal: $e');
    }
    _batimento?.cancel();
    _batimento = Timer.periodic(_intervalo, (_) => _batida());
    await _gravarUltimaVez(DateTime.now());
  }

  Future<void> _sairOnline({required bool apagarUltimaVez}) async {
    _batimento?.cancel();
    _batimento = null;
    await _fecharCanal();
    await _gravarUltimaVez(apagarUltimaVez ? null : DateTime.now());
  }

  Future<void> _marcarPresente(RealtimeChannel canal) async {
    try {
      await canal.track(<String, dynamic>{
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[PresenceService] falha no track: $e');
    }
  }

  void _batida() {
    if (!_ativo || !compartilhando.value) return;
    _gravarUltimaVez(DateTime.now());
    final RealtimeChannel? canal = _canal;
    if (canal != null) _marcarPresente(canal);
  }

  Future<void> _fecharCanal() async {
    final RealtimeChannel? canal = _canal;
    _canal = null;
    if (canal == null) return;
    try {
      await canal.untrack();
    } catch (_) {}
    try {
      await _supabase.removeChannel(canal);
    } catch (_) {}
  }

  Future<void> _gravarUltimaVez(DateTime? quando) async {
    if (_meuId.isEmpty) return;
    try {
      await _supabase.from('signal_accounts').upsert(<String, dynamic>{
        'phone': _meuId,
        'last_seen': quando?.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[PresenceService] não consegui gravar last_seen: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ativo || !compartilhando.value) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _entrarOnline();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _sairOnline(apagarUltimaVez: false);
        break;
      default:
        break;
    }
  }

  // --------------------------------------------------------- status dos outros

  /// Começa a acompanhar [userId]. Chame [liberar] quando não precisar mais.
  ValueListenable<PresencaContato> observar(String userId) {
    final String id = userId.trim().toLowerCase();
    final _Observacao obs = _observacoes.putIfAbsent(id, () {
      final _Observacao nova = _Observacao();
      _iniciarObservacao(id, nova);
      return nova;
    });
    obs.referencias++;
    return obs.valor;
  }

  void liberar(String userId) {
    final String id = userId.trim().toLowerCase();
    final _Observacao? obs = _observacoes[id];
    if (obs == null) return;
    obs.referencias--;
    if (obs.referencias > 0) return;
    _observacoes.remove(id);
    _encerrarObservacao(obs);
    obs.valor.dispose();
  }

  void _iniciarObservacao(String id, _Observacao obs) {
    _buscarUltimaVez(id, obs);
    obs.temporizador = Timer.periodic(_intervalo, (_) {
      if (!obs.online) _buscarUltimaVez(id, obs);
    });

    try {
      final RealtimeChannel canal = _supabase.channel('presence:$id');
      obs.canal = canal;
      canal
          .onPresenceSync((_) => _atualizarOnline(id, obs))
          .onPresenceJoin((_) => _atualizarOnline(id, obs))
          .onPresenceLeave((_) => _atualizarOnline(id, obs))
          .subscribe();
    } catch (e) {
      debugPrint('[PresenceService] não consegui observar $id: $e');
    }
  }

  void _atualizarOnline(String id, _Observacao obs) {
    if (obs.encerrado) return;
    final RealtimeChannel? canal = obs.canal;
    if (canal == null) return;
    final bool agoraOnline = canal.presenceState().isNotEmpty;
    final bool saiu = obs.online && !agoraOnline;
    obs.online = agoraOnline;
    _publicar(obs);
    if (saiu) _buscarUltimaVez(id, obs);
  }

  Future<void> _buscarUltimaVez(String id, _Observacao obs) async {
    try {
      final dynamic linha = await _supabase
          .from('signal_accounts')
          .select('last_seen')
          .eq('phone', id)
          .maybeSingle();
      if (obs.encerrado) return;
      final dynamic bruto = linha == null ? null : (linha as Map)['last_seen'];
      obs.ultima =
          bruto is String ? DateTime.tryParse(bruto)?.toLocal() : null;
      _publicar(obs);
    } catch (e) {
      debugPrint('[PresenceService] last_seen de $id: $e');
      if (!obs.encerrado) _publicar(obs);
    }
  }

  void _publicar(_Observacao obs) {
    if (obs.encerrado) return;
    obs.valor.value = PresencaContato(
      carregado: true,
      online: obs.online,
      ultimaVez: obs.ultima,
    );
  }

  void _encerrarObservacao(_Observacao obs) {
    obs.encerrado = true;
    obs.temporizador?.cancel();
    final RealtimeChannel? canal = obs.canal;
    obs.canal = null;
    if (canal != null) {
      try {
        _supabase.removeChannel(canal);
      } catch (_) {}
    }
  }
}
