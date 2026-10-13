import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/core/presence_service.dart';
import 'package:wechat_flutter/core/profile_service.dart';
import 'package:wechat_flutter/core/push_service.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/im/all_im.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

TextStyle _inter(double tam, FontWeight peso, {Color? cor, double? altura}) {
  return GoogleFonts.inter(
    fontSize: tam,
    fontWeight: peso,
    color: cor ?? Colors.black87,
    height: altura,
  );
}

/// Tela "Em breve" (PIN e troca de e-mail).
class _EmBrevePagina extends StatelessWidget {
  final String titulo;
  final String texto;
  final IconData icone;

  const _EmBrevePagina({
    Key? key,
    required this.titulo,
    required this.texto,
    required this.icone,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: ComMomBar(title: titulo),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icone, size: 56.0, color: Colors.black26),
              const SizedBox(height: 14.0),
              Text(trApp('Em breve', en: 'Coming soon', zh: '敬请期待'),
                  style: _inter(20.0, FontWeight.w600)),
              const SizedBox(height: 8.0),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: _inter(14.5, FontWeight.w400,
                      cor: Colors.black45, altura: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Configurações > Conta: PIN (em breve), troca de e-mail (em breve) e
/// exclusão da conta (funciona de verdade).
class AccountPage extends StatefulWidget {
  const AccountPage({Key? key}) : super(key: key);

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  // ------------------------------------------------------------ pedaços

  Widget _cabecalho(String texto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 22.0, 20.0, 6.0),
      child: Text(texto, style: _inter(15.5, FontWeight.w700)),
    );
  }

  Widget _linha({
    required String titulo,
    String? subtitulo,
    required VoidCallback aoTocar,
    Color? cor,
    Widget? direita,
  }) {
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(titulo, style: _inter(17.0, FontWeight.w400, cor: cor)),
                  if (subtitulo != null) ...<Widget>[
                    const SizedBox(height: 4.0),
                    Text(subtitulo,
                        style: _inter(14.0, FontWeight.w400,
                            cor: Colors.black45, altura: 1.35)),
                  ],
                ],
              ),
            ),
            if (direita != null) ...<Widget>[
              const SizedBox(width: 12.0),
              direita,
            ],
          ],
        ),
      ),
    );
  }

  Widget _bloco(List<Widget> filhos) =>
      Container(color: Colors.white, child: Column(children: filhos));

  // ------------------------------------------------------------- ações

  void _pinEmBreve() {
    Get.to<void>(_EmBrevePagina(
      titulo: trApp('PIN do Kakaô', en: 'Kakaô PIN'),
      icone: Icons.pin_outlined,
      texto: trApp(
          'O PIN do Kakaô ainda está sendo preparado e vai chegar numa próxima versão.',
          en: 'The Kakaô PIN is still being prepared.'),
    ));
  }

  void _mudarEmailEmBreve() {
    Get.to<void>(_EmBrevePagina(
      titulo: trApp('Mudar e-mail', en: 'Change e-mail'),
      icone: Icons.alternate_email,
      texto: trApp(
          'Seu e-mail é o seu identificador no Kakaô: é por ele que seus contatos e suas mensagens cifradas encontram você. A troca segura de e-mail ainda está sendo preparada.',
          en: 'Your e-mail is your identifier on Kakaô. Safe e-mail change is still being prepared.'),
    ));
  }

  Future<void> _excluirConta() async {
    final GlobalModel model = Provider.of<GlobalModel>(context, listen: false);
    final String meuId = model.account.trim().toLowerCase();

    final bool? sim = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(trApp('Excluir a conta?', en: 'Delete account?')),
        content: Text(trApp(
            'Sua conta e seus dados no Kakaô serão apagados para sempre. '
            'As conversas, os momentos e as fotos guardados neste aparelho '
            'também serão removidos. Esta ação não pode ser desfeita.',
            en: 'Your account and data will be permanently deleted. This cannot be undone.')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(trApp('Cancelar', en: 'Cancel', zh: '取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(trApp('Excluir', en: 'Delete', zh: '删除'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (sim != true || !mounted) return;

    // Indicador de progresso por cima de tudo.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => const Center(
          child: CircularProgressIndicator(color: _verde)),
    ));

    final SupabaseClient supabase = Supabase.instance.client;

    // 1) Teste: confirma que a função do Supabase existe e que há sessão,
    //    antes de mexer em qualquer coisa neste aparelho.
    try {
      await supabase
          .rpc('excluir_minha_conta', params: <String, dynamic>{'p_simular': true});
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      final String t = '$e';
      showToast(t.contains('excluir_minha_conta')
          ? 'Falta instalar o SQL excluir_conta.sql no Supabase.'
          : 'Não foi possível excluir a conta: $e');
      return;
    }

    try {
      // 2) Apaga a foto cifrada e para os serviços (antes de apagar a conta,
      //    para nada voltar a gravar dados depois).
      try {
        await ProfileService.instance.removerMinhaFoto(meuId);
      } catch (_) {}
      await PushService.instance.parar();
      await PresenceService.instance.parar();
      await SignalCore().encerrarCasulo();

      // 3) Apaga a conta e os dados no servidor.
      await supabase.rpc('excluir_minha_conta');
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      showToast('Não foi possível excluir a conta: $e');
      // Os serviços já foram parados: volta ao login para recomeçar limpo.
      if (mounted) await ImLoginManager.loginOut(context);
      return;
    }

    // 4) Apaga tudo deste aparelho e fecha o app.
    try {
      await supabase.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    try {
      await Hive.close();
      await Hive.deleteFromDisk();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('[Conta] limpeza local: $e');
    }

    showToast('Conta excluída');
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    await SystemNavigator.pop();
  }

  // ---------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(title: trApp('Conta', en: 'Account', zh: '账号')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24.0),
        children: <Widget>[
          // ----------------------------------------------------- PIN
          _bloco(<Widget>[
            _cabecalho(trApp('PIN do Kakaô', en: 'Kakaô PIN')),
            _linha(
              titulo: trApp('Troque o seu PIN', en: 'Change your PIN'),
              aoTocar: _pinEmBreve,
            ),
            _linha(
              titulo: trApp('Bloqueio de Registro', en: 'Registration Lock'),
              subtitulo: trApp(
                  'Exigir o seu PIN do Kakaô ao registrar o seu e-mail novamente no Kakaô',
                  en: 'Require your Kakaô PIN when registering your e-mail again'),
              aoTocar: _pinEmBreve,
              // Só visual por enquanto (o PIN fica para depois).
              direita: IgnorePointer(
                child: Switch(
                  value: false,
                  activeColor: _verde,
                  onChanged: (bool _) {},
                ),
              ),
            ),
            const SizedBox(height: 8.0),
          ]),
          const SizedBox(height: 10.0),
          // --------------------------------------------------- Conta
          _bloco(<Widget>[
            _cabecalho(trApp('Conta', en: 'Account', zh: '账号')),
            _linha(
              titulo: trApp('Mudar e-mail', en: 'Change e-mail'),
              aoTocar: _mudarEmailEmBreve,
            ),
            _linha(
              titulo: trApp('Excluir a conta', en: 'Delete account'),
              cor: Colors.red,
              aoTocar: _excluirConta,
            ),
            const SizedBox(height: 8.0),
          ]),
        ],
      ),
    );
  }
}
