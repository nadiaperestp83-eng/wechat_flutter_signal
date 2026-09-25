import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import '../tools/event/im_event.dart';
import 'local_store.dart';
import 'signal_bridge_client.dart';

typedef CallbackMsg = void Function(V2TimMessage messageInfo);

/// Continua com a mesma assinatura que chat_page.dart já chama:
/// sendTextMsg(widget.id, widget.type, text)
Future<void> sendTextMsg(String targetId, int type, String context,
    {CallbackMsg? call}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) {
    showToast('Sessão inválida — faça login de novo');
    return;
  }

  if (type == ConversationType.V2TIM_GROUP) {
    // Grupos ainda não têm suporte no bridge signal-cli usado aqui.
    showToast('Envio pra grupo ainda não suportado pelo bridge do Signal');
    return;
  }

  final int agora = DateTime.now().millisecondsSinceEpoch;
  final String msgID = 'local_$agora';

  final V2TimMessage mensagem = V2TimMessage(
    msgID: msgID,
    id: msgID,
    timestamp: agora,
    sender: meuNumero,
    userID: targetId,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: context),
    isSelf: true,
    status: 1, // enviando
  );

  // Mostra a mensagem na tela imediatamente (otimista), antes da resposta
  // do bridge chegar.
  await _salvarMensagemLocal(targetId, mensagem);
  if (call != null) call(mensagem);
  eventBusNewMsg.value = EventBusNewMsg(targetId);

  try {
    final resultado = await SignalBridgeClient.sendText(
      fromPhone: meuNumero,
      to: targetId,
      message: context,
    );

    final bool sucesso = resultado['sucesso'] == true;
    await SignalLocalStore.updateMessageStatus(targetId, msgID, sucesso ? 2 : 4);
    if (!sucesso) {
      showToast('Falha ao enviar: ${resultado['erro'] ?? 'erro desconhecido'}');
    }
    eventBusNewMsg.value = EventBusNewMsg(targetId);
  } catch (e) {
    await SignalLocalStore.updateMessageStatus(targetId, msgID, 4);
    showToast('Falha ao enviar: $e');
    eventBusNewMsg.value = EventBusNewMsg(targetId);
  }
}

Future<void> _salvarMensagemLocal(String conversationId, V2TimMessage m) async {
  await SignalLocalStore.appendMessage(conversationId, {
    'msgID': m.msgID,
    'timestamp': m.timestamp,
    'sender': m.sender,
    'userID': m.userID,
    'groupID': m.groupID,
    'isSelf': true,
    'elemType': m.elemType,
    'text': m.textElem?.text,
    'status': m.status,
  });
  await SignalLocalStore.upsertConversation({
    'conversationID': conversationId,
    'type': ConversationType.V2TIM_C2C,
    'userID': conversationId,
    'showName': null,
    'faceUrl': null,
    'unreadCount': 0,
    'orderkey': m.timestamp,
    'lastMessage': {
      'msgID': m.msgID,
      'timestamp': m.timestamp,
      'sender': m.sender,
      'isSelf': true,
      'elemType': m.elemType,
      'text': m.textElem?.text,
    },
  });
}
