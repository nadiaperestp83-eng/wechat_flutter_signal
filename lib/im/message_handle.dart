import 'dart:developer';

import 'package:image_picker/image_picker.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'local_store.dart';
import 'signal_bridge_client.dart';

/// Mesma assinatura de antes: ChatDataRep().repData() chama
/// getDimMessages(id, type: type) e espera List<V2TimMessage>.
///
/// Aqui: primeiro puxa mensagens novas do bridge (/receive) e grava no
/// Hive, depois devolve tudo que está salvo localmente pra essa conversa.
Future<List<V2TimMessage>> getDimMessages(String id,
    {required int type, Callback? callback, int num = 50}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero != null) {
    await _puxarNovasMensagens(meuNumero);
  }

  final List<Map<String, dynamic>> salvas = SignalLocalStore.getMessages(id);
  final ordenadas = salvas.reversed.toList(); // mais nova primeiro, como o Tencent devolvia

  return ordenadas.take(num).map(_mapaParaV2TimMessage).toList();
}

/// Chama /receive no bridge e distribui cada mensagem nova pra conversa
/// certa dentro do Hive (criando a conversa se ainda não existir).
Future<void> _puxarNovasMensagens(String meuNumero) async {
  try {
    final envelopes = await SignalBridgeClient.receive(meuNumero);

    for (final envelope in envelopes) {
      final env = envelope['envelope'] as Map<String, dynamic>?;
      final dataMessage = env?['dataMessage'] as Map<String, dynamic>?;
      if (env == null || dataMessage == null) continue;

      final String? remetente =
          (env['sourceNumber'] ?? env['source']) as String?;
      if (remetente == null) continue;

      final int timestamp =
          (dataMessage['timestamp'] ?? env['timestamp'] ?? DateTime.now().millisecondsSinceEpoch) as int;
      final String? texto = dataMessage['message'] as String?;
      final msgID = 'in_${remetente}_$timestamp';

      await SignalLocalStore.appendMessage(remetente, {
        'msgID': msgID,
        'timestamp': timestamp,
        'sender': remetente,
        'userID': remetente,
        'groupID': null,
        'isSelf': false,
        'elemType': MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        'text': texto,
        'status': 3, // recebida
      });

      await SignalLocalStore.upsertConversation({
        'conversationID': remetente,
        'type': 1, // ConversationType.V2TIM_C2C
        'userID': remetente,
        'showName': null,
        'faceUrl': null,
        'unreadCount': 1,
        'orderkey': timestamp,
        'lastMessage': {
          'msgID': msgID,
          'timestamp': timestamp,
          'sender': remetente,
          'isSelf': false,
          'elemType': MessageElemType.V2TIM_ELEM_TYPE_TEXT,
          'text': texto,
        },
      });
    }
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
    elemType: (m['elemType'] as int?) ?? MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: m['text'] as String?),
    isSelf: m['isSelf'] as bool? ?? false,
    status: m['status'] as int?,
  );
}

// Imagem/áudio: bridge ainda não devolve anexos reais, só texto.
Future<void> sendImageMsg(String userName, int type,
    {required Callback callback,
    required ImageSource source,
    required File file}) async {
  showToast('Recebimento/envio de imagem ainda não suportado pelo bridge do Signal');
}

Future<dynamic> sendSoundMessages(String id, String soundPath, int duration,
    int type, Callback callback) async {
  showToast('Recebimento/envio de áudio ainda não suportado pelo bridge do Signal');
}
