import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:wechat_flutter/im/conversation_handle.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

class ChatListData {
  Future<bool> isNull() async {
    final List<V2TimConversation?>? data = await getConversationsListData();
    return !listNoEmpty(data);
  }

  Future<List<V2TimConversation?>> chatListData() async {
    final List<V2TimConversation?>? data = await getConversationsListData();
    return data ?? <V2TimConversation?>[];
  }
}
