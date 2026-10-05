import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/pages/mine/change_name_page.dart';
import 'package:wechat_flutter/pages/mine/code_page.dart';
import 'package:wechat_flutter/pages/mine/foto_perfil_acoes.dart';
import 'package:wechat_flutter/pages/mine/personal_info_page.dart';
import 'package:wechat_flutter/pages/settings/settings_page.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/view/presence_text.dart';

/// Aba "Perfil": mesmo visual da tela de perfil dos amigos
/// (ContactsDetailsPage): avatar, nome, status, botões em cartões brancos
/// e cartão de informações.
class MinePage extends StatefulWidget {
  @override
  _MinePageState createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  bool _enviando = false;

  String _nome(GlobalModel model) {
    final String n = model.nickName;
    if (strNoEmpty(n) && n != 'nickName') return n;
    return model.account;
  }

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

  Widget _iniciaisAvatar(String nome, double tamanho) {
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
        _iniciais(nome),
        style: TextStyle(
            color: Colors.white,
            fontSize: tamanho * 0.36,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  void _abrirFoto(GlobalModel model) {
    if (_enviando) return;
    FotoPerfilAcoes.abrirOpcoes(
      context,
      model,
      aoMudarEnvio: (bool v) {
        if (mounted) setState(() => _enviando = v);
      },
    );
  }

  Widget _avatarGrande(GlobalModel model) {
    const double tamanho = 110.0;
    final String nome = _nome(model);

    return GestureDetector(
      onTap: () => _abrirFoto(model),
      child: SizedBox(
        width: tamanho,
        height: tamanho,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              strNoEmpty(model.avatar)
                  ? ImageView(
                      img: model.avatar,
                      width: tamanho,
                      height: tamanho,
                      fit: BoxFit.cover,
                      isRadius: false,
                    )
                  : _iniciaisAvatar(nome, tamanho),
              if (_enviando)
                Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 26.0,
                    height: 26.0,
                    child: CircularProgressIndicator(
                        strokeWidth: 3.0, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
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
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13.0, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linhaInfo(String valor, String rotulo, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
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

  Widget _cartaoInfo(GlobalModel model) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        children: <Widget>[
          _linhaInfo(model.account, 'E-mail', () async {
            await Clipboard.setData(ClipboardData(text: model.account));
            showToast('Copiado');
          }),
          const Divider(height: 1.0, indent: 20.0),
          _linhaInfo(_nome(model), 'Apelido', () {
            Get.to<void>(ChangeNamePage(model.nickName));
          }),
        ],
      ),
    );
  }

  List<Widget> body(GlobalModel model) {
    return <Widget>[
      const SizedBox(height: 10.0),
      _avatarGrande(model),
      const SizedBox(height: 16.0),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Text(
          _nome(model),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.w500),
        ),
      ),
      const SizedBox(height: 4.0),
      PresenceText(userId: model.account, isSelf: true),
      const SizedBox(height: 24.0),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: <Widget>[
            Expanded(
                child: _botaoAcao(Icons.add_a_photo_rounded, 'Definir foto',
                    () => _abrirFoto(model))),
            const SizedBox(width: 10.0),
            Expanded(
                child: _botaoAcao(Icons.edit_rounded, 'Editar informações',
                    () => Get.to<void>(PersonalInfoPage()))),
            const SizedBox(width: 10.0),
            Expanded(
                child: _botaoAcao(Icons.settings_rounded, 'Configurações',
                    () => Get.to<void>(const SettingsPage()))),
          ],
        ),
      ),
      const SizedBox(height: 16.0),
      _cartaoInfo(model),
      const SizedBox(height: 24.0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);
    final bool temFoto = strNoEmpty(model.avatar);

    final Widget menu = SizedBox(
      width: 60,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        onSelected: (String v) {
          switch (v) {
            case 'editar':
              Get.to<void>(PersonalInfoPage());
              break;
            case 'config':
              Get.to<void>(const SettingsPage());
              break;
            case 'remover':
              FotoPerfilAcoes.remover(
                model,
                aoMudarEnvio: (bool e) {
                  if (mounted) setState(() => _enviando = e);
                },
              );
              break;
            case 'sair':
              confirmarSairDaConta(context);
              break;
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
              value: 'editar',
              child: Text(trApp('Editar informações',
                  en: 'Edit info', zh: '编辑信息'))),
          PopupMenuItem<String>(
              value: 'config',
              child:
                  Text(trApp('Configurações', en: 'Settings', zh: '设置'))),
          if (temFoto)
            PopupMenuItem<String>(
                value: 'remover',
                child: Text(
                    trApp('Remover foto', en: 'Remove photo', zh: '删除头像'))),
          PopupMenuItem<String>(
              value: 'sair',
              child: Text(trApp('Sair da conta', en: 'Log out', zh: '退出登录'),
                  style: const TextStyle(color: Colors.red))),
        ],
        child: Image.asset(contactAssets + 'ic_contacts_details.png'),
      ),
    );

    final Widget qr = IconButton(
      tooltip: 'QR code',
      icon: const Icon(Icons.qr_code_2, size: 26.0, color: Colors.black),
      onPressed: () => Get.to<void>(CodePage()),
    );

    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(
        title: '',
        backgroundColor: chatBg,
        leadingW: qr,
        rightDMActions: <Widget>[menu],
      ),
      body: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: Column(children: body(model)),
        ),
      ),
    );
  }
}
