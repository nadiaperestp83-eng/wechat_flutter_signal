import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/ui/dialog/code_dialog.dart';
import 'package:flutter/material.dart';

import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Conteúdo do QR do perfil. Um leitor de QR (a implementar) deve reconhecer
/// o prefixo e adicionar o e-mail como contato.
String conteudoQrDoPerfil(String email) => 'wcf:add:${email.toLowerCase()}';

class CodePage extends StatefulWidget {
  final bool isGroup;

  CodePage([this.isGroup = false]);

  @override
  _CodePageState createState() => _CodePageState();
}

class _CodePageState extends State<CodePage> {
  List<String> data = ['换个样式', '保存到手机', '扫描二维码', '重置二维码'];
  List<String> groupData = ['保存到手机', '扫描二维码'];

  /// QR real do meu perfil (e-mail), com foto e nome.
  Widget _perfilPessoal(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);
    final String nome = (strNoEmpty(model.nickName) && model.nickName != 'nickName')
        ? model.nickName
        : model.account;

    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(
        title: trApp('Meu QR code', en: 'My QR code', zh: '我的二维码'),
        backgroundColor: chatBg,
      ),
      body: SingleChildScrollView(
        child: Container(
          margin: EdgeInsets.only(left: 20.0, right: 20.0, top: Get.height / 14),
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  ClipOval(
                    child: ImageView(
                      img: strNoEmpty(model.avatar) ? model.avatar : defIcon,
                      width: 48.0,
                      height: 48.0,
                      fit: BoxFit.cover,
                      isRadius: false,
                    ),
                  ),
                  const SizedBox(width: 14.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17.0, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2.0),
                        Text(model.account,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.0, color: mainTextColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24.0),
              QrImageView(
                data: conteudoQrDoPerfil(model.account),
                version: QrVersions.auto,
                size: Get.width - 88.0,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16.0),
              Text(
                trApp('Peça para a pessoa escanear este código para te adicionar.',
                    en: 'Ask the other person to scan this code to add you.',
                    zh: '让对方扫描此二维码添加您。'),
                textAlign: TextAlign.center,
                style: TextStyle(color: mainTextColor),
              ),
              const SizedBox(height: 12.0),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: model.account));
                  showToast(trApp('E-mail copiado',
                      en: 'E-mail copied', zh: '邮箱已复制'));
                },
                icon: const Icon(Icons.copy, size: 18.0),
                label: Text(trApp('Copiar meu e-mail',
                    en: 'Copy my e-mail', zh: '复制我的邮箱')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isGroup) return _perfilPessoal(context);

    var rWidget = [
      new SizedBox(
        width: 60,
        child: new TextButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(EdgeInsets.zero),
          ),
          onPressed: () => codeDialog(
            context,
            widget.isGroup ? groupData : data,
          ),
          child: new Image.asset(contactAssets + 'ic_contacts_details.png'),
        ),
      )
    ];

    var body = [
      new Container(
        margin: EdgeInsets.only(
            left: 20.0, right: 20.0, top: Get.height / 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(4.0)),
        ),
        child: new Padding(
          padding: EdgeInsets.all(20.0),
          child: new Column(
            children: <Widget>[
              new SizedBox(
                width: Get.width - 40.0,
                child: new CardPerson(
                  name: 'CrazyQ1',
                  area: '北京 海淀',
                  icon: 'assets/images/Contact_Male.webp',
                  groupName: widget.isGroup ? 'wechat_flutter 101号群' : "未知",
                ),
              ),
              new SizedBox(width: mainSpace),
              new Container(
                padding: EdgeInsets.symmetric(
                  horizontal: !widget.isGroup ? 0 : 20,
                  vertical: !widget.isGroup ? 0 : 20,
                ),
                child: new CachedNetworkImage(
                  imageUrl: widget.isGroup ? download : myCode,
                  fit: BoxFit.cover,
                  width: Get.width - 40,
                ),
              ),
              new SizedBox(height: mainSpace * 2),
              new Text(
                '${widget.isGroup ? '该二维码7天内(7月1日前)有效，重新进入将更新' : '扫一扫上面的二维码图案，加我微信'}',
                style: TextStyle(color: mainTextColor),
              ),
            ],
          ),
        ),
      )
    ];
    return new Scaffold(
      backgroundColor: chatBg,
      appBar: new ComMomBar(
          title: '${widget.isGroup ? '群' : ''}二维码名片', rightDMActions: rWidget),
      body: new SingleChildScrollView(child: new Column(children: body)),
    );
  }
}

class CardPerson extends StatelessWidget {
  final String? name, icon, area, groupName;

  CardPerson({this.name, this.icon, this.area, this.groupName});

  @override
  Widget build(BuildContext context) {
    return new Row(
      children: <Widget>[
        new Padding(
          padding: EdgeInsets.only(right: 15.0),
          child: new ImageView(
            img: strNoEmpty(groupName) ? defGroupAvatar : defAvatar,
            width: 45,
          ),
        ),
        strNoEmpty(groupName)
            ? new Text(
                groupName ?? '',
                style: TextStyle(fontSize: 17.0, fontWeight: FontWeight.w600),
              )
            : new Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  new Row(
                    children: <Widget>[
                      new Text(
                        name ?? '',
                        style: TextStyle(
                            fontSize: 17.0, fontWeight: FontWeight.w600),
                      ),
                      new SizedBox(width: mainSpace / 2),
                      new Image.asset(
                        icon ?? '',
                        width: 18.0,
                        fit: BoxFit.cover,
                      ),
                    ],
                  ),
                  new SizedBox(height: mainSpace / 3),
                  new Text(
                    area ?? '',
                    style: TextStyle(fontSize: 14.0, color: mainTextColor),
                  ),
                ],
              )
      ],
    );
  }
}
