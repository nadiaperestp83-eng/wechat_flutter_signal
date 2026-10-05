import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/core/media_crypto.dart';
import 'package:wechat_flutter/im/local_store.dart';

/// Foto de perfil no modelo do Signal.
///
///  1. Cada usuário tem uma Profile Key (32 bytes) que nasce e fica só nos
///     aparelhos.
///  2. A foto é cifrada no aparelho com essa chave (AES-256-GCM) e o Supabase
///     Storage guarda apenas o blob ilegível, num caminho aleatório.
///  3. A Profile Key é entregue a cada contato DENTRO de mensagens Signal
///     (E2E). Com ela, o contato baixa o blob e decifra localmente.
///
/// O servidor nunca vê a imagem nem a chave.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  static const String _bucket = 'signal_profiles';
  static const String _nomeBox = 'signal_profile_media';
  static const Duration _intervaloChecagem = Duration(minutes: 5);

  /// Sobe a cada mudança de foto/chave. Os widgets de avatar escutam isto.
  final ValueNotifier<int> versao = ValueNotifier<int>(0);

  Box<dynamic>? _box;
  final Map<String, DateTime> _ultimaChecagem = <String, DateTime>{};
  final Map<String, Future<Uint8List?>> _carregando =
      <String, Future<Uint8List?>>{};

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Box<dynamic>> iniciar() async {
    return _box ??= await Hive.openBox<dynamic>(_nomeBox);
  }

  void _avisarMudanca() => versao.value = versao.value + 1;

  // ------------------------------------------------------------------ chaves

  /// Profile Key de [userId] (a minha ou a de um contato). Só existe aqui
  /// no aparelho.
  Uint8List? chaveDe(String userId) {
    final dynamic bruto = _box?.get('key:$userId');
    if (bruto is! String) return null;
    try {
      return Uint8List.fromList(base64Decode(bruto));
    } catch (_) {
      return null;
    }
  }

  /// Devolve a minha Profile Key, criando uma na primeira vez.
  Future<Uint8List> minhaChave(String meuId) async {
    final Box<dynamic> box = await iniciar();
    final Uint8List? existente = chaveDe(meuId);
    if (existente != null) return existente;
    final Uint8List nova = MediaCrypto.gerarChave();
    await box.put('key:$meuId', base64Encode(nova));
    return nova;
  }

  /// Guarda a Profile Key recebida (por mensagem Signal) de um contato.
  Future<void> guardarChaveDoContato(String contatoId, Uint8List chave) async {
    if (chave.length != MediaCrypto.tamanhoChave) return;
    final Box<dynamic> box = await iniciar();
    final Uint8List? atual = chaveDe(contatoId);
    if (atual != null && listEquals(atual, chave)) return;

    await box.put('key:$contatoId', base64Encode(chave));
    // Chave nova: a foto em cache (se houver) não vale mais.
    await box.delete('img:$contatoId');
    await box.delete('path:$contatoId');
    _ultimaChecagem.remove(contatoId);
    _avisarMudanca();
  }

  // ------------------------------------------------------------------- leitura

  /// Foto já decifrada e guardada no aparelho (sem rede).
  Uint8List? fotoEmCache(String userId) {
    final dynamic v = _box?.get('img:$userId');
    return v is Uint8List ? v : null;
  }

  /// Retorna a foto de [userId]: usa o cache e confere o servidor no máximo
  /// a cada poucos minutos. Sem Profile Key do contato, não há como decifrar.
  Future<Uint8List?> carregarFoto(String userId, {bool forcar = false}) {
    final Future<Uint8List?>? emAndamento = _carregando[userId];
    if (emAndamento != null) return emAndamento;

    final Future<Uint8List?> futuro =
        _carregarFoto(userId, forcar: forcar).whenComplete(() {
      _carregando.remove(userId);
    });
    _carregando[userId] = futuro;
    return futuro;
  }

  Future<Uint8List?> _carregarFoto(String userId, {required bool forcar}) async {
    final Box<dynamic> box = await iniciar();
    final Uint8List? emCache = fotoEmCache(userId);
    final Uint8List? chave = chaveDe(userId);
    if (chave == null) return null;

    final DateTime agora = DateTime.now();
    final DateTime? ultima = _ultimaChecagem[userId];
    if (!forcar &&
        emCache != null &&
        ultima != null &&
        agora.difference(ultima) < _intervaloChecagem) {
      return emCache;
    }

    try {
      final dynamic linha = await _supabase
          .from('signal_accounts')
          .select('avatar_path')
          .eq('phone', userId)
          .maybeSingle();
      _ultimaChecagem[userId] = agora;

      final String? caminho =
          linha == null ? null : (linha as Map)['avatar_path'] as String?;
      if (caminho == null || caminho.isEmpty) {
        if (emCache != null) {
          await box.delete('img:$userId');
          await box.delete('path:$userId');
          _avisarMudanca();
        }
        return null;
      }

      if (emCache != null && box.get('path:$userId') == caminho) {
        return emCache;
      }

      final Uint8List blob =
          await _supabase.storage.from(_bucket).download(caminho);
      final Uint8List foto = MediaCrypto.decifrar(chave, blob);
      await box.put('img:$userId', foto);
      await box.put('path:$userId', caminho);
      _avisarMudanca();
      return foto;
    } catch (e) {
      debugPrint('[ProfileService] não consegui carregar a foto de $userId: $e');
      return emCache;
    }
  }

  // ------------------------------------------------------------------- escrita

  /// Cifra [bytes] com a minha Profile Key, sobe o blob e publica o caminho.
  /// Lança exceção em caso de falha (o chamador mostra o erro).
  Future<void> definirMinhaFoto(String meuId, Uint8List bytes) async {
    final Box<dynamic> box = await iniciar();
    final Uint8List chave = await minhaChave(meuId);
    final Uint8List blob = MediaCrypto.cifrar(chave, bytes);

    // Nome opaco: o servidor não aprende nada sobre a imagem.
    final String nome = MediaCrypto.bytesAleatorios(16)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final String caminho = '${meuId.toLowerCase()}/$nome.bin';
    final dynamic anterior = box.get('path:$meuId');

    await _supabase.storage.from(_bucket).uploadBinary(
          caminho,
          blob,
          fileOptions: const FileOptions(
            contentType: 'application/octet-stream',
            upsert: false,
          ),
        );

    try {
      await _supabase.from('signal_accounts').upsert(<String, dynamic>{
        'phone': meuId,
        'avatar_path': caminho,
        // Some qualquer URL pública antiga: a foto agora só existe cifrada.
        'avatar_url': null,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      try {
        await _supabase.storage.from(_bucket).remove(<String>[caminho]);
      } catch (_) {}
      rethrow;
    }

    if (anterior is String && anterior.isNotEmpty && anterior != caminho) {
      try {
        await _supabase.storage.from(_bucket).remove(<String>[anterior]);
      } catch (_) {}
    }

    await box.put('img:$meuId', bytes);
    await box.put('path:$meuId', caminho);
    await _salvarPerfilLocal(meuId, caminho);
    _ultimaChecagem[meuId] = DateTime.now();
    _avisarMudanca();
  }

  /// Remove a minha foto (servidor e aparelho).
  Future<void> removerMinhaFoto(String meuId) async {
    final Box<dynamic> box = await iniciar();
    final dynamic anterior = box.get('path:$meuId');

    await _supabase.from('signal_accounts').upsert(<String, dynamic>{
      'phone': meuId,
      'avatar_path': null,
      'avatar_url': null,
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (anterior is String && anterior.isNotEmpty) {
      try {
        await _supabase.storage.from(_bucket).remove(<String>[anterior]);
      } catch (_) {}
    }

    await box.delete('img:$meuId');
    await box.delete('path:$meuId');
    await _salvarPerfilLocal(meuId, null);
    _ultimaChecagem.remove(meuId);
    _avisarMudanca();
  }

  Future<void> _salvarPerfilLocal(String meuId, String? caminho) async {
    final Map<String, dynamic> perfil =
        SignalLocalStore.getSelfProfile(meuId) ?? <String, dynamic>{};
    if (caminho == null) {
      perfil.remove('avatarPath');
    } else {
      perfil['avatarPath'] = caminho;
    }
    perfil.remove('avatarUrl');
    await SignalLocalStore.saveSelfProfile(meuId, perfil);
  }
}
