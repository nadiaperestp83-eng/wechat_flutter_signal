import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/im/login_handle.dart';
import 'package:wechat_flutter/provider/login_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/view/edit_view.dart';

import 'select_location_page.dart';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  bool isSelect = false;

  FocusNode nickF = new FocusNode();
  TextEditingController nickC = new TextEditingController();
  FocusNode phoneF = new FocusNode();
  TextEditingController phoneC = new TextEditingController();
  FocusNode pWF = new FocusNode();
  TextEditingController pWC = new TextEditingController();

  String localAvatarImgPath = '';
  bool _verificando = false;

  String? _numeroComSmsEnviado;
  bool _enviandoSms = false;
  final List<String> _debugLog = [];

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
    _preencherNumeroPendente();
    phoneF.addListener(_aoSairDoCampoTelefone);
  }

  @override
  void dispose() {
    phoneF.removeListener(_aoSairDoCampoTelefone);
    super.dispose();
  }

  // Combina o código do país escolhido no seletor "Country" com os dígitos
  // do campo "Phone" — o usuário não precisa mais digitar "+55" na mão.
  // Se o texto já vier com o código incluso (ex: número pré-preenchido
  // vindo do login_page.dart), não duplica.
  String _numeroCompleto(BuildContext context) {
    final model = Provider.of<LoginModel>(context, listen: false);
    final match = RegExp(r'\+\d+').firstMatch(model.area);
    final codigoPais = match?.group(0) ?? '+55';
    final codigoDigitos = codigoPais.replaceFirst('+', '');

    var apenasDigitos = phoneC.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (!apenasDigitos.startsWith(codigoDigitos)) {
      apenasDigitos = '$codigoDigitos$apenasDigitos';
    }
    return '+$apenasDigitos';
  }

  void _aoSairDoCampoTelefone() {
    if (phoneF.hasFocus) return; // só age quando o campo PERDE o foco
    _log('Campo Phone perdeu o foco (texto: "${phoneC.text}")');
    _dispararEnvioSmsSeNecessario();
  }

  // Cobre o caso de quem chega nessa tela direto (ex: botão "Cadastre-se"
  // da tela inicial), sem ter passado pelo login_page.dart antes — sem
  // isso, o Signal nunca fica sabendo que precisa mandar o SMS.
  Future<void> _dispararEnvioSmsSeNecessario() async {
    if (!strNoEmpty(phoneC.text)) {
      _log('Campo Phone vazio — nada a fazer.');
      return;
    }
    final numero = _numeroCompleto(context);
    if (numero == _numeroComSmsEnviado) {
      _log('SMS já foi pedido pra $numero antes — não repete.');
      return;
    }
    if (_enviandoSms) {
      _log('Já tem um pedido em andamento — ignorando toque duplicado.');
      return;
    }

    _log('=== Iniciando fluxo pra $numero ===');
    showToast('Registrando número no Signal...');
    setState(() => _enviandoSms = true);
    try {
      final resultado = await ImLoginManager.requestCode(numero, onLog: _log);
      _log('Resultado final: $resultado');
      if (resultado['sucesso'] == false) {
        if (resultado['precisaCaptcha'] == true) {
          showToast(
            'O Signal pediu verificação extra pra esse número. '
            'Abra ${resultado['captchaUrl']} e tente de novo.',
          );
        } else {
          showToast('Falha ao enviar SMS: ${resultado['erro'] ?? 'erro desconhecido'}');
        }
        return;
      }
      _numeroComSmsEnviado = numero;
      showToast(
        resultado['jaRegistrado'] == true
            ? 'Esse número já está registrado — digite o código já recebido.'
            : 'Enviamos um SMS com o código de verificação.',
      );
    } catch (e, stack) {
      _log('EXCEÇÃO: $e');
      _log('$stack');
      showToast('Falha ao falar com o servidor Signal: $e');
    } finally {
      if (mounted) setState(() => _enviandoSms = false);
    }
  }

  // O número já foi salvo em login_handle.dart (ImLoginManager.login) antes
  // de mandar o usuário pra cá — só pré-preenchemos o campo por conveniência.
  Future<void> _preencherNumeroPendente() async {
    final numeroPendente = await SharedUtil.instance.getString(Keys.account);
    if (numeroPendente != null && numeroPendente.isNotEmpty) {
      setState(() => phoneC.text = numeroPendente);
      _numeroComSmsEnviado = numeroPendente; // já foi enviado por login_handle.dart
    }
  }

  _openGallery() async {
    XFile? img = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (img != null) {
      localAvatarImgPath = img.path;
      setState(() {});
    } else {
      return;
    }
  }

  Widget body(LoginModel model) {
    var column = [
      new Padding(
        padding: EdgeInsets.only(
            left: 5.0, top: mainSpace * 3, bottom: mainSpace * 2),
        child: new Text('Digite o código enviado por SMS',
            style: TextStyle(fontSize: 25.0)),
      ),
      new Row(
        children: <Widget>[
          new Expanded(
            child: new EditView(
              label: S.of(context).nickName,
              hint: S.of(context).exampleName,
              bottomLineColor:
                  nickF.hasFocus ? Colors.green : lineColor.withOpacity(0.5),
              focusNode: nickF,
              controller: nickC,
              onTap: () => setState(() {}),
            ),
          ),
          new InkWell(
            child: !strNoEmpty(localAvatarImgPath)
                ? new Image.asset('assets/images/login/select_avatar.webp',
                    width: 60.0, height: 60.0, fit: BoxFit.cover)
                : new ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(5.0)),
                    child: new Image.file(File(localAvatarImgPath),
                        width: 60.0, height: 60.0, fit: BoxFit.cover),
                  ),
            onTap: () => _openGallery(),
          ),
        ],
      ),
      new InkWell(
        child: new Padding(
          padding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 5.0),
          child: new Row(
            children: <Widget>[
              new Container(
                width: Get.width * 0.25,
                alignment: Alignment.centerLeft,
                child: new Text(S.of(context).phoneCity,
                    style:
                        TextStyle(fontSize: 16.0, fontWeight: FontWeight.w400)),
              ),
              new Expanded(
                child: new Text(
                  model.area,
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              )
            ],
          ),
        ),
        onTap: () async {
          final result = await Get.to<String?>(new SelectLocationPage());
          if (result == null) return;
          model.area = result;
          model.refresh();
          SharedUtil.instance.saveString(Keys.area, result);
        },
      ),
      new EditView(
        label: S.of(context).phoneNumber,
        hint: S.of(context).phoneNumberHint,
        controller: phoneC,
        focusNode: phoneF,
        onTap: () => setState(() {}),
      ),
      // Campo reaproveitado: era "senha", agora é o código do SMS.
      new EditView(
        label: 'Código SMS',
        hint: '000000',
        controller: pWC,
        focusNode: pWF,
        bottomLineColor:
            pWF.hasFocus ? Colors.green : lineColor.withOpacity(0.5),
        onTap: () => setState(() {}),
        onChanged: (str) {
          setState(() {});
        },
      ),
      new SizedBox(height: mainSpace * 2),
      new Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          new InkWell(
            child: new Image.asset(
              'assets/images/login/${isSelect ? 'ic_select_have.webp' : 'ic_select_no.png'}',
              width: 25.0,
              height: 25.0,
              fit: BoxFit.cover,
            ),
            onTap: () {
              setState(() => isSelect = !isSelect);
            },
          ),
          new Padding(
            padding: EdgeInsets.only(left: mainSpace / 2),
            child: new Text(
              S.of(context).readAgree,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          new InkWell(
            child: new Text(
              S.of(context).protocolName,
              style: TextStyle(color: tipColor),
            ),
            onTap: () => Get.to<void>(WebViewPage(
                url: S.of(context).protocolUrl,
                title: S.of(context).protocolTitle)),
          ),
        ],
      ),
      new ComMomButton(
        text: _verificando ? 'Verificando...' : 'Verificar',
        style: TextStyle(
            color:
                pWC.text == '' ? Colors.grey.withOpacity(0.8) : Colors.white),
        margin: EdgeInsets.only(top: 20.0),
        color: pWC.text == ''
            ? Color.fromRGBO(226, 226, 226, 1.0)
            : Color.fromRGBO(8, 191, 98, 1.0),
        onTap: () async {
          if (_verificando || _enviandoSms) return;
          if (!strNoEmpty(phoneC.text)) {
            showToast('Digite o número de telefone');
            return;
          }

          // Garante que o registro/SMS foi disparado mesmo que o campo
          // Phone nunca tenha perdido o foco de verdade (ex: usuário
          // digitou e tocou direto em Verificar).
          final numeroAtual = _numeroCompleto(context);
          if (_numeroComSmsEnviado != numeroAtual) {
            await _dispararEnvioSmsSeNecessario();
          }

          if (!strNoEmpty(pWC.text)) {
            showToast('Digite o código recebido por SMS');
            return;
          }
          setState(() => _verificando = true);
          await ImLoginManager.verify(_numeroCompleto(context), pWC.text, context);
          if (mounted) setState(() => _verificando = false);
        },
      ),
      new SizedBox(height: 16.0),
      // Painel de debug — mostra exatamente o que o app está fazendo,
      // passo a passo, sem depender de log do Render/GitHub.
      new Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
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
                  ? '(nada ainda — saia do campo Phone ou toque em Verificar)'
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
    ];

    return new Container(
      padding: EdgeInsets.symmetric(horizontal: 10.0),
      child: new Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: column),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<LoginModel>(context);

    return new Scaffold(
      appBar:
          new ComMomBar(title: "", leadingImg: 'assets/images/bar_close.png'),
      body: new MainInputBody(
        color: appBarColor,
        child: new SingleChildScrollView(child: body(model)),
        onTap: () => setState(() => {}),
      ),
    );
  }
}
