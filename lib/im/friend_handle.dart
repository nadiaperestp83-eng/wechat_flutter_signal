import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:wechat_flutter/tools/event/im_event.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';
import 'nome_contato.dart';

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

    final String? nomeLimpo =
        (name == null || name.trim().isEmpty) ? null : name.trim();
    await SignalLocalStore.upsertContact({
      'phone': userName,
      'name': nomeLimpo,
      'isRegistered': true,
    });

    // Avisa a lista de Contatos e a de Conversas para se atualizarem.
    eventBusNewMsg.value = EventBusNewMsg(userName);

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
  eventBusNewMsg.value = EventBusNewMsg(userName);
  showToast('Removido com sucesso');

  if (suCc == null) {
    popToHomePage(context);
  } else {
    suCc(true);
  }
  return true;
}

Future<List<V2TimFriendInfo>> getContactsFriends(String userName) async {
  // A caixa de contatos também guarda o perfil da própria conta ('self:...'),
  // que não tem o campo 'phone'. Só entram aqui os contatos de verdade.
  final List<Map<String, dynamic>> salvos =
      SignalLocalStore.getContacts().where((Map<String, dynamic> c) {
    final dynamic phone = c['phone'];
    return phone is String && phone.isNotEmpty && !phone.startsWith('self:');
  }).toList();

  // Quem foi adicionado sem apelido ganha o nome do perfil dele.
  try {
    await NomeContato.buscar(salvos.map((c) => c['phone'] as String))
        .timeout(const Duration(seconds: 2));
  } catch (_) {}

  return salvos.map((Map<String, dynamic> c) {
    final String phone = c['phone'] as String;
    return V2TimFriendInfo(
      userID: phone,
      friendRemark: NomeContato.apelido(phone),
      userProfile: V2TimUserFullInfo(
        userID: phone,
        nickName: NomeContato.nome(phone),
        faceUrl: 'perfil:$phone',
      ),
    );
  }).toList();
}

Future<bool> createGroupChat(List<String> personList, {String? name}) async {
  showToast('Criação de grupo ainda não suportada');
  return false;
}
