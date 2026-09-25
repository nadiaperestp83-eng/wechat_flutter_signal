import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';
import 'signal_bridge_client.dart';

/// Mesma assinatura que contacts.dart já chama.
Future<List<V2TimFriendInfo>> getContactsFriends() async {
  final salvos = SignalLocalStore.getContacts();
  return salvos
      .where((c) => !(c['phone'] as String).startsWith('self:'))
      .map((c) => V2TimFriendInfo(
            userID: c['phone'] as String,
            friendRemark: c['name'] as String?,
            userProfile: V2TimUserFullInfo(
              userID: c['phone'] as String,
              nickName: (c['name'] as String?) ?? (c['phone'] as String),
            ),
          ))
      .toList();
}

/// Verifica no Signal se o número existe e salva como contato local.
Future<Map<String, dynamic>> addFriend(String recipient, {String? name}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) {
    return {'sucesso': false, 'erro': 'sessão inválida'};
  }

  final statusResultado =
      await SignalBridgeClient.getUserStatus(ownerPhone: meuNumero, recipient: recipient);
  final bool registrado = statusResultado['registrado'] == true;

  if (!registrado) {
    return {'sucesso': false, 'erro': 'Esse número não está no Signal'};
  }

  await SignalBridgeClient.addContact(ownerPhone: meuNumero, recipient: recipient, name: name);

  await SignalLocalStore.upsertContact({
    'phone': recipient,
    'name': name,
    'isRegistered': true,
  });

  return {'sucesso': true};
}

Future<void> delFriend(String userID) async {
  await SignalLocalStore.deleteContact(userID);
}

/// Grupos: sem suporte no bridge signal-cli atual (era stub no original
/// também — mantido assim de propósito, não é regressão).
Future<dynamic> createGroupChat(String name, List<String> memberList) async {
  showToast('Criação de grupo ainda não suportada pelo bridge do Signal');
  return null;
}
