import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wechat_flutter/core/media_crypto.dart';

/// Erro mostrado ao usuário (frase errada, arquivo inválido...).
class BackupInvalido implements Exception {
  final String mensagem;
  const BackupInvalido(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Deriva a chave AES-256 da frase (PBKDF2-HMAC-SHA256). Roda num isolate.
Uint8List _derivarChave(Map<String, dynamic> a) {
  final Uint8List sal = a['sal'] as Uint8List;
  final int iteracoes = a['iter'] as int;
  final String frase = a['frase'] as String;
  final PBKDF2KeyDerivator derivador =
      PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(sal, iteracoes, 32));
  return derivador.process(Uint8List.fromList(utf8.encode(frase)));
}

/// Backup local cifrado por frase de recuperação (sem nuvem).
///
/// O arquivo guarda as chaves e sessões do Signal, as conversas, as mensagens,
/// os contatos e as chaves de perfil deste aparelho. Tudo é compactado e
/// cifrado com AES-256-GCM; a chave vem da frase de recuperação (30 dígitos)
/// por PBKDF2. Sem a frase, o arquivo é ilegível.
///
/// Os Momentos (que somem em 24 h) não entram no backup.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String _magia = 'KKBK1';
  static const int _iteracoes = 100000;

  /// Caixas de texto do Hive (mensagens, conversas, contatos e chaves).
  static const List<String> _caixasTexto = <String>[
    'signal_messages_box',
    'signal_conversations_box',
    'signal_contacts_box',
    'signal_keys',
  ];
  static const String _caixaPerfil = 'signal_profile_media';

  static const String _prefAtivo = 'backup_ativo';
  static const String _prefFrase = 'backup_frase';
  static const String _prefUltimo = 'backup_ultimo_ms';
  static const String _prefContaRestaurada = 'backup_conta_restaurada';

  final Random _aleatorio = Random.secure();

  // ------------------------------------------------------------ configuração

  Future<bool> estaAtivo() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getBool(_prefAtivo) ?? false;
  }

  Future<String?> frase() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getString(_prefFrase);
  }

  Future<DateTime?> ultimoBackup() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int? ms = p.getInt(_prefUltimo);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Liga os backups e devolve a frase de recuperação (30 dígitos em grupos
  /// de 5). Se já havia uma, mantém a mesma.
  Future<String> ativar() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    String? atual = p.getString(_prefFrase);
    if (atual == null || atual.isEmpty) {
      atual = _gerarFrase();
      await p.setString(_prefFrase, atual);
    }
    await p.setBool(_prefAtivo, true);
    return atual;
  }

  Future<void> desativar() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_prefAtivo, false);
    await p.remove(_prefFrase);
    await p.remove(_prefUltimo);
  }

  String _gerarFrase() {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 30; i++) {
      if (i > 0 && i % 5 == 0) sb.write(' ');
      sb.write(_aleatorio.nextInt(10));
    }
    return sb.toString();
  }

  String _normalizar(String frase) => frase.replaceAll(RegExp(r'[^0-9]'), '');

  // --------------------------------------------------------- conta restaurada

  /// E-mail da conta do último backup restaurado (para preencher o login).
  Future<String?> contaRestaurada() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getString(_prefContaRestaurada);
  }

  Future<void> limparContaRestaurada() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_prefContaRestaurada);
  }

  // ----------------------------------------------------------------- criar

  /// Gera o arquivo de backup (bytes) com a frase guardada.
  Future<Uint8List> gerarArquivo(String conta) async {
    final String? f = await frase();
    if (f == null || f.isEmpty) {
      throw const BackupInvalido('Ative os backups primeiro.');
    }
    return _montar(conta, f);
  }

  /// Chamar depois que o arquivo foi salvo de verdade.
  Future<void> registrarBackupSalvo() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt(_prefUltimo, DateTime.now().millisecondsSinceEpoch);
  }

  Future<Uint8List> _montar(String conta, String frase) async {
    final String sufixo = conta.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final Map<String, dynamic> caixas = <String, dynamic>{};

    for (final String nome in _caixasTexto) {
      final Box<String> box = await _abrirTexto(nome);
      caixas[nome] = <String, dynamic>{
        't': 's',
        'd': <String, String>{
          for (final dynamic k in box.keys) '$k': box.get(k) ?? '',
        },
      };
    }
    for (final String nome in <String>[_caixaPerfil, 'signal_call_log_$sufixo']) {
      final Box<dynamic> box = await _abrirDinamica(nome);
      caixas[nome] = <String, dynamic>{
        't': 'd',
        'd': <String, dynamic>{
          for (final dynamic k in box.keys) '$k': _codificar(box.get(k)),
        },
      };
    }

    final Map<String, dynamic> documento = <String, dynamic>{
      'v': 1,
      'conta': conta.trim().toLowerCase(),
      'criado': DateTime.now().millisecondsSinceEpoch,
      'caixas': caixas,
    };

    final Uint8List compactado = Uint8List.fromList(
        gzip.encode(utf8.encode(jsonEncode(documento))));

    final Uint8List sal = MediaCrypto.bytesAleatorios(16);
    final Uint8List chave = await compute(_derivarChave, <String, dynamic>{
      'sal': sal,
      'iter': _iteracoes,
      'frase': _normalizar(frase),
    });
    final Uint8List blob = MediaCrypto.cifrar(chave, compactado);

    final BytesBuilder saida = BytesBuilder(copy: false);
    saida.add(utf8.encode(_magia));
    saida.add(sal);
    final ByteData iter = ByteData(4)..setUint32(0, _iteracoes);
    saida.add(iter.buffer.asUint8List());
    saida.add(blob);
    return saida.toBytes();
  }

  // -------------------------------------------------------------- restaurar

  /// Decifra [arquivo] com [fraseDigitada] e grava tudo no Hive deste aparelho.
  /// Devolve o e-mail da conta do backup. Chamar ANTES de entrar na conta.
  Future<String> restaurar(Uint8List arquivo, String fraseDigitada) async {
    final int cab = _magia.length;
    if (arquivo.length < cab + 16 + 4 + 28 ||
        utf8.decode(arquivo.sublist(0, cab), allowMalformed: true) != _magia) {
      throw const BackupInvalido('Este arquivo não é um backup do Kakaô.');
    }

    final Uint8List sal = Uint8List.fromList(arquivo.sublist(cab, cab + 16));
    final int iteracoes =
        ByteData.sublistView(arquivo, cab + 16, cab + 20).getUint32(0);
    final Uint8List blob = Uint8List.fromList(arquivo.sublist(cab + 20));

    if (iteracoes < 10000 || iteracoes > 2000000) {
      throw const BackupInvalido('Arquivo de backup inválido.');
    }
    final String frase = _normalizar(fraseDigitada);
    if (frase.length != 30) {
      throw const BackupInvalido('A frase de recuperação tem 30 dígitos.');
    }

    final Uint8List chave = await compute(_derivarChave, <String, dynamic>{
      'sal': sal,
      'iter': iteracoes,
      'frase': frase,
    });

    final Map<String, dynamic> documento;
    try {
      final Uint8List compactado = MediaCrypto.decifrar(chave, blob);
      documento = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(gzip.decode(compactado))) as Map);
    } catch (_) {
      throw const BackupInvalido(
          'Frase de recuperação incorreta ou arquivo danificado.');
    }

    final String conta = (documento['conta'] as String?) ?? '';
    final Map<String, dynamic> caixas =
        Map<String, dynamic>.from(documento['caixas'] as Map);

    for (final MapEntry<String, dynamic> e in caixas.entries) {
      final Map<String, dynamic> info = Map<String, dynamic>.from(e.value as Map);
      final Map<String, dynamic> dados =
          Map<String, dynamic>.from(info['d'] as Map);

      if (info['t'] == 's') {
        final Box<String> box = await _abrirTexto(e.key);
        await box.putAll(<String, String>{
          for (final MapEntry<String, dynamic> d in dados.entries)
            d.key: d.value as String,
        });
      } else {
        final Box<dynamic> box = await _abrirDinamica(e.key);
        for (final MapEntry<String, dynamic> d in dados.entries) {
          await box.put(d.key, _decodificar(d.value));
        }
      }
    }

    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_prefContaRestaurada, conta);
    return conta;
  }

  // ------------------------------------------------------------------ apoio

  Future<Box<String>> _abrirTexto(String nome) async {
    return Hive.isBoxOpen(nome)
        ? Hive.box<String>(nome)
        : await Hive.openBox<String>(nome);
  }

  Future<Box<dynamic>> _abrirDinamica(String nome) async {
    return Hive.isBoxOpen(nome)
        ? Hive.box<dynamic>(nome)
        : await Hive.openBox<dynamic>(nome);
  }

  /// Converte um valor do Hive em algo que o JSON aceita.
  dynamic _codificar(dynamic v) {
    if (v == null || v is bool || v is num || v is String) return v;
    if (v is Uint8List) return <String, dynamic>{'__u8': base64Encode(v)};
    if (v is DateTime) return <String, dynamic>{'__dt': v.toIso8601String()};
    if (v is List) return v.map<dynamic>(_codificar).toList();
    if (v is Map) {
      return <String, dynamic>{
        '__map': v.entries
            .map<dynamic>((MapEntry<dynamic, dynamic> e) =>
                <dynamic>[_codificar(e.key), _codificar(e.value)])
            .toList(),
      };
    }
    debugPrint('[Backup] tipo ignorado: ${v.runtimeType}');
    return null;
  }

  dynamic _decodificar(dynamic v) {
    if (v is List) return v.map<dynamic>(_decodificar).toList();
    if (v is Map) {
      if (v.containsKey('__u8')) {
        return Uint8List.fromList(base64Decode(v['__u8'] as String));
      }
      if (v.containsKey('__dt')) return DateTime.parse(v['__dt'] as String);
      if (v.containsKey('__map')) {
        final Map<dynamic, dynamic> m = <dynamic, dynamic>{};
        for (final dynamic par in (v['__map'] as List)) {
          m[_decodificar((par as List)[0])] = _decodificar(par[1]);
        }
        return m;
      }
    }
    return v;
  }
}
