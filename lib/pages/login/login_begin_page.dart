import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wechat_flutter/im/login_handle.dart';
import 'package:wechat_flutter/pages/settings/language_page.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Tela única de entrada do Kakaô: e-mail + senha. Se a conta já existe, entra;
/// se ainda não existe, é criada com os mesmos dados (login e cadastro de
/// sempre, sem telas separadas).
class LoginBeginPage extends StatefulWidget {
  @override
  _LoginBeginPageState createState() => _LoginBeginPageState();
}

class _LoginBeginPageState extends State<LoginBeginPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  final TextEditingController _emailC = TextEditingController();
  final TextEditingController _senhaC = TextEditingController();
  final FocusNode _emailF = FocusNode();
  final FocusNode _senhaF = FocusNode();

  bool _aceitou = false;
  bool _carregando = false;
  bool _ocultarSenha = true;

  @override
  void initState() {
    super.initState();
    _emailC.addListener(() => setState(() {}));
    _senhaC.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailC.dispose();
    _senhaC.dispose();
    _emailF.dispose();
    _senhaF.dispose();
    super.dispose();
  }

  String get _email => _emailC.text.trim().toLowerCase();

  bool get _emailValido =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email);

  bool get _pronto =>
      _emailValido && _senhaC.text.length >= 6 && _aceitou && !_carregando;

  Future<void> _continuar() async {
    if (_carregando) return;
    if (!_emailValido) {
      showToast('Digite um e-mail válido');
      return;
    }
    if (_senhaC.text.length < 6) {
      showToast('A senha precisa ter pelo menos 6 caracteres');
      return;
    }
    if (!_aceitou) {
      showToast('Aceite os termos para continuar');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _carregando = true);
    final bool entrou = await ImLoginManager.entrarOuCadastrarComEmail(
        _email, _senhaC.text, context);
    if (!mounted) return;
    // Se entrou, o ImLoginManager já abriu o app (Get.offAll).
    if (!entrou) setState(() => _carregando = false);
  }

  // ------------------------------------------------------------ pedaços

  TextStyle _inter(double tam, FontWeight peso,
      {Color? cor, double? altura, double? espaco}) {
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

  InputDecoration _decoracao(String dica, {Widget? sufixo}) {
    return InputDecoration(
      hintText: dica,
      hintStyle: _inter(17.0, FontWeight.w400, cor: Colors.black38),
      filled: true,
      fillColor: Colors.grey.shade100,
      suffixIcon: sufixo,
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

  Widget _botao() {
    return SizedBox(
      width: double.infinity,
      height: 56.0,
      child: ElevatedButton(
        onPressed: _pronto ? _continuar : null,
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
            : Text('Continuar',
                style: _inter(17.0, FontWeight.w600, cor: Colors.white)),
      ),
    );
  }

  Widget _termos() {
    return GestureDetector(
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
                Text('Bem-vindo ao Kakaô!',
                    textAlign: TextAlign.center,
                    style: _inter(28.0, FontWeight.w700,
                        altura: 1.2, espaco: -0.5)),
                const SizedBox(height: 14.0),
                Text(
                  'Entre com seu e-mail e senha. Se você ainda não tem conta, '
                  'ela é criada automaticamente.',
                  textAlign: TextAlign.center,
                  style: _inter(14.5, FontWeight.w400,
                      cor: Colors.black54, altura: 1.4),
                ),
                const SizedBox(height: 24.0),
                TextField(
                  controller: _emailC,
                  focusNode: _emailF,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _senhaF.requestFocus(),
                  style: _inter(17.0, FontWeight.w400),
                  decoration: _decoracao('seu@email.com'),
                ),
                const SizedBox(height: 14.0),
                TextField(
                  controller: _senhaC,
                  focusNode: _senhaF,
                  obscureText: _ocultarSenha,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _continuar(),
                  style: _inter(17.0, FontWeight.w400),
                  decoration: _decoracao(
                    'Senha (mínimo 6 caracteres)',
                    sufixo: IconButton(
                      icon: Icon(
                        _ocultarSenha
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.black45,
                      ),
                      onPressed: () =>
                          setState(() => _ocultarSenha = !_ocultarSenha),
                    ),
                  ),
                ),
                const SizedBox(height: 22.0),
                _termos(),
                const SizedBox(height: 28.0),
                _botao(),
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
