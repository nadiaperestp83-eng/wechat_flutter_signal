import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wechat_flutter/im/friend_handle.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import 'confirm_alert.dart';

/// Menu "..." do perfil do contato. Só mostra ações que funcionam de verdade:
/// excluir contato (remove da sua lista local) e cancelar.
friendItemDialog(BuildContext context,
    {required String userId, required OnSuCc suCc}) {
  void excluir() {
    Navigator.of(context).pop();
    confirmAlert(
      context,
      (bool confirmou) {
        if (confirmou) {
          delFriend(userId, context, suCc: (v) => suCc(v));
        }
      },
      tips: 'Deseja mesmo excluir este contato?',
      okBtn: 'Excluir',
      cancelBtn: 'Cancelar',
      warmStr: 'Excluir contato',
      isWarm: true,
      style: TextStyle(fontWeight: FontWeight.w500),
    );
  }

  Widget botao(String texto, VoidCallback onPressed, {Color? cor}) {
    return new Container(
      width: Get.width,
      child: new TextButton(
        style: ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 15.0)),
          backgroundColor: WidgetStatePropertyAll(Colors.white),
        ),
        onPressed: onPressed,
        child: new Text(texto, style: TextStyle(color: cor)),
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return new Center(
        child: new Material(
          type: MaterialType.transparency,
          child: new Column(
            children: <Widget>[
              new Expanded(
                child: new InkWell(
                  child: new Container(),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              new ClipRRect(
                borderRadius: BorderRadius.all(
                  Radius.circular(10.0),
                ),
                child: new Container(
                  color: Colors.white,
                  child: new Column(
                    children: <Widget>[
                      botao('Excluir contato', excluir, cor: Colors.red),
                      new HorizontalLine(color: appBarColor, height: 10.0),
                      botao('Cancelar', () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      );
    },
  );
}
