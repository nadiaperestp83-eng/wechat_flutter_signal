import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wechat_flutter/im/login_handle.dart';
import 'package:wechat_flutter/pages/settings/language_page.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Tela única de entrada do Kakaô: a pessoa digita o e-mail, recebe um código
/// de 6 dígitos e confirma. Conta nova é criada sozinha (não há mais "Entrar"
/// e "Cadastrar" separados, nem senha).
class LoginBeginPage extends StatefulWidget {
  @override
  _LoginBeginPageState createState() => _LoginBeginPageState();
}

class _LoginBeginPageState extends State<LoginBeginPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);
  static const int _segundosParaReenviar = 60;

  final TextEditingController _emailC = TextEditingController();
  final TextEditingController _codigoC = TextEditingController();
  final FocusNode _emailF = FocusNode();
  final FocusNode _codigoF = FocusNode();

  bool _aceitou = false;
  bool _codigoEnviado = false;
  bool _carregando = false;
  int _espera = 0;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _emailC.addListener(() => setState(() {}));
    _codigoC.addListener(_aoDigitarCodigo);
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _emailC.dispose();
    _codigoC.dispose();
    _emailF.dispose();
    _codigoF.dispose();
    super.dispose();
  }

  String get _email => _emailC.text.trim().toLowerCase();

  bool get _emailValido =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email);

  // ---------------------------------------------------------------- ações

  Future<void> _enviarCodigo() async {
    if (_carregando) return;
    if (!_emailValido) {
      showToast('Digite um e-mail válido');
      return;
    }
    if (!_aceitou) {
      showToast('Aceite os termos para continuar');
      return;
    }

    setState(() => _carregando = true);
    final bool ok = await ImLoginManager.enviarCodigoEmail(_email);
    if (!mounted) return;
    setState(() => _carregando = false);

    if (ok) {
      setState(() => _codigoEnviado = true);
      _iniciarEspera();
      showToast('Enviamos um código de 6 dígitos para $_email');
      _codigoF.requestFocus();
    }
  }

  Future<void> _reenviarCodigo() async {
    if (_carregando || _espera > 0) return;
    setState(() => _carregando = true);
    final bool ok = await ImLoginManager.enviarCodigoEmail(_email);
    if (!mounted) return;
    setState(() => _carregando = false);
    if (ok) {
      _iniciarEspera();
      showToast('Código reenviado');
    }
  }

  Future<void> _verificar() async {
    if (_carregando) return;
    if (_codigoC.text.trim().length != 6) {
      showToast('Digite o código de 6 dígitos');
      return;
    }
    setState(() => _carregando = true);
    final bool entrou =
        await ImLoginManager.verificarCodigoEmail(_email, _codigoC.text, context);
    if (!mounted) return;
    if (!entrou) {
      setState(() => _carregando = false);
      _codigoC.clear();
      _codigoF.requestFocus();
    }
    // Se entrou, o ImLoginManager já abriu o app (Get.offAll).
  }

  void _aoDigitarCodigo() {
    setState(() {});
    // Confirma sozinho quando os 6 dígitos são digitados.
    if (_codigoC.text.length == 6 && !_carregando) {
      _verificar();
    }
  }

  void _usarOutroEmail() {
    _relogio?.cancel();
    setState(() {
      _codigoEnviado = false;
      _espera = 0;
      _codigoC.clear();
    });
    _emailF.requestFocus();
  }

  void _iniciarEspera() {
    _relogio?.cancel();
    setState(() => _espera = _segundosParaReenviar);
    _relogio = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _espera = _espera - 1);
      if (_espera <= 0) t.cancel();
    });
  }

  // ------------------------------------------------------------ pedaços

  TextStyle _inter(double tam, FontWeight peso, {Color? cor, double? altura, double? espaco}) {
    return GoogleFonts.inter(
      fontSize: tam,
      fontWeight: peso,
      color: cor ?? Colors.black87,
      height: altura,
      letterSpacing: espaco,
    );
  }

  /// Logo "Kakaô" com a folha, sobre um halo suave.
  Widget _logo() {
    return SizedBox(
      height: 190.0,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 190.0,
            height: 190.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[Colors.white, Colors.grey.shade100],
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Text(
                'Kakaô',
                style: GoogleFonts.inter(
                  fontSize: 54.0,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xff1c1c1e),
                  letterSpacing: -2.0,
                ),
              ),
              const Positioned(
                top: -6.0,
                right: -12.0,
                child: Icon(Icons.eco, color: _verde, size: 28.0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoracao(String dica) {
    return InputDecoration(
      hintText: dica,
      hintStyle: _inter(17.0, FontWeight.w400, cor: Colors.black38),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18.0, vertical: 18.0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.0),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.0),
        borderSide: const BorderSide(color: _verde, width: 1.5),
      ),
    );
  }

  Widget _botao(String texto, VoidCallback? aoTocar) {
    return SizedBox(
      width: double.infinity,
      height: 56.0,
      child: ElevatedButton(
        onPressed: aoTocar,
        style: ElevatedButton.styleFrom(
          backgroundColor: _verde,
          disabledBackgroundColor: Colors.grey.shade300,
          elevation: 0.0,
          shape: const StadiumBorder(),
        ),
        child: _carregando
            ? const SizedBox(
                width: 22.0,
                height: 22.0,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Text(texto,
                style: _inter(17.0, FontWeight.w600, cor: Colors.white)),
      ),
    );
  }

  Widget _passoEmail() {
    final bool pronto = _emailValido && _aceitou && !_carregando;
    return Column(
      key: const ValueKey<int>(0),
      children: <Widget>[
        Text('Bem-vindo ao Kakaô!',
            textAlign: TextAlign.center,
            style: _inter(28.0, FontWeight.w700, altura: 1.2, espaco: -0.5)),
        const SizedBox(height: 28.0),
        Text('E-mail', style: _inter(20.0, FontWeight.w500)),
        const SizedBox(height: 10.0),
        Text(
          'Será enviado um código de verificação de 6 dígitos para o seu e-mail. '
          'Se você ainda não tem conta, ela é criada automaticamente.',
          textAlign: TextAlign.center,
          style: _inter(14.5, FontWeight.w400, cor: Colors.black54, altura: 1.4),
        ),
        const SizedBox(height: 22.0),
        TextField(
          controller: _emailC,
          focusNode: _emailF,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _enviarCodigo(),
          style: _inter(17.0, FontWeight.w400),
          decoration: _decoracao('seu@email.com'),
        ),
        const SizedBox(height: 22.0),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _aceitou = !_aceitou),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1.0),
                child: Icon(
                  _aceitou ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: _aceitou ? _verde : Colors.black54,
                  size: 28.0,
                ),
              ),
              const SizedBox(width: 14.0),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: _inter(14.5, FontWeight.w400,
                        cor: Colors.black87, altura: 1.4),
                    children: <InlineSpan>[
                      const TextSpan(text: 'Li e concordo com os '),
                      TextSpan(
                          text: 'Termos de uso',
                          style: _inter(14.5, FontWeight.w600,
                              cor: _verde, altura: 1.4)),
                      const TextSpan(text: ' e o '),
                      TextSpan(
                          text: 'Aviso de Privacidade',
                          style: _inter(14.5, FontWeight.w600,
                              cor: _verde, altura: 1.4)),
                      const TextSpan(text: ' do Kakaô.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28.0),
        _botao('Continuar', pronto ? _enviarCodigo : null),
      ],
    );
  }

  Widget _passoCodigo() {
    final bool pronto = _codigoC.text.length == 6 && !_carregando;
    return Column(
      key: const ValueKey<int>(1),
      children: <Widget>[
        Text('Digite o código',
            textAlign: TextAlign.center,
            style: _inter(28.0, FontWeight.w700, altura: 1.2, espaco: -0.5)),
        const SizedBox(height: 16.0),
        Text(
          'Enviamos um código de 6 dígitos para',
          textAlign: TextAlign.center,
          style: _inter(14.5, FontWeight.w400, cor: Colors.black54),
        ),
        const SizedBox(height: 4.0),
        Text(_email,
            textAlign: TextAlign.center,
            style: _inter(16.0, FontWeight.w600)),
        const SizedBox(height: 26.0),
        TextField(
          controller: _codigoC,
          focusNode: _codigoF,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: _inter(30.0, FontWeight.w600, espaco: 14.0),
          decoration: _decoracao('000000').copyWith(counterText: ''),
        ),
        const SizedBox(height: 28.0),
        _botao('Verificar', pronto ? _verificar : null),
        const SizedBox(height: 14.0),
        _espera > 0
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text('Reenviar código em ${_espera}s',
                    style: _inter(14.5, FontWeight.w400, cor: Colors.black45)),
              )
            : TextButton(
                onPressed: _carregando ? null : _reenviarCodigo,
                child: Text('Reenviar código',
                    style: _inter(15.0, FontWeight.w600, cor: _verde)),
              ),
        TextButton(
          onPressed: _carregando ? null : _usarOutroEmail,
          child: Text('Usar outro e-mail',
              style: _inter(15.0, FontWeight.w500, cor: Colors.black54)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24.0, 6.0, 24.0, 24.0),
            child: Column(
              children: <Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Get.to<void>(LanguagePage()),
                    child: Text(S.of(context).language,
                        style: _inter(15.0, FontWeight.w500, cor: _verde)),
                  ),
                ),
                const SizedBox(height: 8.0),
                _logo(),
                const SizedBox(height: 30.0),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _codigoEnviado ? _passoCodigo() : _passoEmail(),
                ),
                const SizedBox(height: 28.0),
                Text(
                  'Seus dados ficam protegidos: as mensagens e chamadas '
                  'são criptografadas de ponta a ponta.',
                  textAlign: TextAlign.center,
                  style: _inter(12.5, FontWeight.w400,
                      cor: Colors.black45, altura: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
