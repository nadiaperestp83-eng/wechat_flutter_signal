import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/config/provider_config.dart';
import 'package:wechat_flutter/im/login_handle.dart';
import 'package:wechat_flutter/pages/login/register_page.dart';
import 'package:wechat_flutter/pages/login/select_location_page.dart';
import 'package:wechat_flutter/provider/login_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController _tC = new TextEditingController();
  final List<String> _debugLog = [];
  bool _processando = false;

  // Login por e-mail
  final TextEditingController _emailC = new TextEditingController();
  final TextEditingController _senhaC = new TextEditingController();
  bool _processandoEmail = false;
  bool _ocultarSenha = true;

  void _log(String linha) {
    final hora = DateTime.now().toIso8601String().substring(11, 19);
    debugPrint('[SignalDebug $hora] $linha');
    if (mounted) {
      setState(() => _debugLog.add('$hora  $linha'));
    } else {
      _debugLog.add('$hora  $linha');
    }
  }

  @override
  void initState() {
    super.initState();
    initEdit();
  }

  @override
  void dispose() {
    _tC.dispose();
    _emailC.dispose();
    _senhaC.dispose();
    super.dispose();
  }

  initEdit() async {
    final user = await SharedUtil.instance.getString(Keys.account);
    if (user == null) return;
    // Conta por e-mail vai pro campo de e-mail; telefone fica no campo de telefone.
    if (user.contains('@')) {
      _emailC.text = user;
    } else {
      _tC.text = user;
    }
    if (mounted) setState(() {});
  }

  Future<void> _entrarComEmail() async {
    if (_processandoEmail || _processando) return;
    setState(() => _processandoEmail = true);
    _log('=== Toque em Entrar com e-mail: "${_emailC.text.trim()}" ===');
    await ImLoginManager.loginWithEmail(_emailC.text, _senhaC.text, context,
        onLog: _log);
    if (mounted) setState(() => _processandoEmail = false);
  }

  Widget _campoEmail(String label, String hint, TextEditingController c,
      {bool senha = false}) {
    return new Container(
      padding: EdgeInsets.only(bottom: 5.0),
      margin: EdgeInsets.symmetric(horizontal: 10.0),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey, width: 0.15))),
      child: new Row(
        children: <Widget>[
          new Container(
            width: Get.width * 0.25,
            alignment: Alignment.centerLeft,
            margin: EdgeInsets.only(left: 15.0),
            child: new Text(label,
                style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w400)),
          ),
          new Expanded(
            child: new TextField(
              controller: c,
              maxLines: 1,
              obscureText: senha && _ocultarSenha,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType:
                  senha ? TextInputType.visiblePassword : TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                suffixIcon: senha
                    ? IconButton(
                        icon: Icon(
                            _ocultarSenha ? Icons.visibility_off : Icons.visibility,
                            size: 20.0),
                        onPressed: () =>
                            setState(() => _ocultarSenha = !_ocultarSenha),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoEmail() {
    final bool preenchido =
        _emailC.text.trim().isNotEmpty && _senhaC.text.isNotEmpty;

    return new Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        new Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0),
          child: new Row(
            children: <Widget>[
              new Expanded(child: new Divider()),
              new Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.0),
                child: new Text('ou', style: TextStyle(color: tipColor)),
              ),
              new Expanded(child: new Divider()),
            ],
          ),
        ),
        new Padding(
          padding: EdgeInsets.only(left: 20.0, top: 15.0, bottom: 5.0),
          child: new Text('Entrar com e-mail', style: TextStyle(fontSize: 20.0)),
        ),
        _campoEmail('E-mail', 'seu@email.com', _emailC),
        _campoEmail('Senha', 'Digite sua senha', _senhaC, senha: true),
        new SizedBox(height: 20.0),
        new ComMomButton(
          text: _processandoEmail ? 'Entrando...' : 'Entrar com e-mail',
          style: TextStyle(
              color: preenchido ? Colors.white : Colors.grey.withOpacity(0.8)),
          margin: EdgeInsets.symmetric(horizontal: 10.0),
          color: preenchido
              ? Color.fromRGBO(8, 191, 98, 1.0)
              : Color.fromRGBO(226, 226, 226, 1.0),
          onTap: _entrarComEmail,
        ),
        new Center(
          child: new TextButton(
            child: new Text('Não tem conta? Cadastrar com e-mail',
                style: TextStyle(color: tipColor)),
            onPressed: () => Get.to<void>(
                ProviderConfig.getInstance().getLoginPage(new RegisterPage())),
          ),
        ),
      ],
    );
  }

  Widget bottomItem(String item) {
    return new Row(
      children: <Widget>[
        new InkWell(
          child: new Text(item, style: TextStyle(color: tipColor)),
          onTap: () {
            showToast( S.of(context).notOpen + item);
          },
        ),
        item == S.of(context).weChatSecurityCenter
            ? new Container()
            : new Padding(
                padding: EdgeInsets.symmetric(horizontal: 5.0),
                child: new VerticalLine(height: 15.0),
              )
      ],
    );
  }

  Widget body(LoginModel model) {
    return new Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        new Padding(
          padding: EdgeInsets.only(
              left: 20.0, top: mainSpace * 3, bottom: mainSpace * 2),
          child: new Text(S.of(context).mobileNumberLogin,
              style: TextStyle(fontSize: 25.0)),
        ),
        new TextButton(
          child: new Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.0),
            child: new Row(
              children: <Widget>[
                new Container(
                  width: Get.width * 0.25,
                  alignment: Alignment.centerLeft,
                  child: new Text(S.of(context).phoneCity,
                      style: TextStyle(
                          fontSize: 16.0, fontWeight: FontWeight.w400)),
                ),
                new Expanded(
                  child: new Text(
                    model.area,
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 16.0,
                        fontWeight: FontWeight.w400),
                  ),
                )
              ],
            ),
          ),
          onPressed: () async {
            final result = await Get.to<String?>(new SelectLocationPage());
            if (result == null) return;
            model.area = result;
            model.refresh();
            SharedUtil.instance.saveString(Keys.area, result);
          },
        ),
        new Container(
          padding: EdgeInsets.only(bottom: 5.0),
          decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Colors.grey, width: 0.15))),
          child: new Row(
            children: <Widget>[
              new Container(
                width: Get.width * 0.25,
                alignment: Alignment.centerLeft,
                margin: EdgeInsets.only(left: 25.0),
                child: new Text(
                  S.of(context).phoneNumber,
                  style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w400),
                ),
              ),
              new Expanded(
                  child: new TextField(
                controller: _tC,
                maxLines: 1,
                style: TextStyle(textBaseline: TextBaseline.alphabetic),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter(new RegExp(r'[0-9]'), allow: true)
                ],
                decoration: InputDecoration(
                    hintText: S.of(context).phoneNumberHint,
                    border: InputBorder.none),
                onChanged: (text) {
                  setState(() {});
                },
              ))
            ],
          ),
        ),
        new Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
          child: new InkWell(
            child: new Text(
              S.of(context).userLoginTip,
              style: TextStyle(color: tipColor),
            ),
            onTap: () => showToast( S.of(context).notOpen),
          ),
        ),
        new SizedBox(height: mainSpace * 2.5),
        new ComMomButton(
          text: _processando ? 'Processando...' : S.of(context).nextStep,
          style: TextStyle(
              color:
                  _tC.text == '' ? Colors.grey.withOpacity(0.8) : Colors.white),
          margin: EdgeInsets.symmetric(horizontal: 10.0),
          color: _tC.text == ''
              ? Color.fromRGBO(226, 226, 226, 1.0)
              : Color.fromRGBO(8, 191, 98, 1.0),
          onTap: () async {
            if (_processando) return;
            if (_tC.text == '') {
              showToast('随便输入三位或以上');
            } else if (_tC.text.length >= 3) {
              _log('=== Toque em Next step, número: "${_tC.text}" ===');
              setState(() => _processando = true);
              await ImLoginManager.login(_tC.text, context, onLog: _log);
              if (mounted) setState(() => _processando = false);
            } else {
              showToast('请输入三位或以上');
            }
          },
        ),
        const SizedBox(height: 24.0),
        _secaoEmail(),
        const SizedBox(height: 16.0),
        // Painel de debug — mesma ideia da tela de código: mostra passo a
        // passo o que está acontecendo, sem depender de log externo.
        new Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10.0),
          margin: const EdgeInsets.symmetric(horizontal: 10.0),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Debug (toque e segure pra selecionar/copiar):',
                style: TextStyle(color: Colors.white54, fontSize: 11.0),
              ),
              const SizedBox(height: 6.0),
              SelectableText(
                _debugLog.isEmpty
                    ? '(nada ainda — toque em Next step)'
                    : _debugLog.join('\n'),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11.0,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<LoginModel>(context);

    List<String> btItem = [
      S.of(context).retrievePW,
      S.of(context).emergencyFreeze,
      S.of(context).weChatSecurityCenter,
    ];

    return new Scaffold(
      appBar:
          new ComMomBar(title: '', leadingImg: 'assets/images/bar_close.png'),
      body: new MainInputBody(
        color: appBarColor,
        child: new Stack(
          children: <Widget>[
            new SingleChildScrollView(child: body(model)),
            new Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: new Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: btItem.map(bottomItem).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
