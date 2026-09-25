import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';
import 'signal_bridge_client.dart';

// Mesmo typedef do original — friend_item_dialog.dart importa isso
// diretamente de cá.
typedef OnSuCc = void Function(bool v);

/// Mesma assinatura original: addFriend(userName, context, {suCc}).
/// userName aqui é o número de telefone a adicionar.
Future<dynamic> addFriend(String userName, BuildContext context,
    {OnSuCc? suCc}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) {
    showToast('Sessão inválida');
    return;
  }

  try {
    final statusResultado = await SignalBridgeClient.getUserStatus(
      ownerPhone: meuNumero,
      recipient: userName,
    );
    final bool registrado = statusResultado['registrado'] == true;

    if (!registrado) {
      showToast('Esse número não está no Signal');
      return;
    }

    await SignalBridgeClient.addContact(ownerPhone: meuNumero, recipient: userName);
    await SignalLocalStore.upsertContact({
      'phone': userName,
      'name': null,
      'isRegistered': true,
    });

    showToast('Adicionado com sucesso');

    if (suCc == null) {
      popToHomePage(context);
    } else {
      suCc(true);
    }
  } catch (e) {
    showToast('Falha ao adicionar: $e');
  }
}

/// Mesma assinatura original: delFriend(userName, context, {suCc}).
Future<dynamic> delFriend(String userName, BuildContext context,
    {OnSuCc? suCc}) async {
  await SignalLocalStore.deleteContact(userName);
  showToast('Removido com sucesso');

  if (suCc == null) {
    popToHomePage(context);
  } else {
    suCc(true);
  }
  return true;
}

/// Mesma assinatura original: getContactsFriends(userName). O parâmetro
/// existe pra manter compatibilidade com quem chama, mas como o cache
/// local (Hive) é de uma conta só por aparelho, não precisamos filtrar
/// por ele.
Future<List<V2TimFriendInfo>> getContactsFriends(String userName) async {
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

/// Mesma assinatura original: createGroupChat(personList, {name}).
/// Grupos não são suportados pelo bridge signal-cli atual.
Future<bool> createGroupChat(List<String> personList, {String? name}) async {
  showToast('Criação de grupo ainda não suportada pelo bridge do Signal');
  return false;
}
