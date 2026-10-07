import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Uma ligação no histórico (só metadados; nunca áudio nem vídeo).
class CallRecord {
  final String id;
  final String peer;
  final bool video;

  /// true = recebida; false = feita por mim.
  final bool entrada;

  /// 'atendida' | 'perdida' | 'recusada' | 'semResposta' | 'ocupado'
  final String resultado;
  final int ts; // início (ms)
  final int dur; // segundos falados

  const CallRecord({
    required this.id,
    required this.peer,
    required this.video,
    required this.entrada,
    required this.resultado,
    required this.ts,
    required this.dur,
  });

  bool get perdida => entrada && resultado != 'atendida' && resultado != 'recusada';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'peer': peer,
        'video': video,
        'in': entrada,
        'res': resultado,
        'ts': ts,
        'dur': dur,
      };

  static CallRecord fromMap(Map<dynamic, dynamic> m) => CallRecord(
        id: m['id'] as String,
        peer: m['peer'] as String,
        video: m['video'] == true,
        entrada: m['in'] == true,
        resultado: (m['res'] as String?) ?? 'perdida',
        ts: (m['ts'] as num?)?.toInt() ?? 0,
        dur: (m['dur'] as num?)?.toInt() ?? 0,
      );
}

/// Histórico de ligações guardado SOMENTE neste aparelho (Hive), por conta.
/// Nada vai para a nuvem. Fica guardado até a pessoa apagar.
class CallLog {
  CallLog._();
  static final CallLog instance = CallLog._();

  /// Sobe a cada mudança; a tela Ligações escuta isto.
  final ValueNotifier<int> versao = ValueNotifier<int>(0);

  Box<dynamic>? _box;
  String _conta = '';

  Future<void> iniciar(String meuId) async {
    final String id = meuId.trim().toLowerCase();
    if (id.isEmpty) return;
    if (_box != null && _conta == id) return;

    _conta = id;
    final String sufixo = id.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    _box = await Hive.openBox<dynamic>('signal_call_log_$sufixo');
    versao.value = versao.value + 1;
  }

  /// Chamar no logout: a tela deixa de mostrar o histórico desta conta.
  Future<void> fechar() async {
    _box = null;
    _conta = '';
    versao.value = versao.value + 1;
  }

  Future<void> registrar({
    required String id,
    required String peer,
    required bool video,
    required bool entrada,
    required String resultado,
    required int ts,
    required int dur,
  }) async {
    final Box<dynamic>? box = _box;
    if (box == null) return;
    await box.put(
      id,
      CallRecord(
        id: id,
        peer: peer,
        video: video,
        entrada: entrada,
        resultado: resultado,
        ts: ts,
        dur: dur,
      ).toMap(),
    );
    versao.value = versao.value + 1;
  }

  /// Mais recentes primeiro.
  List<CallRecord> listar() {
    final Box<dynamic>? box = _box;
    if (box == null) return <CallRecord>[];
    final List<CallRecord> lista = <CallRecord>[];
    for (final dynamic v in box.values) {
      if (v is! Map) continue;
      try {
        lista.add(CallRecord.fromMap(v));
      } catch (_) {}
    }
    lista.sort((CallRecord a, CallRecord b) => b.ts.compareTo(a.ts));
    return lista;
  }

  Future<void> apagar(String id) async {
    await _box?.delete(id);
    versao.value = versao.value + 1;
  }

  Future<void> limpar() async {
    await _box?.clear();
    versao.value = versao.value + 1;
  }
}
