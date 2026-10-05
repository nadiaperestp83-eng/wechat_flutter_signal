import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';

typedef OnSuCc = void Function(bool v);

Future<dynamic> addFriend(String userName, BuildContext context,
    {OnSuCc? suCc, String? name}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) {
    showToast('Sessão inválida');
    return;
  }

  try {
    final supabase = Supabase.instance.client;

    // Verifica se o número existe no Supabase (tabela signal_bundles)
    final bundleRow = await supabase
        .from('signal_bundles')
        .select('user_id')
        .eq('user_id', userName)
        .maybeSingle();

    if (bundleRow == null) {
      showToast('Esse número não está cadastrado no app');
      return;
    }

    await SignalLocalStore.upsertContact({
      'phone': userName,
      'name': name,
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
              faceUrl: 'perfil:${c['phone']}',
            ),
          ))
      .toList();
}

Future<bool> createGroupChat(List<String> personList, {String? name}) async {
  showToast('Criação de grupo ainda não suportada');
  return false;
}
