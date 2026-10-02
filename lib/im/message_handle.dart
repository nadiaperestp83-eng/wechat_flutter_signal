import 'dart:developer';

import 'package:image_picker/image_picker.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';

Future<List<V2TimMessage>> getDimMessages(String id,
    {required int type, Callback? callback, int num = 50}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero != null) {
    await _puxarNovasMensagens(meuNumero, id);
  }

  final List<Map<String, dynamic>> salvas = SignalLocalStore.getMessages(id);
  final ordenadas = salvas.reversed.toList();

  return ordenadas.take(num).map(_mapaParaV2TimMessage).toList();
}

/// Busca mensagens novas no Firestore via SignalCore e salva no Hive.
Future<void> _puxarNovasMensagens(String meuNumero, String conversationId) async {
  try {
    // SignalCore já escuta via stream em tempo real — aqui apenas garantimos
    // que mensagens pendentes offline sejam processadas ao abrir o chat.
    await SignalCore().verificarMensagensPendentes();
  } catch (e) {
    log('[message_handle] falha ao buscar mensagens novas: $e');
  }
}

V2TimMessage _mapaParaV2TimMessage(Map<String, dynamic> m) {
  return V2TimMessage(
    msgID: m['msgID'] as String?,
    id: m['msgID'] as String?,
    timestamp: m['timestamp'] as int?,
    sender: m['sender'] as String?,
    userID: m['userID'] as String?,
    groupID: m['groupID'] as String?,
    elemType:
        (m['elemType'] as int?) ?? MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: m['text'] as String?),
    isSelf: m['isSelf'] as bool? ?? false,
    status: m['status'] as int?,
  );
}

Future<void> sendImageMsg(String userName, int type,
    {required Callback callback,
    required ImageSource source,
    required File file}) async {
  showToast('Envio de imagem ainda não suportado');
}

Future<dynamic> sendSoundMessages(String id, String soundPath, int duration,
    int type, Callback callback) async {
  showToast('Envio de áudio ainda não suportado');
}
