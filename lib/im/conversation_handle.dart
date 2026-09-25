import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';

import 'local_store.dart';

Future<List<V2TimConversation?>?> getConversationsListData() async {
  final salvas = SignalLocalStore.getConversations();
  return salvas.map(_mapaParaV2TimConversation).toList();
}

Future<dynamic> deleteConversationAndLocalMsgModel(String id, int type) async {
  await delConversationModel(id, type);
  await delLocalMsg(id, type);
}

Future<dynamic> delLocalMsg(String identifier, int type) async {
  await SignalLocalStore.deleteMessages(identifier);
  return true;
}

Future<dynamic> delConversationModel(String identifier, int type) async {
  await SignalLocalStore.deleteConversation(identifier);
  return true;
}

Future<int> getUnreadMessageNumModel(int type, String id) async {
  final conversas = SignalLocalStore.getConversations();
  final match = conversas.where((c) => c['conversationID'] == id);
  if (match.isEmpty) return 0;
  return (match.first['unreadCount'] as int?) ?? 0;
}

Future<void> setReadMessageModel(int type, String id) async {
  await SignalLocalStore.setUnreadCount(id, 0);
}

V2TimConversation _mapaParaV2TimConversation(Map<String, dynamic> c) {
  final ultimaMensagemMapa = c['lastMessage'] as Map<String, dynamic>?;

  return V2TimConversation(
    conversationID: c['conversationID'] as String,
    type: c['type'] as int?,
    userID: c['userID'] as String?,
    groupID: c['groupID'] as String?,
    showName: c['showName'] as String? ?? c['userID'] as String?,
    faceUrl: c['faceUrl'] as String?,
    unreadCount: c['unreadCount'] as int?,
    orderkey: c['orderkey'] as int?,
    lastMessage: ultimaMensagemMapa != null
        ? V2TimMessage(
            msgID: ultimaMensagemMapa['msgID'] as String?,
            timestamp: ultimaMensagemMapa['timestamp'] as int?,
            sender: ultimaMensagemMapa['sender'] as String?,
            isSelf: ultimaMensagemMapa['isSelf'] as bool? ?? false,
            elemType: (ultimaMensagemMapa['elemType'] as int?) ??
                MessageElemType.V2TIM_ELEM_TYPE_TEXT,
            textElem: V2TimTextElem(text: ultimaMensagemMapa['text'] as String?),
          )
        : null,
  );
}
