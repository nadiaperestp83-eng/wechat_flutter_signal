import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Criptografia de mídia no aparelho, no estilo do Signal.
///
/// Usada hoje pela foto de perfil (chave = Profile Key) e pensada para ser
/// reaproveitada nas fotos do chat (chave aleatória por anexo, enviada dentro
/// da mensagem Signal). O servidor só enxerga o "blob" cifrado.
///
/// Formato do blob:  nonce (12 bytes) || texto cifrado || tag GCM (16 bytes)
class MediaCrypto {
  MediaCrypto._();

  static const int tamanhoChave = 32; // AES-256
  static const int _tamanhoNonce = 12;
  static const int _tamanhoTagBits = 128;
  static const int _tamanhoTagBytes = 16;

  static final Random _aleatorio = Random.secure();

  /// Bytes aleatórios criptograficamente seguros.
  static Uint8List bytesAleatorios(int quantidade) => Uint8List.fromList(
      List<int>.generate(quantidade, (_) => _aleatorio.nextInt(256)));

  /// Gera uma chave nova de 32 bytes (Profile Key ou chave de anexo).
  static Uint8List gerarChave() => bytesAleatorios(tamanhoChave);

  /// Cifra [dados] com [chave]. Cada chamada usa um nonce novo.
  static Uint8List cifrar(Uint8List chave, Uint8List dados) {
    _validarChave(chave);
    final Uint8List nonce = bytesAleatorios(_tamanhoNonce);
    final GCMBlockCipher cifra = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
            KeyParameter(chave), _tamanhoTagBits, nonce, Uint8List(0)),
      );
    final Uint8List cifrado = cifra.process(dados);

    final Uint8List saida = Uint8List(_tamanhoNonce + cifrado.length);
    saida.setRange(0, _tamanhoNonce, nonce);
    saida.setRange(_tamanhoNonce, saida.length, cifrado);
    return saida;
  }

  /// Decifra um blob gerado por [cifrar]. Lança exceção se a chave estiver
  /// errada ou se o conteúdo tiver sido alterado (autenticação GCM).
  static Uint8List decifrar(Uint8List chave, Uint8List blob) {
    _validarChave(chave);
    if (blob.length < _tamanhoNonce + _tamanhoTagBytes) {
      throw const FormatException('Blob cifrado curto demais.');
    }
    final Uint8List nonce = Uint8List.sublistView(blob, 0, _tamanhoNonce);
    final Uint8List cifrado = Uint8List.sublistView(blob, _tamanhoNonce);
    final GCMBlockCipher cifra = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
            KeyParameter(chave), _tamanhoTagBits, nonce, Uint8List(0)),
      );
    return cifra.process(cifrado);
  }

  static void _validarChave(Uint8List chave) {
    if (chave.length != tamanhoChave) {
      throw ArgumentError('A chave precisa ter $tamanhoChave bytes.');
    }
  }
}
