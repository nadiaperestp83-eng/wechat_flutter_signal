import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';

/// Resolve o nome a mostrar para uma pessoa (no lugar do e-mail):
///  1. o apelido que eu dei ao contato;
///  2. o nome que a pessoa usa no perfil dela (signal_accounts.display_name);
///  3. por último, o próprio e-mail.
class NomeContato {
  NomeContato._();

  static final Map<String, String> _remotos = <String, String>{};
  static final Set<String> _tentados = <String>{};

  /// Apelido salvo no contato. Vazio ou igual ao e-mail não conta.
  static String? apelido(String id) {
    for (final Map<String, dynamic> c in SignalLocalStore.getContacts()) {
      if (c['phone'] == id) {
        final dynamic nome = c['name'];
        if (nome is String && nome.trim().isNotEmpty && nome.trim() != id) {
          return nome.trim();
        }
        return null;
      }
    }
    return null;
  }

  /// Nome para exibir agora (sem rede).
  static String nome(String id) => apelido(id) ?? _remotos[id] ?? id;

  /// Busca no Supabase o nome público de quem ainda não tem nome conhecido.
  /// Cada pessoa é consultada uma vez por abertura do app.
  /// Devolve true se descobriu algum nome novo.
  static Future<bool> buscar(Iterable<String> ids) async {
    final List<String> faltam = ids
        .where((String id) =>
            id.isNotEmpty &&
            apelido(id) == null &&
            !_remotos.containsKey(id) &&
            !_tentados.contains(id))
        .toSet()
        .toList();
    if (faltam.isEmpty) return false;
    _tentados.addAll(faltam);

    try {
      final dynamic linhas = await Supabase.instance.client
          .from('signal_accounts')
          .select('phone, display_name')
          .inFilter('phone', faltam);

      bool descobriu = false;
      for (final dynamic linha in (linhas as List<dynamic>)) {
        final Map<dynamic, dynamic> m = linha as Map<dynamic, dynamic>;
        final String? phone = m['phone'] as String?;
        final String? nome = (m['display_name'] as String?)?.trim();
        if (phone == null || nome == null || nome.isEmpty) continue;
        _remotos[phone] = nome;
        descobriu = true;
        await _gravarNoContato(phone, nome);
      }
      return descobriu;
    } catch (e) {
      debugPrint('[NomeContato] não consegui buscar nomes: $e');
      _tentados.removeAll(faltam); // tenta de novo na próxima vez
      return false;
    }
  }

  /// Se o contato existe e está sem nome, guarda o nome descoberto.
  static Future<void> _gravarNoContato(String phone, String nome) async {
    for (final Map<String, dynamic> c in SignalLocalStore.getContacts()) {
      if (c['phone'] != phone) continue;
      final dynamic atual = c['name'];
      if (atual is String && atual.trim().isNotEmpty && atual.trim() != phone) {
        return;
      }
      final Map<String, dynamic> novo = Map<String, dynamic>.from(c);
      novo['name'] = nome;
      await SignalLocalStore.upsertContact(novo);
      return;
    }
  }
}
