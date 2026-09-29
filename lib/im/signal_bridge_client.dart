import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wechat_flutter/config/const.dart';

class SignalBridgeClient {
  SignalBridgeClient._();

  static Future<Map<String, dynamic>> _post(
    String funcao,
    Map<String, dynamic> body,
  ) async {
    if (signalFunctionsBaseUrl.isEmpty || signalSupabaseAnonKey.isEmpty) {
      throw SignalBridgeException(
        'App compilado sem SIGNAL_FUNCTIONS_BASE_URL/SIGNAL_SUPABASE_ANON_KEY. '
        'Verifique os --dart-define do build (GitHub Secrets).',
        0,
      );
    }

    final uri = Uri.parse('$signalFunctionsBaseUrl/$funcao');

    // O Render free tier derruba a conexão enquanto o servidor ainda está
    // "acordando" de estar dormindo (spin-down por inatividade). Tenta de
    // novo uma vez — a primeira chamada já disparou o wake-up.
    for (var tentativa = 1; tentativa <= 2; tentativa++) {
      try {
        final resposta = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $signalSupabaseAnonKey',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 90));

        final dynamic decodificado =
            resposta.body.isNotEmpty ? jsonDecode(resposta.body) : <String, dynamic>{};
        if (decodificado is! Map<String, dynamic>) {
          throw SignalBridgeException('Resposta inesperada de $funcao', resposta.statusCode);
        }
        return decodificado;
      } catch (e) {
        final mensagem = e.toString().toLowerCase();
        final eQuedaDeConexao =
            mensagem.contains('connection abort') || mensagem.contains('connection closed');

        if (tentativa == 1 && eQuedaDeConexao) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        rethrow;
      }
    }

    throw SignalBridgeException('Falha ao chamar $funcao após retry', 0);
  }

  static Future<Map<String, dynamic>> status(String phone) =>
      _post('signal-auth', {'action': 'status', 'phone': phone});

  static Future<Map<String, dynamic>> register(String phone, {String? captchaToken}) =>
      _post('signal-auth', {'action': 'register', 'phone': phone, 'captchaToken': captchaToken});

  static Future<Map<String, dynamic>> verify(String phone, String code) =>
      _post('signal-auth', {'action': 'verify', 'phone': phone, 'code': code});

  static Future<Map<String, dynamic>> sendText({
    required String fromPhone,
    required String to,
    required String message,
  }) =>
      _post('signal-send', {'phone': fromPhone, 'to': to, 'message': message});

  static Future<List<Map<String, dynamic>>> receive(String phone) async {
    final resultado = await _post('signal-receive', {'phone': phone});
    final lista = resultado['envelopes'] as List<dynamic>? ?? [];
    return lista.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> getUserStatus({
    required String ownerPhone,
    required String recipient,
  }) =>
      _post('signal-contacts', {
        'action': 'check',
        'ownerPhone': ownerPhone,
        'recipient': recipient,
      });

  static Future<Map<String, dynamic>> addContact({
    required String ownerPhone,
    required String recipient,
    String? name,
  }) =>
      _post('signal-contacts', {
        'action': 'add',
        'ownerPhone': ownerPhone,
        'recipient': recipient,
        'name': name,
      });

  static Future<Map<String, dynamic>> updateProfile({
    required String phone,
    String? name,
    String? about,
  }) =>
      _post('signal-auth', {
        'action': 'update_profile',
        'phone': phone,
        'name': name,
        'about': about,
      });
}

class SignalBridgeException implements Exception {
  SignalBridgeException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => 'SignalBridgeException($statusCode): $message';
}
