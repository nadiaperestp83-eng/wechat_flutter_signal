import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Guarda mensagens, conversas e contatos localmente (Hive), do jeito que
/// um cliente Signal de verdade faz — o servidor (bridge/Supabase) não
/// retém nada, só repassa. Aqui é a única fonte de verdade do histórico.
///
/// Guardamos tudo como JSON dentro de Box<String> (chave -> string JSON)
/// pra não precisar gerar TypeAdapter do Hive (build_runner).
class SignalLocalStore {
  SignalLocalStore._();

  static const _boxMessages = 'signal_messages_box';
  static const _boxConversations = 'signal_conversations_box';
  static const _boxContacts = 'signal_contacts_box';

  static late Box<String> _messages;
  static late Box<String> _conversations;
  static late Box<String> _contacts;

  static Future<void> init() async {
    await Hive.initFlutter();
    _messages = await Hive.openBox<String>(_boxMessages);
    _conversations = await Hive.openBox<String>(_boxConversations);
    _contacts = await Hive.openBox<String>(_boxContacts);
  }

  // ---------- Mensagens ----------
  // Chave: conversationId (userID pra diretas, groupID pra grupos)
  // Valor: JSON de uma List<Map> de mensagens (mais antiga -> mais nova)

  static List<Map<String, dynamic>> getMessages(String conversationId) {
    final bruto = _messages.get(conversationId);
    if (bruto == null) return [];
    final lista = jsonDecode(bruto) as List<dynamic>;
    return lista.cast<Map<String, dynamic>>();
  }

  /// Adiciona uma mensagem, evitando duplicata pelo msgID.
  static Future<void> appendMessage(
    String conversationId,
    Map<String, dynamic> mensagem,
  ) async {
    final atual = getMessages(conversationId);
    final jaExiste = atual.any((m) => m['msgID'] == mensagem['msgID']);
    if (jaExiste) return;
    atual.add(mensagem);
    await _messages.put(conversationId, jsonEncode(atual));
  }

  static Future<void> updateMessageStatus(
    String conversationId,
    String msgID,
    int status,
  ) async {
    final atual = getMessages(conversationId);
    final idx = atual.indexWhere((m) => m['msgID'] == msgID);
    if (idx == -1) return;
    atual[idx]['status'] = status;
    await _messages.put(conversationId, jsonEncode(atual));
  }

  static Future<void> deleteMessages(String conversationId) async {
    await _messages.delete(conversationId);
  }

  // ---------- Conversas ----------
  // Chave: conversationId. Valor: JSON com metadados da conversa.

  static List<Map<String, dynamic>> getConversations() {
    return _conversations.values
        .map((v) => jsonDecode(v) as Map<String, dynamic>)
        .toList()
      ..sort((a, b) =>
          (b['orderkey'] as int? ?? 0).compareTo(a['orderkey'] as int? ?? 0));
  }

  static Future<void> upsertConversation(Map<String, dynamic> conversa) async {
    final id = conversa['conversationID'] as String;
    await _conversations.put(id, jsonEncode(conversa));
  }

  static Future<void> deleteConversation(String conversationId) async {
    await _conversations.delete(conversationId);
  }

  static Future<void> setUnreadCount(String conversationId, int count) async {
    final bruto = _conversations.get(conversationId);
    if (bruto == null) return;
    final mapa = jsonDecode(bruto) as Map<String, dynamic>;
    mapa['unreadCount'] = count;
    await _conversations.put(conversationId, jsonEncode(mapa));
  }

  // ---------- Contatos ----------
  // Chave: phone do contato. Valor: JSON {phone, name, isRegistered}

  static List<Map<String, dynamic>> getContacts() {
    return _contacts.values.map((v) => jsonDecode(v) as Map<String, dynamic>).toList();
  }

  static Future<void> upsertContact(Map<String, dynamic> contato) async {
    final phone = contato['phone'] as String;
    await _contacts.put(phone, jsonEncode(contato));
  }

  static Future<void> deleteContact(String phone) async {
    await _contacts.delete(phone);
  }

  // ---------- Sessão (perfil local do próprio usuário) ----------

  static Map<String, dynamic>? getSelfProfile(String phone) {
    final bruto = _contacts.get('self:$phone');
    return bruto != null ? jsonDecode(bruto) as Map<String, dynamic> : null;
  }

  static Future<void> saveSelfProfile(String phone, Map<String, dynamic> perfil) async {
    await _contacts.put('self:$phone', jsonEncode(perfil));
  }
}
