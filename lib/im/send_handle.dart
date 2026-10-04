import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import '../tools/event/im_event.dart';
import 'local_store.dart';

typedef CallbackMsg = void Function(V2TimMessage messageInfo);

Future<void> sendTextMsg(String targetId, int type, String context,
    {CallbackMsg? call}) async {
  final String? meuNumero = await SharedUtil.instance.getString(Keys.account);
  if (meuNumero == null) {
    showToast('Sessão inválida — faça login de novo');
    return;
  }

  if (type == ConversationType.V2TIM_GROUP) {
    showToast('Envio pra grupo ainda não suportado');
    return;
  }

  final int agora = DateTime.now().millisecondsSinceEpoch;
  // ID único: viaja criptografado dentro da mensagem e é a chave dos recibos.
  final String msgID = 'm_${agora}_${Random().nextInt(1 << 30)}';

  final V2TimMessage mensagem = V2TimMessage(
    msgID: msgID,
    id: msgID,
    timestamp: agora,
    sender: meuNumero,
    userID: targetId,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: context),
    isSelf: true,
    status: 1,
  );

  await _salvarMensagemLocal(targetId, mensagem);
  if (call != null) call(mensagem);
  eventBusNewMsg.value = EventBusNewMsg(targetId);

  try {
    // Envia pela caixa de correio do Supabase (criptografado pelo SignalCore)
    await SignalCore().enviarMensagemSegura(targetId, context, msgId: msgID);

    // 2 = servidor recebeu (1 visto cinza). Os recibos sobem pra 6/7.
    // upgrade (e não update): se o recibo de entrega já chegou, não rebaixa.
    await SignalLocalStore.upgradeMessageStatus(targetId, [msgID], 2);
    eventBusNewMsg.value = EventBusNewMsg(targetId);
  } catch (e) {
    await SignalLocalStore.updateMessageStatus(targetId, msgID, 4);
    showToast('Falha ao enviar: $e');
    eventBusNewMsg.value = EventBusNewMsg(targetId);
  }
}

Future<void> _salvarMensagemLocal(
    String conversationId, V2TimMessage m) async {
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
