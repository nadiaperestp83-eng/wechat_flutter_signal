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

/// Aba "Perfil": foto grande, nome, status (online / visto por último),
/// botões Definir foto / Editar informações / Configurações e cartão com os
/// dados da conta. Sem posts.
class MinePage extends StatefulWidget {
  @override
  _MinePageState createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);
  static const double _tamanhoFoto = 140.0;

  bool _enviando = false;

  String _nome(GlobalModel model) {
    final String n = model.nickName;
    if (strNoEmpty(n) && n != 'nickName') return n;
    return model.account;
  }

  String _iniciais(String nome) {
    final List<String> partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.first.toUpperCase();
    return (partes.first.characters.first + partes.last.characters.first)
        .toUpperCase();
  }

  Widget _iniciaisAvatar(String nome) {
    return Container(
      width: _tamanhoFoto,
      height: _tamanhoFoto,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color.fromRGBO(140, 210, 100, 1.0), _verde],
        ),
      ),
      child: Text(
        _iniciais(nome),
        style: TextStyle(
            color: Colors.white,
            fontSize: _tamanhoFoto * 0.36,
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

  void _editarInformacoes() => Get.to<void>(PersonalInfoPage());

  void _abrirConfiguracoes() => Get.to<void>(const SettingsPage());

  void _abrirQr() => Get.to<void>(CodePage());

  Widget _avatar(GlobalModel model) {
    final String nome = _nome(model);
    final bool temFoto = strNoEmpty(model.avatar);

    return GestureDetector(
      onTap: () => _abrirFoto(model),
      child: SizedBox(
        width: _tamanhoFoto,
        height: _tamanhoFoto,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              temFoto
                  ? ImageView(
                      img: model.avatar,
                      width: _tamanhoFoto,
                      height: _tamanhoFoto,
                      fit: BoxFit.cover,
                      isRadius: false,
                    )
                  : _iniciaisAvatar(nome),
              if (_enviando)
                Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 30.0,
                    height: 30.0,
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

  Widget _barraTopo(GlobalModel model) {
    final bool temFoto = strNoEmpty(model.avatar);
    return SizedBox(
      height: 56.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            tooltip: trApp('Meu QR code', en: 'My QR code', zh: '我的二维码'),
            icon: const Icon(Icons.qr_code_2, size: 28.0),
            onPressed: _abrirQr,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String v) {
              switch (v) {
                case 'editar':
                  _editarInformacoes();
                  break;
                case 'config':
                  _abrirConfiguracoes();
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
                    en: 'Edit info', zh: '编辑信息')),
              ),
              PopupMenuItem<String>(
                value: 'config',
                child: Text(
                    trApp('Configurações', en: 'Settings', zh: '设置')),
              ),
              if (temFoto)
                PopupMenuItem<String>(
                  value: 'remover',
                  child: Text(trApp('Remover foto',
                      en: 'Remove photo', zh: '删除头像')),
                ),
              PopupMenuItem<String>(
                value: 'sair',
                child: Text(
                  trApp('Sair da conta', en: 'Log out', zh: '退出登录'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
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
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icone, color: _verde, size: 26.0),
              const SizedBox(height: 6.0),
              Text(
                texto,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _linhaInfo(model.account, trApp('E-mail (toque para copiar)',
              en: 'E-mail (tap to copy)', zh: '邮箱（点击复制）'), () async {
            await Clipboard.setData(ClipboardData(text: model.account));
            showToast(trApp('Copiado', en: 'Copied', zh: '已复制'));
          }),
          const Divider(height: 1.0, indent: 20.0),
          _linhaInfo(_nome(model),
              trApp('Apelido (toque para alterar)',
                  en: 'Nickname (tap to change)', zh: '昵称（点击修改）'), () {
            Get.to<void>(ChangeNamePage(model.nickName));
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);

    return Scaffold(
      backgroundColor: chatBg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            _barraTopo(model),
            const SizedBox(height: 4.0),
            Center(child: _avatar(model)),
            const SizedBox(height: 16.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                _nome(model),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 24.0, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4.0),
            PresenceText(userId: model.account, isSelf: true),
            const SizedBox(height: 24.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _botaoAcao(
                      Icons.add_a_photo_outlined,
                      trApp('Definir foto', en: 'Set photo', zh: '设置头像'),
                      () => _abrirFoto(model),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: _botaoAcao(
                      Icons.edit_outlined,
                      trApp('Editar informações',
                          en: 'Edit info', zh: '编辑信息'),
                      _editarInformacoes,
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: _botaoAcao(
                      Icons.settings_outlined,
                      trApp('Configurações', en: 'Settings', zh: '设置'),
                      _abrirConfiguracoes,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            _cartaoInfo(model),
            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }
}
