import 'package:lpinyin/lpinyin.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:wechat_flutter/im/friend_handle.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import '../info_handle.dart';

class Contact {
  Contact({
    required this.avatar,
    required this.name,
    required this.nameIndex,
    required this.identifier,
  });

  final String avatar;
  final String name;
  final String nameIndex;
  final String identifier;
}

/// Letra do índice A-Z. Nomes vazios ou que não começam por letra vão para '#'.
String _inicial(String nome) {
  try {
    final String pinyin = PinyinHelper.getFirstWordPinyin(nome);
    if (pinyin.isNotEmpty) {
      final String letra = pinyin[0].toUpperCase();
      if (RegExp(r'^[A-Z]$').hasMatch(letra)) return letra;
    }
  } catch (_) {}
  return '#';
}

class ContactsPageData {
  Future<bool> contactIsNull() async {
    final String? user = await SharedUtil.instance.getString(Keys.account);
    final List<V2TimFriendInfo> result = await getContactsFriends(user!);
    return !listNoEmpty(result);
  }

  Future<List<Contact>> getMethod(List<V2TimFriendInfo> result) async {
    List<Contact> contacts = <Contact>[];
    String avatar;
    String nickName;
    String identifier;
    String? remark;

    if (!listNoEmpty(result)) {
      return contacts;
    }
    int dLength = result.length;
    for (int i = 0; i < dLength; i++) {
      V2TimFriendInfo model = result[i];
      avatar = model.userProfile?.faceUrl ?? defIcon;
      identifier = model.userID;
      remark = await getRemarkMethod(model.userID);
      nickName = model.userProfile?.nickName ?? model.userID;
      final String nomeFinal = (remark?.isNotEmpty ?? false)
          ? remark!
          : (nickName.trim().isNotEmpty ? nickName.trim() : identifier);
      contacts.insert(
        0,
        Contact(
          avatar: avatar,
          name: nomeFinal,
          nameIndex: _inicial(nomeFinal),
          identifier: identifier,
        ),
      );
    }
    return contacts;
  }

  Future<List<Contact>> listFriend() async {
    final String? user = await SharedUtil.instance.getString(Keys.account);
    final List<V2TimFriendInfo> result = await getContactsFriends(user!);
    return getMethod(result);
  }
}
