import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:wechat_flutter/pages/chat/chat_page.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/dialog/friend_item_dialog.dart';
import 'package:wechat_flutter/ui/item/contact_card.dart';
import 'package:wechat_flutter/ui/orther/button_row.dart';

class ContactsDetailsPage extends StatefulWidget {
  final String? avatar, title, id;

  ContactsDetailsPage({this.avatar, this.title, this.id});

  @override
  _ContactsDetailsPageState createState() => _ContactsDetailsPageState();
}

class _ContactsDetailsPageState extends State<ContactsDetailsPage> {
  late String _titulo;
  late String _avatar;

  @override
  void initState() {
    super.initState();
    _titulo = widget.title ?? '';
    _avatar = widget.avatar ?? '';
    _carregarPerfilSupabase();
  }

  /// Busca nome e foto atuais do usuário em signal_accounts (coluna "phone"
  /// guarda o identificador: e-mail ou telefone). Se falhar, mantém o que veio.
  Future<void> _carregarPerfilSupabase() async {
    final String? id = widget.id;
    if (id == null || id.isEmpty) return;
    try {
      final linha = await Supabase.instance.client
          .from('signal_accounts')
          .select('display_name, avatar_url')
          .eq('phone', id)
          .maybeSingle();
      if (linha == null || !mounted) return;
      final String? nome = linha['display_name'] as String?;
      final String? foto = linha['avatar_url'] as String?;
      setState(() {
        if (nome != null && nome.trim().isNotEmpty) _titulo = nome.trim();
        if (foto != null && foto.trim().isNotEmpty) _avatar = foto.trim();
      });
    } catch (_) {
      // sem perfil ou sem permissão: segue com os dados recebidos
    }
  }

  List<Widget> body(bool isSelf) {
    return [
      new ContactCard(
        img: _avatar,
        id: widget.id!,
        title: _titulo,
        nickName: _titulo,
        isBorder: true,
      ),
      new ButtonRow(
        margin: EdgeInsets.only(top: 10.0),
        text: 'Enviar mensagem',
        isBorder: true,
        onPressed: () {
          log('to chat page');
          Get.off(new ChatPage(
              id: widget.id!,
              title: _titulo,
              type: ConversationType.V2TIM_C2C));
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final globalModel = Provider.of<GlobalModel>(context);
    bool isSelf = globalModel.account == widget.id;

    var rWidget = [
      new SizedBox(
        width: 60,
        child: new TextButton(
          style:
              ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.all(0))),
          onPressed: () =>
              friendItemDialog(context, userId: widget.id!, suCc: (v) {
            if (v) Navigator.of(context).maybePop();
          }),
          child: new Image.asset(contactAssets + 'ic_contacts_details.png'),
        ),
      )
    ];

    return new Scaffold(
      backgroundColor: chatBg,
      appBar: new ComMomBar(
          title: '',
          backgroundColor: Colors.white,
          rightDMActions: isSelf ? [] : rWidget),
      body: new SingleChildScrollView(
        child: new Column(children: body(isSelf)),
      ),
    );
  }
}
