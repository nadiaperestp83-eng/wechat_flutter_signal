import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:wechat_flutter/im/local_store.dart';
import 'package:wechat_flutter/tools/event/im_event.dart';

class MensagemDescriptografada {
  final String remetente;
  final String texto;
  final DateTime timestamp;

  MensagemDescriptografada({
    required this.remetente,
    required this.texto,
    required this.timestamp,
  });
}

/// Status de mensagem enviada (guardado em 'status' no Hive):
///   1 = enviando, 2 = enviada ao servidor (1 visto cinza),
///   6 = entregue no aparelho do destinatário (2 vistos cinza),
///   7 = lida (2 vistos azuis), 3/4 = falha.
class StatusMensagem {
  static const int enviando = 1;
  static const int enviada = 2;
  static const int entregue = 6;
  static const int lida = 7;
}

class SignalCore {
  static final SignalCore _instance = SignalCore._internal();
  factory SignalCore() => _instance;
  SignalCore._internal();

  bool _inicializado = false;
  RealtimeChannel? _canal;
  String _meuUserId = '';

  late IdentityKeyPair _identityKeyPair;
  late int _registrationId;
  late SignedPreKeyRecord _signedPreKey;

  late InMemorySessionStore _sessionStore;
  late InMemoryPreKeyStore _preKeyStore;
  late InMemorySignedPreKeyStore _signedPreKeyStore;
  late InMemoryIdentityKeyStore _identityKeyStore;

  final Set<String> _sessoesEstabelecidas = {};

  /// Fila única: criptografar/descriptografar mexe no estado das sessões,
  /// então tudo roda um de cada vez (evita corrida entre envio e recebimento).
  Future<void> _fila = Future<void>.value();
  final Set<String> _linhasVistas = <String>{};

  final StreamController<MensagemDescriptografada> _streamController =
      StreamController<MensagemDescriptografada>.broadcast();

  Stream<MensagemDescriptografada> get mensagensRecebidas =>
      _streamController.stream;
  bool get estaInicializado => _inicializado;
  String get meuUserId => _meuUserId;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<T> _serializar<T>(Future<T> Function() tarefa) {
    final Completer<T> completer = Completer<T>();
    _fila = _fila.then((_) async {
      try {
        completer.complete(await tarefa());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<void> inicializarCasulo({required String meuUserId}) async {
    if (_inicializado) return;
    _meuUserId = meuUserId;

    // Estado novo a cada inicialização (também ao trocar de conta).
    _sessionStore = InMemorySessionStore();
    _preKeyStore = InMemoryPreKeyStore();
    _signedPreKeyStore = InMemorySignedPreKeyStore();
    _sessoesEstabelecidas.clear();
    _linhasVistas.clear();

    _identityKeyPair = generateIdentityKeyPair();
    _registrationId = generateRegistrationId(false);
    _identityKeyStore =
        InMemoryIdentityKeyStore(_identityKeyPair, _registrationId);

    final preKeys = generatePreKeys(0, 100);
    _signedPreKey = generateSignedPreKey(_identityKeyPair, 0);

    for (final p in preKeys) {
      await _preKeyStore.storePreKey(p.id, p);
    }
    await _signedPreKeyStore.storeSignedPreKey(_signedPreKey.id, _signedPreKey);

    await _publicarMeuBundle(preKeys);
    _escutarMensagensEntrantes();
    await verificarMensagensPendentes();

    _inicializado = true;
  }

  Future<void> encerrarCasulo() async {
    final canal = _canal;
    _canal = null;
    if (canal != null) {
      try {
        await _supabase.removeChannel(canal);
      } catch (_) {}
    }
    _inicializado = false;
  }

  Future<void> reconectarSeNecessario() async {
    if (!_inicializado || _meuUserId.isEmpty) return;
    try {
      _escutarMensagensEntrantes();
      await verificarMensagensPendentes();
    } catch (e) {
      print('Erro ao reconectar o Casulo: $e');
    }
  }

  /// Busca na caixa de correio (Supabase) o que chegou enquanto o app
  /// estava fechado e processa em ordem.
  Future<void> verificarMensagensPendentes() async {
    if (_meuUserId.isEmpty) return;
    try {
      final linhas = await _supabase
          .from('signal_chat_messages')
          .select()
          .eq('recipient_id', _meuUserId)
          .order('created_at', ascending: true);
      for (final l in (linhas as List)) {
        _enfileirar(Map<String, dynamic>.from(l as Map));
      }
      await _fila;
    } catch (e) {
      print('Erro ao verificar mensagens pendentes: $e');
    }
  }

  Future<void> _publicarMeuBundle(List<PreKeyRecord> preKeys) async {
    await _supabase.from('signal_bundles').upsert({
      'user_id': _meuUserId,
      'registration_id': _registrationId,
      'identity_key':
          base64Encode(_identityKeyPair.getPublicKey().serialize()),
      'signed_pre_key_id': _signedPreKey.id,
      'signed_pre_key_public':
          base64Encode(_signedPreKey.getKeyPair().publicKey.serialize()),
      'signed_pre_key_signature': base64Encode(_signedPreKey.signature),
    }, onConflict: 'user_id');

    // As prekeys de execuções anteriores não têm mais chave privada aqui:
    // se ficassem no servidor, alguém poderia consumir uma e a mensagem
    // nunca seria descriptografada.
    await _supabase.from('signal_prekeys').delete().eq('user_id', _meuUserId);

    final linhas = preKeys
        .map((pk) => {
              'user_id': _meuUserId,
              'pre_key_id': pk.id,
              'pre_key_public':
                  base64Encode(pk.getKeyPair().publicKey.serialize()),
            })
        .toList();

    await _supabase.from('signal_prekeys').insert(linhas);
  }

  void _escutarMensagensEntrantes() {
    final antigo = _canal;
    if (antigo != null) {
      _supabase.removeChannel(antigo);
    }
    // O RLS já entrega só as linhas em que sou o destinatário.
    _canal = _supabase
        .channel('signal_chat_inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'signal_chat_messages',
          callback: (PostgresChangePayload payload) {
            final Map<String, dynamic> linha =
                Map<String, dynamic>.from(payload.newRecord);
            if (linha['recipient_id'] == _meuUserId) {
              _enfileirar(linha);
            }
          },
        )
        .subscribe();
  }

  void _enfileirar(Map<String, dynamic> linha) {
    final String? id = linha['id']?.toString();
    if (id == null || _linhasVistas.contains(id)) return;
    _linhasVistas.add(id);
    _serializar<void>(() => _processarLinha(linha)).catchError((Object e) {
      print('Erro ao processar linha $id: $e');
    });
  }

  // ------------------------------------------------------------------ sessão

  String _chaveEmBase64(IdentityKey k) => base64Encode(k.serialize());

  Future<void> _garantirSessao(String userId) async {
    final address = SignalProtocolAddress(userId, 1);

    final bundleRow = await _supabase
        .from('signal_bundles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (bundleRow == null) {
      throw StateError('Usuário $userId ainda não publicou um bundle de chaves.');
    }

    final identityKey = IdentityKey(
        Curve.decodePoint(base64Decode(bundleRow['identity_key']), 0));

    if (await _sessionStore.containsSession(address)) {
      final conhecida = await _identityKeyStore.getIdentity(address);
      if (conhecida != null &&
          _chaveEmBase64(conhecida) == _chaveEmBase64(identityKey)) {
        _sessoesEstabelecidas.add(userId);
        return;
      }
      // O outro lado reabriu o app e gerou chaves novas: descarta a sessão
      // antiga e aceita a nova identidade.
      await _sessionStore.deleteSession(address);
      await _identityKeyStore.saveIdentity(address, identityKey);
      _sessoesEstabelecidas.remove(userId);
    }

    final preKeyResult = await _supabase
        .rpc('consume_one_time_prekey', params: {'target_user_id': userId});

    if (preKeyResult is! List || preKeyResult.isEmpty) {
      throw StateError(
          'Usuário $userId está sem one-time prekeys disponíveis no momento.');
    }

    final preKeyId = preKeyResult.first['pre_key_id'] as int;
    final preKeyPublicB64 = preKeyResult.first['pre_key_public'] as String;
    final preKeyPublic = Curve.decodePoint(base64Decode(preKeyPublicB64), 0);

    final signedPreKeyPublic = Curve.decodePoint(
        base64Decode(bundleRow['signed_pre_key_public']), 0);
    final signedPreKeySignature =
        base64Decode(bundleRow['signed_pre_key_signature']);

    final bundle = PreKeyBundle(
      bundleRow['registration_id'] as int,
      1,
      preKeyId,
      preKeyPublic,
      bundleRow['signed_pre_key_id'] as int,
      signedPreKeyPublic,
      signedPreKeySignature,
      identityKey,
    );

    final sessionBuilder = SessionBuilder(
      _sessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityKeyStore,
      address,
    );

    await sessionBuilder.processPreKeyBundle(bundle);
    _sessoesEstabelecidas.add(userId);
  }

  // ------------------------------------------------------------------ envio

  /// Criptografa [texto] na sessão com [destino] e põe na caixa de correio.
  Future<void> _cifrarEEnviar(String destino, String texto) async {
    await _garantirSessao(destino);

    final address = SignalProtocolAddress(destino, 1);
    final sessionCipher = SessionCipher(
      _sessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityKeyStore,
      address,
    );

    final ciphertextMessage =
        await sessionCipher.encrypt(Uint8List.fromList(utf8.encode(texto)));

    await _supabase.from('signal_chat_messages').insert({
      'sender_id': _meuUserId,
      'recipient_id': destino,
      'payload': base64Encode(ciphertextMessage.serialize()),
      'payload_type': ciphertextMessage.getType(),
    });
  }

  /// Envia uma mensagem de texto. O [msgId] viaja dentro do conteúdo
  /// criptografado e é a chave dos recibos de entrega/leitura.
  Future<void> enviarMensagemSegura(String numeroDestino, String textoPuro,
      {String? msgId}) async {
    if (!_inicializado) {
      throw StateError(
          'SignalCore não inicializado. Chame inicializarCasulo() primeiro.');
    }
    final String id =
        msgId ?? 'm_${DateTime.now().millisecondsSinceEpoch}';
    final String envelope = jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'msg',
      'id': id,
      'text': textoPuro,
    });
    await _serializar<void>(() => _cifrarEEnviar(numeroDestino, envelope));
  }

  Future<void> _enviarReciboInterno(
      String destino, String tipo, List<String> ids) {
    final String envelope = jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'rcpt',
      'k': tipo, // 'delivery' | 'read'
      'ids': ids,
    });
    return _cifrarEEnviar(destino, envelope);
  }

  /// Confirmação de leitura: avisa o remetente (criptografado) que as
  /// mensagens recebidas nesta conversa já foram vistas.
  Future<void> enviarRecibosDeLeitura(String conversa) async {
    if (!_inicializado || conversa.isEmpty) return;

    final List<String> pendentes = SignalLocalStore.getMessages(conversa)
        .where((m) =>
            m['isSelf'] != true &&
            m['receiptable'] == true &&
            m['readReceiptSent'] != true)
        .map((m) => m['msgID'] as String)
        .toList();
    if (pendentes.isEmpty) return;

    await SignalLocalStore.markReadReceiptSent(conversa, pendentes, true);
    await SignalLocalStore.setUnreadCount(conversa, 0);
    try {
      await _serializar<void>(
          () => _enviarReciboInterno(conversa, 'read', pendentes));
    } catch (e) {
      await SignalLocalStore.markReadReceiptSent(conversa, pendentes, false);
      print('Erro ao enviar recibo de leitura: $e');
    }
  }

  // ---------------------------------------------------------------- recebimento

  Future<String> _decifrar(String remetente, Map<String, dynamic> linha) async {
    final Uint8List payloadBytes = base64Decode(linha['payload'] as String);
    final int payloadTipo = (linha['payload_type'] as num).toInt();

    final address = SignalProtocolAddress(remetente, 1);
    final sessionCipher = SessionCipher(
      _sessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityKeyStore,
      address,
    );

    Uint8List textoPlanoBytes;
    if (payloadTipo == CiphertextMessage.prekeyType) {
      final mensagem = PreKeySignalMessage(payloadBytes);
      textoPlanoBytes = await sessionCipher.decrypt(mensagem);
    } else {
      final mensagem = SignalMessage.fromSerialized(payloadBytes);
      textoPlanoBytes = await sessionCipher.decryptFromSignal(mensagem);
    }

    _sessoesEstabelecidas.add(remetente);
    return utf8.decode(textoPlanoBytes);
  }

  Future<void> _apagarLinha(String linhaId) async {
    try {
      // Como no Signal: depois de entregue, nada fica no servidor.
      await _supabase.from('signal_chat_messages').delete().eq('id', linhaId);
    } catch (e) {
      print('Erro ao apagar linha entregue: $e');
    }
  }

  Future<void> _processarLinha(Map<String, dynamic> linha) async {
    final String linhaId = linha['id'].toString();
    final String remetente = linha['sender_id'] as String;

    String textoBruto;
    try {
      textoBruto = await _decifrar(remetente, linha);
    } catch (e) {
      // Reentrega de algo que já foi processado: só limpa o servidor.
      if (e.runtimeType.toString() != 'DuplicateMessageException') {
        print('Não consegui descriptografar mensagem de $remetente: $e');
        await _registrarFalhaDescriptografia(remetente);
      }
      await _apagarLinha(linhaId);
      return;
    }

    try {
      await _tratarConteudo(remetente, textoBruto);
    } catch (e) {
      print('Erro ao tratar conteúdo recebido: $e');
    }
    await _apagarLinha(linhaId);
  }

  Future<void> _tratarConteudo(String remetente, String texto) async {
    Map<String, dynamic>? envelope;
    try {
      final dynamic decodificado = jsonDecode(texto);
      if (decodificado is Map<String, dynamic> && decodificado['t'] is String) {
        envelope = decodificado;
      }
    } catch (_) {}

    // Texto puro: mensagens de versões antigas do app (sem recibos).
    if (envelope == null) {
      await _receberTexto(remetente, texto, msgId: null);
      return;
    }

    switch (envelope['t'] as String) {
      case 'msg':
        await _receberTexto(remetente, (envelope['text'] as String?) ?? '',
            msgId: envelope['id'] as String?);
        break;
      case 'rcpt':
        await _receberRecibo(remetente, envelope);
        break;
      default:
        print('Tipo de conteúdo desconhecido: ${envelope['t']}');
    }
  }

  Future<void> _salvarMensagemRecebida(
    String remetente,
    String msgID,
    String texto, {
    required bool comRecibo,
  }) async {
    final int agora = DateTime.now().millisecondsSinceEpoch;

    // Salva no Hive local — histórico fica só no aparelho, não na nuvem
    await SignalLocalStore.appendMessage(remetente, {
      'msgID': msgID,
      'timestamp': agora,
      'sender': remetente,
      'userID': remetente,
      'groupID': null,
      'isSelf': false,
      'elemType': MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      'text': texto,
      'status': 3,
      'receiptable': comRecibo,
      'readReceiptSent': false,
    });

    final conversas = SignalLocalStore.getConversations()
        .where((c) => c['conversationID'] == remetente)
        .toList();
    final Map<String, dynamic>? anterior =
        conversas.isEmpty ? null : conversas.first;
    final int naoLidas = ((anterior?['unreadCount'] as int?) ?? 0) + 1;

    await SignalLocalStore.upsertConversation({
      'conversationID': remetente,
      'type': 1,
      'userID': remetente,
      'showName': anterior?['showName'],
      'faceUrl': anterior?['faceUrl'],
      'unreadCount': naoLidas,
      'orderkey': agora,
      'lastMessage': {
        'msgID': msgID,
        'timestamp': agora,
        'sender': remetente,
        'isSelf': false,
        'elemType': MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        'text': texto,
      },
    });

    // Notifica a UI pra atualizar o chat em tempo real
    eventBusNewMsg.value = EventBusNewMsg(remetente);
  }

  Future<void> _receberTexto(String remetente, String texto,
      {String? msgId}) async {
    final int agora = DateTime.now().millisecondsSinceEpoch;
    final String msgID = msgId ?? 'in_${remetente}_$agora';

    await _salvarMensagemRecebida(remetente, msgID, texto,
        comRecibo: msgId != null);

    _streamController.add(MensagemDescriptografada(
      remetente: remetente,
      texto: texto,
      timestamp: DateTime.now(),
    ));

    // Entrega confirmada: a mensagem já está guardada neste aparelho.
    if (msgId != null) {
      try {
        await _enviarReciboInterno(remetente, 'delivery', <String>[msgID]);
      } catch (e) {
        print('Erro ao enviar recibo de entrega: $e');
      }
    }
  }

  Future<void> _receberRecibo(
      String remetente, Map<String, dynamic> envelope) async {
    final String tipo = (envelope['k'] as String?) ?? 'delivery';
    final List<String> ids =
        ((envelope['ids'] as List?) ?? <dynamic>[]).whereType<String>().toList();
    if (ids.isEmpty) return;

    final int status =
        tipo == 'read' ? StatusMensagem.lida : StatusMensagem.entregue;
    await SignalLocalStore.upgradeMessageStatus(remetente, ids, status);
    eventBusNewMsg.value = EventBusNewMsg(remetente);
  }

  Future<void> _registrarFalhaDescriptografia(String remetente) async {
    final int agora = DateTime.now().millisecondsSinceEpoch;
    await _salvarMensagemRecebida(
      remetente,
      'fail_${remetente}_$agora',
      '⚠ Não foi possível descriptografar esta mensagem. '
      'Peça para a pessoa enviar de novo.',
      comRecibo: false,
    );
  }

  Future<String> enviarFotoTemporaria(
      List<int> bytes, String nomeArquivo) async {
    final caminho =
        'fotos_temporarias/${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';

    await _supabase.storage.from('fotos_temporarias').uploadBinary(
          caminho,
          Uint8List.fromList(bytes),
        );

    return _supabase.storage
        .from('fotos_temporarias')
        .getPublicUrl(caminho);
  }
}
