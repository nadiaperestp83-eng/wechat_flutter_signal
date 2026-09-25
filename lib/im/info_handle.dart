import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';
import 'signal_bridge_client.dart';

/// Mesma assinatura usada em global_model.dart: getUsersProfile([account])
Future<List<V2TimUserFullInfo>> getUsersProfile(List<String> users) async {
  final resultado = <V2TimUserFullInfo>[];
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);

  for (final userID in users) {
    if (meuNumero != null && userID == meuNumero) {
      final perfil = SignalLocalStore.getSelfProfile(meuNumero);
      resultado.add(V2TimUserFullInfo(
        userID: meuNumero,
        nickName: perfil?['name'] as String? ?? meuNumero,
        faceUrl: perfil?['avatarUrl'] as String?,
        selfSignature: perfil?['about'] as String?,
      ));
      continue;
    }

    final contatos = SignalLocalStore.getContacts();
    final match = contatos.where((c) => c['phone'] == userID);
    resultado.add(V2TimUserFullInfo(
      userID: userID,
      nickName: match.isNotEmpty ? (match.first['name'] as String? ?? userID) : userID,
    ));
  }

  return resultado;
}

/// Mesma assinatura original: setUsersProfileMethod(context, {avatarStr, nickNameStr}).
/// Devolve bool (sucesso/falha), igual antes — quem chama faz `if (result) {...}`.
Future<bool> setUsersProfileMethod(BuildContext context,
    {String? avatarStr, String? nickNameStr}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) return false;

  try {
    final resultado = await SignalBridgeClient.updateProfile(
      phone: meuNumero,
      name: nickNameStr,
    );

    final perfilAtual = SignalLocalStore.getSelfProfile(meuNumero) ?? <String, dynamic>{};
    if (nickNameStr != null) perfilAtual['name'] = nickNameStr;
    if (avatarStr != null) perfilAtual['avatarUrl'] = avatarStr;
    await SignalLocalStore.saveSelfProfile(meuNumero, perfilAtual);

    return resultado['sucesso'] == true;
  } catch (_) {
    return false;
  }
}

/// Apelido (remark) de um contato — puramente local, o Signal não tem
/// esse conceito no servidor.
Future<String?> getRemarkMethod(String id) async {
  final contatos = SignalLocalStore.getContacts();
  final match = contatos.where((c) => c['phone'] == id);
  return match.isNotEmpty ? match.first['name'] as String? : null;
}

Future<void> setRemarkMethod(String userID, String remark) async {
  final contatos = SignalLocalStore.getContacts();
  final match = contatos.where((c) => c['phone'] == userID);
  final contato = match.isNotEmpty ? Map<String, dynamic>.from(match.first) : {'phone': userID};
  contato['name'] = remark;
  await SignalLocalStore.upsertContact(contato);
}
