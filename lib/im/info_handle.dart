import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';

Future<List<V2TimUserFullInfo>> getUsersProfile(List<String> users) async {
  final resultado = <V2TimUserFullInfo>[];
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);

  for (final userID in users) {
    if (meuNumero != null && userID == meuNumero) {
      final perfil = SignalLocalStore.getSelfProfile(meuNumero);
      // Foto cifrada (Profile Key) tem prioridade; URL antiga só como legado.
      final String? caminhoFoto = perfil?['avatarPath'] as String?;
      final String? faceUrl = (caminhoFoto != null && caminhoFoto.isNotEmpty)
          ? 'perfil:$meuNumero'
          : perfil?['avatarUrl'] as String?;
      resultado.add(V2TimUserFullInfo(
        userID: meuNumero,
        nickName: perfil?['name'] as String? ?? meuNumero,
        faceUrl: faceUrl,
        selfSignature: perfil?['about'] as String?,
      ));
      continue;
    }

    final contatos = SignalLocalStore.getContacts();
    final match = contatos.where((c) => c['phone'] == userID);
    resultado.add(V2TimUserFullInfo(
      userID: userID,
      nickName: match.isNotEmpty ? (match.first['name'] as String? ?? userID) : userID,
      // Foto cifrada: o ImageView decifra com a Profile Key do contato.
      faceUrl: 'perfil:$userID',
    ));
  }

  return resultado;
}

Future<bool> setUsersProfileMethod(BuildContext context,
    {String? avatarStr, String? nickNameStr}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) return false;

  // 'perfil:...' é só um marcador interno da foto cifrada: nunca pode ir
  // parar na coluna avatar_url (que é uma URL pública, de legado).
  final String? avatarLegado =
      (avatarStr != null && avatarStr.isNotEmpty && !avatarStr.startsWith('perfil:'))
          ? avatarStr
          : null;

  try {
    final supabase = Supabase.instance.client;

    await supabase.from('signal_accounts').upsert({
      'phone': meuNumero,
      if (nickNameStr != null) 'display_name': nickNameStr,
      if (avatarLegado != null) 'avatar_url': avatarLegado,
      'updated_at': DateTime.now().toIso8601String(),
    });

    final perfilAtual =
        SignalLocalStore.getSelfProfile(meuNumero) ?? <String, dynamic>{};
    if (nickNameStr != null) perfilAtual['name'] = nickNameStr;
    if (avatarLegado != null) perfilAtual['avatarUrl'] = avatarLegado;
    await SignalLocalStore.saveSelfProfile(meuNumero, perfilAtual);

    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> getRemarkMethod(String id) async {
  final contatos = SignalLocalStore.getContacts();
  final match = contatos.where((c) => c['phone'] == id);
  return match.isNotEmpty ? match.first['name'] as String? : null;
}

Future<void> setRemarkMethod(String userID, String remark) async {
  final contatos = SignalLocalStore.getContacts();
  final match = contatos.where((c) => c['phone'] == userID);
  final contato = match.isNotEmpty
      ? Map<String, dynamic>.from(match.first)
      : {'phone': userID};
  contato['name'] = remark;
  await SignalLocalStore.upsertContact(contato);
}
