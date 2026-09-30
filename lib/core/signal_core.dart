import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:wechat_flutter/config/const.dart';

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

class SignalCore {
  static final SignalCore _instance = SignalCore._internal();
  factory SignalCore() => _instance;
  SignalCore._internal();

  bool _inicializado = false;
  bool _supabaseInicializado = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;
  String _meuUserId = '';

  late IdentityKeyPair _identityKeyPair;
  late int _registrationId;
  late SignedPreKeyRecord _signedPreKey;

  final InMemorySessionStore _sessionStore = InMemorySessionStore();
  final InMemoryPreKeyStore _preKeyStore = InMemoryPreKeyStore();
  final InMemorySignedPreKeyStore _signedPreKeyStore = InMemorySignedPreKeyStore();
  late InMemoryIdentityKeyStore _identityKeyStore;

  final Set<String> _sessoesEstabelecidas = {};

  final StreamController<MensagemDescriptografada> _streamController =
      StreamController<MensagemDescriptografada>.broadcast();

  Stream<MensagemDescriptografada> get mensagensRecebidas => _streamController.stream;
  bool get estaInicializado => _inicializado;
  String get meuUserId => _meuUserId;

  SupabaseClient get _supabase => Supabase.instance.client;
  CollectionReference<Map<String, dynamic>> get _mensagensFirestore =>
      FirebaseFirestore.instance.collection('signal_chat_messages');

  /// Chame DEPOIS que o número foi verificado com sucesso — gera as chaves
  /// do Casulo, publica o bundle público no Supabase (auth/chaves) e
  /// começa a escutar mensagens novas no Firestore (transporte).
  Future<void> inicializarCasulo({required String meuUserId}) async {
    if (_inicializado) return;
    _meuUserId = meuUserId;

    if (!_supabaseInicializado) {
      if (signalSupabaseUrl.isEmpty || signalSupabaseAnonKey.isEmpty) {
        throw StateError(
          'signalSupabaseUrl/signalSupabaseAnonKey vazios — confirme os '
          'dart-defines SIGNAL_SUPABASE_URL e SIGNAL_SUPABASE_ANON_KEY.',
        );
      }
      await Supabase.initialize(
        url: signalSupabaseUrl,
        anonKey: signalSupabaseAnonKey,
      );
      _supabaseInicializado = true;
    }

    _identityKeyPair = generateIdentityKeyPair();
    _registrationId = generateRegistrationId(false);
    _identityKeyStore = InMemoryIdentityKeyStore(_identityKeyPair, _registrationId);

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
    await _firestoreSub?.cancel();
    _inicializado = false;
  }

  Future<void> reconectarSeNecessario() async {
    if (!_inicializado || _meuUserId.isEmpty) return;
    try {
      await _firestoreSub?.cancel();
      _escutarMensagensEntrantes();
      await verificarMensagensPendentes();
    } catch (e) {
      print('Erro ao reconectar o Casulo: $e');
    }
  }

  /// Busca direto no Firestore qualquer mensagem que já esteja esperando,
  /// caso o listener não tenha notificado (ex: app estava fechado).
  Future<void> verificarMensagensPendentes() async {
    if (_meuUserId.isEmpty) return;
    try {
      final snapshot =
          await _mensagensFirestore.where('recipientId', isEqualTo: _meuUserId).get();
      for (final doc in snapshot.docs) {
        await _processarMensagemEntrante(doc.id, doc.data());
      }
    } catch (e) {
      print('Erro ao verificar mensagens pendentes: $e');
    }
  }

  Future<void> _publicarMeuBundle(List<PreKeyRecord> preKeys) async {
    await _supabase.from('signal_bundles').upsert({
      'user_id': _meuUserId,
      'registration_id': _registrationId,
      'identity_key': base64Encode(_identityKeyPair.getPublicKey().serialize()),
      'signed_pre_key_id': _signedPreKey.id,
      'signed_pre_key_public':
          base64Encode(_signedPreKey.getKeyPair().publicKey.serialize()),
      'signed_pre_key_signature': base64Encode(_signedPreKey.signature),
    });

    final linhas = preKeys
        .map((pk) => {
              'user_id': _meuUserId,
              'pre_key_id': pk.id,
              'pre_key_public': base64Encode(pk.getKeyPair().publicKey.serialize()),
            })
        .toList();

    await _supabase.from('signal_prekeys').insert(linhas);
  }

  void _escutarMensagensEntrantes() {
    _firestoreSub = _mensagensFirestore
        .where('recipientId', isEqualTo: _meuUserId)
        .snapshots()
        .listen((snapshot) {
      for (final mudanca in snapshot.docChanges) {
        if (mudanca.type == DocumentChangeType.added) {
          _processarMensagemEntrante(mudanca.doc.id, mudanca.doc.data()!);
        }
      }
    });
  }

  Future<void> _garantirSessao(String userId) async {
    if (_sessoesEstabelecidas.contains(userId)) return;

    final address = SignalProtocolAddress(userId, 1);
    if (await _sessionStore.containsSession(address)) {
      _sessoesEstabelecidas.add(userId);
      return;
    }

    final bundleRow =
        await _supabase.from('signal_bundles').select().eq('user_id', userId).maybeSingle();

    if (bundleRow == null) {
      throw StateError('Usuário $userId ainda não publicou um bundle de chaves.');
    }

    final preKeyResult =
        await _supabase.rpc('consume_one_time_prekey', params: {'target_user_id': userId});

    if (preKeyResult is! List || preKeyResult.isEmpty) {
      throw StateError(
        'Usuário $userId está sem one-time prekeys disponíveis no momento.',
      );
    }

    final preKeyId = preKeyResult.first['pre_key_id'] as int;
    final preKeyPublicB64 = preKeyResult.first['pre_key_public'] as String;
    final preKeyPublic = Curve.decodePoint(base64Decode(preKeyPublicB64), 0);

    final identityKey =
        IdentityKey(Curve.decodePoint(base64Decode(bundleRow['identity_key']), 0));
    final signedPreKeyPublic =
        Curve.decodePoint(base64Decode(bundleRow['signed_pre_key_public']), 0);
    final signedPreKeySignature = base64Decode(bundleRow['signed_pre_key_signature']);

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

  Future<void> enviarMensagemSegura(String numeroDestino, String textoPuro) async {
    if (!_inicializado) {
      throw StateError('SignalCore não inicializado. Chame inicializarCasulo() primeiro.');
    }

    await _garantirSessao(numeroDestino);

    final address = SignalProtocolAddress(numeroDestino, 1);
    final sessionCipher = SessionCipher(
      _sessionStore,
      _preKeyStore,
      _signedPreKeyStore,
      _identityKeyStore,
      address,
    );

    final ciphertextMessage =
        await sessionCipher.encrypt(Uint8List.fromList(utf8.encode(textoPuro)));

    await _mensagensFirestore.add({
      'senderId': _meuUserId,
      'recipientId': numeroDestino,
      'payload': base64Encode(ciphertextMessage.serialize()),
      'payloadType': ciphertextMessage.getType(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _processarMensagemEntrante(String docId, Map<String, dynamic> dados) async {
    try {
      final String remetente = dados['senderId'] as String;
      final Uint8List payloadBytes = base64Decode(dados['payload'] as String);
      final int payloadTipo = dados['payloadType'] as int;

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
      final textoPlano = utf8.decode(textoPlanoBytes);

      _streamController.add(
        MensagemDescriptografada(
          remetente: remetente,
          texto: textoPlano,
          timestamp: DateTime.now(),
        ),
      );

      // Apaga do Firestore assim que descriptografado — nenhuma mensagem
      // fica salva na nuvem. Quem guarda o histórico é o Hive local.
      await _mensagensFirestore.doc(docId).delete();
    } catch (e) {
      print('Erro ao processar mensagem entrante: $e');
    }
  }
}
