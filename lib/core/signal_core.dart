import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:wechat_flutter/core/call_service.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/core/profile_service.dart';
import 'package:wechat_flutter/im/local_store.dart';
import 'package:wechat_flutter/tools/event/im_event.dart';

/// Resultado de cifrar algo na sessão Signal sem enviar pela caixa de correio
/// (usado pelos Momentos, que viajam por Realtime Broadcast).
class CanalCifrado {
  final String payload; // base64
  final int tipo;
  const CanalCifrado(this.payload, this.tipo);
}

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

  static const String _nomeCofre = 'signal_keys';
  static const int _minimoPreKeys = 30;
  static const int _lotePreKeys = 70;

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

  // Persistência das chaves no aparelho (sem isso, ao fechar o app as chaves
  // se perdiam e mensagens recebidas com o app fechado não abriam).
  Box<String>? _cofre;
  final Set<String> _remotos = <String>{};
  final Set<int> _preKeyIds = <int>{};
  final Set<int> _preKeysEnviadas = <int>{};
  int _proximoPreKeyId = 1;

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

  // ------------------------------------------------------------ inicialização

  String _k(String nome) => '$_meuUserId:$nome';

  void _criarStoresVazios() {
    _sessionStore = InMemorySessionStore();
    _preKeyStore = InMemoryPreKeyStore();
    _signedPreKeyStore = InMemorySignedPreKeyStore();
    _remotos.clear();
    _preKeyIds.clear();
    _preKeysEnviadas.clear();
    _proximoPreKeyId = 1;
  }

  Future<void> inicializarCasulo({required String meuUserId}) async {
    if (_inicializado) return;
    _meuUserId = meuUserId;
    _sessoesEstabelecidas.clear();
    _linhasVistas.clear();
    _fila = Future<void>.value();

    _cofre = await Hive.openBox<String>(_nomeCofre);

    // Reaproveita as chaves guardadas neste aparelho; só gera novas na
    // primeira vez (ou se o cofre estiver corrompido).
    _criarStoresVazios();
    final bool restaurado = await _restaurarEstado();
    if (!restaurado) {
      _criarStoresVazios();
      await _gerarChavesNovas();
    }

    await _publicarMeuBundle(primeiraVez: !restaurado);
    _escutarMensagensEntrantes();
    await verificarMensagensPendentes();

    _inicializado = true;
    // Momentos efêmeros (Broadcast + Hive local).
    unawaited(MomentsService.instance.iniciar(meuUserId));
  }

  Future<void> _gerarChavesNovas() async {
    _identityKeyPair = generateIdentityKeyPair();
    _registrationId = generateRegistrationId(false);
    _identityKeyStore =
        InMemoryIdentityKeyStore(_identityKeyPair, _registrationId);

    _signedPreKey = generateSignedPreKey(_identityKeyPair, 0);
    await _signedPreKeyStore.storeSignedPreKey(_signedPreKey.id, _signedPreKey);

    await _gerarPreKeys(100);

    final cofre = _cofre!;
    await cofre.put(
        _k('identity'), base64Encode(_identityKeyPair.serialize()));
    await cofre.put(_k('regid'), _registrationId.toString());
    await cofre.put(_k('signed'), base64Encode(_signedPreKey.serialize()));
    await _persistirEstado();
  }

  Future<void> _gerarPreKeys(int quantidade) async {
    final int inicio = _proximoPreKeyId < 1 ? 1 : _proximoPreKeyId;
    final novas = generatePreKeys(inicio, quantidade);
    for (final p in novas) {
      await _preKeyStore.storePreKey(p.id, p);
      _preKeyIds.add(p.id);
    }
    _proximoPreKeyId = inicio + quantidade;
  }

  /// Lê as chaves/sessões salvas. Retorna false se não há nada (ou se falhar).
  Future<bool> _restaurarEstado() async {
    final cofre = _cofre!;
    final String? identidade = cofre.get(_k('identity'));
    final String? regId = cofre.get(_k('regid'));
    final String? assinada = cofre.get(_k('signed'));
    if (identidade == null || regId == null || assinada == null) return false;

    try {
      _identityKeyPair =
          IdentityKeyPair.fromSerialized(base64Decode(identidade));
      _registrationId = int.parse(regId);
      _identityKeyStore =
          InMemoryIdentityKeyStore(_identityKeyPair, _registrationId);

      _signedPreKey = SignedPreKeyRecord.fromSerialized(base64Decode(assinada));
      await _signedPreKeyStore.storeSignedPreKey(
          _signedPreKey.id, _signedPreKey);

      final Map<String, dynamic> prekeys =
          (jsonDecode(cofre.get(_k('prekeys')) ?? '{}') as Map)
              .cast<String, dynamic>();
      for (final e in prekeys.entries) {
        final int id = int.parse(e.key);
        await _preKeyStore.storePreKey(
            id, PreKeyRecord.fromBuffer(base64Decode(e.value as String)));
        _preKeyIds.add(id);
      }

      _preKeysEnviadas.addAll(
          ((jsonDecode(cofre.get(_k('enviadas')) ?? '[]')) as List)
              .map((e) => (e as num).toInt()));
      _proximoPreKeyId =
          int.tryParse(cofre.get(_k('proximoPreKeyId')) ?? '') ?? 1;

      _remotos.addAll(((jsonDecode(cofre.get(_k('remotos')) ?? '[]')) as List)
          .cast<String>());

      final Map<String, dynamic> sessoes =
          (jsonDecode(cofre.get(_k('sessoes')) ?? '{}') as Map)
              .cast<String, dynamic>();
      for (final e in sessoes.entries) {
        await _sessionStore.storeSession(
          SignalProtocolAddress(e.key, 1),
          SessionRecord.fromSerialized(base64Decode(e.value as String)),
        );
      }

      final Map<String, dynamic> identidades =
          (jsonDecode(cofre.get(_k('identidades')) ?? '{}') as Map)
              .cast<String, dynamic>();
      for (final e in identidades.entries) {
        await _identityKeyStore.saveIdentity(
          SignalProtocolAddress(e.key, 1),
          IdentityKey.fromBytes(base64Decode(e.value as String), 0),
        );
      }
      return true;
    } catch (e) {
      print('Cofre de chaves ilegível, gerando chaves novas: $e');
      return false;
    }
  }

  /// Grava no aparelho o estado atual (sessões, identidades, prekeys).
  /// Chamado ANTES de enviar e ANTES de apagar a mensagem do servidor, pra
  /// nunca perder o avanço do ratchet se o app fechar no meio.
  Future<void> _persistirEstado() async {
    final cofre = _cofre;
    if (cofre == null) return;

    final Map<String, String> sessoes = <String, String>{};
    final Map<String, String> identidades = <String, String>{};
    for (final String r in _remotos) {
      final address = SignalProtocolAddress(r, 1);
      if (await _sessionStore.containsSession(address)) {
        final registro = await _sessionStore.loadSession(address);
        sessoes[r] = base64Encode(registro.serialize());
      }
      final identidade = await _identityKeyStore.getIdentity(address);
      if (identidade != null) {
        identidades[r] = base64Encode(identidade.serialize());
      }
    }

    // One-time prekeys que ainda existem (as usadas foram removidas pela lib).
    final Map<String, String> prekeys = <String, String>{};
    final List<int> restantes = <int>[];
    for (final int id in _preKeyIds) {
      if (await _preKeyStore.containsPreKey(id)) {
        final registro = await _preKeyStore.loadPreKey(id);
        prekeys['$id'] = base64Encode(registro.serialize());
        restantes.add(id);
      }
    }
    _preKeyIds
      ..clear()
      ..addAll(restantes);

    await cofre.putAll(<String, String>{
      _k('sessoes'): jsonEncode(sessoes),
      _k('identidades'): jsonEncode(identidades),
      _k('prekeys'): jsonEncode(prekeys),
      _k('enviadas'): jsonEncode(_preKeysEnviadas.toList()),
      _k('proximoPreKeyId'): _proximoPreKeyId.toString(),
      _k('remotos'): jsonEncode(_remotos.toList()),
    });
  }

  Future<void> encerrarCasulo() async {
    await MomentsService.instance.parar();
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
      await MomentsService.instance.reconectar();
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

  Future<void> _publicarMeuBundle({required bool primeiraVez}) async {
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

    if (primeiraVez) {
      // Chaves novas: as prekeys antigas do servidor não servem mais.
      await _supabase.from('signal_prekeys').delete().eq('user_id', _meuUserId);
      _preKeysEnviadas.clear();
    } else {
      // Chaves reaproveitadas: só repõe se o estoque do servidor baixou.
      final restantes = await _supabase
          .from('signal_prekeys')
          .select('pre_key_id')
          .eq('user_id', _meuUserId);
      if ((restantes as List).length < _minimoPreKeys) {
        await _gerarPreKeys(_lotePreKeys);
      }
    }

    await _enviarPreKeysNovas();
    await _persistirEstado();
  }

  /// Sobe só as prekeys que nunca foram enviadas (as já usadas por outros não
  /// voltam pro servidor, pra uma mesma prekey nunca ser usada duas vezes).
  Future<void> _enviarPreKeysNovas() async {
    final List<Map<String, dynamic>> linhas = <Map<String, dynamic>>[];
    final List<int> ids = <int>[];
    for (final int id in _preKeyIds) {
      if (_preKeysEnviadas.contains(id)) continue;
      if (!await _preKeyStore.containsPreKey(id)) continue;
      final registro = await _preKeyStore.loadPreKey(id);
      linhas.add(<String, dynamic>{
        'user_id': _meuUserId,
        'pre_key_id': id,
        'pre_key_public':
            base64Encode(registro.getKeyPair().publicKey.serialize()),
      });
      ids.add(id);
    }
    if (linhas.isEmpty) return;
    await _supabase.from('signal_prekeys').insert(linhas);
    _preKeysEnviadas.addAll(ids);
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
        _remotos.add(userId);
        return;
      }
      // O outro lado trocou de chaves (reinstalou o app): descarta a sessão
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
    _remotos.add(userId);
  }

  // ------------------------------------------------------------------ envio

  /// Criptografa [texto] na sessão com [destino] e põe na caixa de correio.
  /// [push] = false nos recibos: eles não geram notificação no aparelho.
  Future<void> _cifrarEEnviar(String destino, String texto,
      {bool push = true}) async {
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

    // Estado salvo antes de enviar: se o app fechar agora, o ratchet não perde
    // o passo já dado.
    await _persistirEstado();

    await _supabase.from('signal_chat_messages').insert({
      'sender_id': _meuUserId,
      'recipient_id': destino,
      'payload': base64Encode(ciphertextMessage.serialize()),
      'payload_type': ciphertextMessage.getType(),
      'push': push,
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
    // Como no Signal: a Profile Key segue dentro da mensagem E2E, para o
    // contato poder decifrar a minha foto de perfil.
    final Uint8List chavePerfil =
        await ProfileService.instance.minhaChave(_meuUserId);
    final String envelope = jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'msg',
      'id': id,
      'text': textoPuro,
      'pk': base64Encode(chavePerfil),
    });
    await _serializar<void>(() => _cifrarEEnviar(numeroDestino, envelope));
  }

  /// Entrega a minha Profile Key (criptografada, sem notificação) a quem já
  /// conversa comigo. Chamado depois de definir/alterar a foto de perfil.
  Future<void> compartilharChaveDePerfil() async {
    if (!_inicializado) return;
    final Uint8List chave =
        await ProfileService.instance.minhaChave(_meuUserId);
    final String envelope = jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'pk',
      'pk': base64Encode(chave),
    });

    final Set<String> destinos = <String>{
      for (final Map<String, dynamic> c in SignalLocalStore.getConversations())
        if (c['groupID'] == null && c['conversationID'] is String)
          c['conversationID'] as String,
      ..._remotos,
    }..remove(_meuUserId);

    for (final String destino in destinos) {
      try {
        await _serializar<void>(
            () => _cifrarEEnviar(destino, envelope, push: false));
      } catch (e) {
        print('Não consegui enviar a chave de perfil para $destino: $e');
      }
    }
  }

  Future<void> _guardarChaveDePerfil(String remetente, dynamic bruto) async {
    if (bruto is! String || bruto.isEmpty) return;
    try {
      await ProfileService.instance.guardarChaveDoContato(
          remetente, Uint8List.fromList(base64Decode(bruto)));
    } catch (e) {
      print('Chave de perfil inválida de $remetente: $e');
    }
  }

  /// Envia o convite de uma chamada pela caixa de mensagens do chat (cifrado).
  /// O aviso de "Nova mensagem" do destinatário acorda o app dele.
  Future<void> enviarConviteChamada(String destino, String envelopeJson) {
    return _serializar<void>(() => _cifrarEEnviar(destino, envelopeJson));
  }

  /// Cifra [texto] na sessão com [destino] SEM gravar nada no servidor.
  /// Quem chama entrega o resultado por Realtime Broadcast.
  Future<CanalCifrado> cifrarParaCanal(String destino, String texto) {
    return _serializar<CanalCifrado>(() async {
      await _garantirSessao(destino);
      final address = SignalProtocolAddress(destino, 1);
      final sessionCipher = SessionCipher(
        _sessionStore,
        _preKeyStore,
        _signedPreKeyStore,
        _identityKeyStore,
        address,
      );
      final mensagem =
          await sessionCipher.encrypt(Uint8List.fromList(utf8.encode(texto)));
      await _persistirEstado();
      return CanalCifrado(
          base64Encode(mensagem.serialize()), mensagem.getType());
    });
  }

  /// Abre algo cifrado por [cifrarParaCanal] do outro lado. Se [remetente]
  /// não for quem diz ser, a descriptografia falha.
  Future<String> decifrarDeCanal(
      String remetente, String payloadBase64, int tipo) {
    return _serializar<String>(() => _decifrar(remetente, <String, dynamic>{
          'payload': payloadBase64,
          'payload_type': tipo,
        }));
  }

  Future<void> _enviarReciboInterno(
      String destino, String tipo, List<String> ids) {
    final String envelope = jsonEncode(<String, dynamic>{
      'v': 1,
      't': 'rcpt',
      'k': tipo, // 'delivery' | 'read'
      'ids': ids,
    });
    return _cifrarEEnviar(destino, envelope, push: false);
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
    _remotos.add(remetente);
    // Salvo antes de apagar a linha do servidor: depois disso não há volta.
    await _persistirEstado();
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
        await _guardarChaveDePerfil(remetente, envelope['pk']);
        await _receberTexto(remetente, (envelope['text'] as String?) ?? '',
            msgId: envelope['id'] as String?);
        break;
      case 'pk':
        await _guardarChaveDePerfil(remetente, envelope['pk']);
        eventBusNewMsg.value = EventBusNewMsg(remetente);
        break;
      case 'rcpt':
        await _receberRecibo(remetente, envelope);
        break;
      case 'call':
        // Convite de chamada de voz/vídeo (cifrado, pela caixa do chat).
        await CallService.instance.aoReceberConvite(remetente, envelope);
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
