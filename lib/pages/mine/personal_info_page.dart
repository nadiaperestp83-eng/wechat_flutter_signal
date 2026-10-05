import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/pages/mine/change_name_page.dart';
import 'package:wechat_flutter/pages/mine/code_page.dart';
import 'package:wechat_flutter/pages/mine/foto_perfil_acoes.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/orther/label_row.dart';

class PersonalInfoPage extends StatefulWidget {
  @override
  _PersonalInfoPageState createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  // Rótulo do e-mail (a conta do app é o e-mail, não o "ID do WeChat").
  static const String _rotuloEmail = 'E-mail';

  bool _enviando = false;

  @override
  void initState() {
    super.initState();
  }

  void action(String? v) {
    if (v == '二维码名片') {
      Get.to<void>(new CodePage());
    } else {
      print(v);
    }
  }

  void _abrirOpcoesDaFoto(GlobalModel model) {
    if (_enviando) return;
    FotoPerfilAcoes.abrirOpcoes(
      context,
      model,
      aoMudarEnvio: (bool v) {
        if (mounted) setState(() => _enviando = v);
      },
    );
  }

  Widget _fotoDePerfil(GlobalModel model) {
    return SizedBox(
      width: 55.0,
      height: 55.0,
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ImageView(
              img: strNoEmpty(model.avatar) ? model.avatar : defIcon,
              width: 55.0,
              height: 55.0,
              fit: BoxFit.cover,
              isRadius: false,
            ),
            if (_enviando)
              Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22.0,
                  height: 22.0,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget body(GlobalModel model) {
    List<Map<String, String>> data = [
      {'label': _rotuloEmail, 'value': model.account},
      {'label': '二维码名片', 'value': ''},
      {'label': '更多', 'value': ''},
      {'label': '我的地址', 'value': ''},
    ];

    var content = [
      new LabelRow(
        label: '头像',
        isLine: true,
        isRight: true,
        rightW: _fotoDePerfil(model),
        onPressed: () => _abrirOpcoesDaFoto(model),
      ),
      new LabelRow(
        label: '昵称',
        isLine: true,
        isRight: true,
        rValue: model.nickName,
        onPressed: () => Get.to<void>(new ChangeNamePage(model.nickName)),
      ),
      new Column(
        children: data.map((item) => buildContent(item, model)).toList(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 14.0, 20.0, 20.0),
        child: Text(
          'Sua foto é criptografada no seu aparelho antes de ser enviada. '
          'O servidor guarda apenas um arquivo ilegível, e só quem conversa '
          'com você recebe a chave para vê-la.',
          style: TextStyle(fontSize: 12.5, color: mainTextColor),
        ),
      ),
    ];

    return new Column(children: content);
  }

  Widget buildContent(Map<String, String> item, GlobalModel model) {
    final String? rotulo = item['label'];
    return new LabelRow(
      label: rotulo,
      rValue: item['value'],
      isLine: rotulo == '我的地址' || rotulo == '更多' ? false : true,
      isRight: rotulo == _rotuloEmail ? false : true,
      margin: EdgeInsets.only(bottom: rotulo == '更多' ? 10.0 : 0.0),
      rightW: rotulo == '二维码名片'
          ? new Image.asset('assets/images/mine/ic_small_code.png',
              color: mainTextColor.withOpacity(0.7))
          : new Container(),
      onPressed: () => action(rotulo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<GlobalModel>(context);

    return new Scaffold(
      backgroundColor: appBarColor,
      appBar: new ComMomBar(title: '个人信息'),
      body: new SingleChildScrollView(child: body(model)),
    );
  }
}
