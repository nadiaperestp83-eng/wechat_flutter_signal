import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';
import 'signal_bridge_client.dart';

/// Mesma assinatura usada em global_model.dart: getUsersProfile([account])
Future<List<V2TimUserFullInfo>> getUsersProfile(List<String> userIDList) async {
  final resultado = <V2TimUserFullInfo>[];

  for (final userID in userIDList) {
    final String? meuNumero = await SharedUtil.instance.getString(Keys.account);

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

/// Atualiza o perfil do PRÓPRIO usuário no Signal (via bridge) e localmente.
Future<Map<String, dynamic>> setUsersProfileMethod({String? nickName, String? about}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) return {'sucesso': false, 'erro': 'sessão inválida'};

  final resultado = await SignalBridgeClient.updateProfile(
    phone: meuNumero,
    name: nickName,
    about: about,
  );

  final perfilAtual = SignalLocalStore.getSelfProfile(meuNumero) ?? {};
  if (nickName != null) perfilAtual['name'] = nickName;
  if (about != null) perfilAtual['about'] = about;
  await SignalLocalStore.saveSelfProfile(meuNumero, perfilAtual);

  return resultado;
}

/// Apelido (remark) de um contato — puramente local, o Signal não tem
/// esse conceito no servidor.
Future<String?> getRemarkMethod(String userID) async {
  final contatos = SignalLocalStore.getContacts();
  final match = contatos.where((c) => c['phone'] == userID);
  return match.isNotEmpty ? match.first['name'] as String? : null;
}

Future<void> setRemarkMethod(String userID, String remark) async {
  final contatos = SignalLocalStore.getContacts();
  final match = contatos.where((c) => c['phone'] == userID);
  final contato = match.isNotEmpty ? Map<String, dynamic>.from(match.first) : {'phone': userID};
  contato['name'] = remark;
  await SignalLocalStore.upsertContact(contato);
}
