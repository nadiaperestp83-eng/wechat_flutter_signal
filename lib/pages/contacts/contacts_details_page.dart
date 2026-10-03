import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:wechat_flutter/pages/chat/chat_page.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/dialog/friend_item_dialog.dart';

class ContactsDetailsPage extends StatefulWidget {
  final String? avatar, title, id;

  ContactsDetailsPage({this.avatar, this.title, this.id});

  @override
  _ContactsDetailsPageState createState() => _ContactsDetailsPageState();
}

class _ContactsDetailsPageState extends State<ContactsDetailsPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

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

  String get _nomeExibicao =>
      _titulo.trim().isNotEmpty ? _titulo.trim() : (widget.id ?? '');

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.first.toUpperCase();
    return (partes.first.characters.first + partes.last.characters.first)
        .toUpperCase();
  }

  Widget _iniciaisAvatar(double tamanho) {
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromRGBO(140, 210, 100, 1.0), _verde],
        ),
      ),
      child: Text(
        _iniciais(_nomeExibicao),
        style: TextStyle(
            color: Colors.white,
            fontSize: tamanho * 0.36,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _avatarGrande() {
    const double tamanho = 110.0;
    if (_avatar.trim().isEmpty) return _iniciaisAvatar(tamanho);
    return ClipOval(
      child: Image.network(
        _avatar,
        width: tamanho,
        height: tamanho,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _iniciaisAvatar(tamanho),
      ),
    );
  }

  Widget _botaoAcao(IconData icone, String texto, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icone, color: _verde, size: 26.0),
              const SizedBox(height: 6.0),
              Text(texto,
                  style: const TextStyle(
                      fontSize: 13.0, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirChat() {
    log('to chat page');
    Get.off(new ChatPage(
        id: widget.id!,
        title: _nomeExibicao,
        type: ConversationType.V2TIM_C2C));
  }

  Widget _linhaInfo(String valor, String rotulo) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: valor));
        showToast('Copiado');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(valor, style: const TextStyle(fontSize: 17.0)),
            const SizedBox(height: 4.0),
            Text(rotulo,
                style: const TextStyle(fontSize: 14.0, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _cartaoInfo() {
    final String id = widget.id ?? '';
    final bool ehEmail = id.contains('@');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        children: <Widget>[
          _linhaInfo(id, ehEmail ? 'E-mail' : 'Celular'),
          if (_titulo.trim().isNotEmpty) ...<Widget>[
            const Divider(height: 1.0, indent: 20.0),
            _linhaInfo(_titulo.trim(), 'Apelido'),
          ],
        ],
      ),
    );
  }

  List<Widget> body(bool isSelf) {
    return <Widget>[
      const SizedBox(height: 10.0),
      _avatarGrande(),
      const SizedBox(height: 16.0),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Text(
          _nomeExibicao,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.w500),
        ),
      ),
      const SizedBox(height: 24.0),
      if (!isSelf)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: <Widget>[
              Expanded(
                  child: _botaoAcao(
                      Icons.chat_bubble_rounded, 'Mensagem', _abrirChat)),
              const SizedBox(width: 10.0),
              Expanded(
                  child: _botaoAcao(Icons.notifications_rounded, 'Silenciar',
                      () => showToast('Silenciar: em breve'))),
              const SizedBox(width: 10.0),
              Expanded(
                  child: _botaoAcao(Icons.call_rounded, 'Ligar',
                      () => showToast('Chamada de voz: em breve'))),
              const SizedBox(width: 10.0),
              Expanded(
                  child: _botaoAcao(Icons.videocam_rounded, 'Vídeo',
                      () => showToast('Chamada de vídeo: em breve'))),
            ],
          ),
        ),
      if (!isSelf) const SizedBox(height: 16.0),
      _cartaoInfo(),
      const SizedBox(height: 24.0),
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
          backgroundColor: chatBg,
          rightDMActions: isSelf ? [] : rWidget),
      body: new SingleChildScrollView(
        child: new SizedBox(
          width: double.infinity,
          child: new Column(children: body(isSelf)),
        ),
      ),
    );
  }
}
