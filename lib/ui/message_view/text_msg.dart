import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:wechat_flutter/ui/message_view/gif_bolha.dart';
import 'package:wechat_flutter/ui/message_view/msg_avatar.dart';
import 'package:wechat_flutter/ui/message_view/text_item_container.dart';

import '../../provider/global_model.dart';

/// Vistos da mensagem enviada: relógio, 1 cinza, 2 cinza, 2 azuis ou erro.
class _Vistos extends StatelessWidget {
  final int? status;

  const _Vistos(this.status);

  @override
  Widget build(BuildContext context) {
    IconData icone;
    Color cor;
    switch (status) {
      case 7:
        icone = Icons.done_all;
        cor = const Color(0xff2196F3);
        break;
      case 6:
        icone = Icons.done_all;
        cor = Colors.grey;
        break;
      case 2:
        icone = Icons.done;
        cor = Colors.grey;
        break;
      case 3:
      case 4:
        icone = Icons.error_outline;
        cor = Colors.red;
        break;
      default:
        icone = Icons.access_time;
        cor = Colors.grey;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, right: 4.0),
      child: Icon(icone, size: 16.0, color: cor),
    );
  }
}

class TextMsg extends StatelessWidget {
  const TextMsg(this.text, this.model, {super.key});

  final String text;
  final V2TimMessage model;

  @override
  Widget build(BuildContext context) {
    final GlobalModel globalModel = Provider.of<GlobalModel>(context);
    final bool self = model.sender == globalModel.account;
    final String? gifUrl = GifBolha.extrair(text);
    List<Widget> body = <Widget>[
      MsgAvatar(model: model, globalModel: globalModel),
      gifUrl != null
          ? GifBolha(url: gifUrl, meu: self)
          : TextItemContainer(
              text: text ?? '文字为空',
              action: '',
              isMyself: self,
            ),
      if (self) _Vistos(model.status),
      const Spacer(),
    ];
    if (self) {
      body = body.reversed.toList();
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      alignment: Alignment.topCenter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: body,
      ),
    );
  }
}
