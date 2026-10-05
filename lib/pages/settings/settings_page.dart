import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/core/presence_service.dart';
import 'package:wechat_flutter/im/all_im.dart';
import 'package:wechat_flutter/pages/settings/language_page.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Pergunta antes de sair da conta (usado aqui e no menu ⋮ do Perfil).
Future<void> confirmarSairDaConta(BuildContext context) async {
  final bool? confirmou = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: Text(trApp('Sair da conta?',
            en: 'Log out?', zh: '退出登录？')),
        content: Text(trApp('Você precisará entrar de novo para usar o app.',
            en: 'You will need to sign in again to use the app.',
            zh: '您需要重新登录才能使用。')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(trApp('Cancelar', en: 'Cancel', zh: '取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(trApp('Sair', en: 'Log out', zh: '退出'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      );
    },
  );
  if (confirmou == true && context.mounted) {
    await ImLoginManager.loginOut(context);
  }
}

/// Configurações: idioma, privacidade (status online) e sair da conta.
/// Serve tanto como aba da barra inferior quanto como tela aberta pelo botão
/// "Configurações" do Perfil (o botão voltar só aparece quando há para onde voltar).
class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  Widget _secao(String titulo, List<Widget> filhos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(32.0, 18.0, 16.0, 8.0),
          child: Text(
            titulo,
            style: const TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                color: _verde),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: filhos),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);

    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(
        title: trApp('Configurações', en: 'Settings', zh: '设置'),
        backgroundColor: chatBg,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24.0),
        children: <Widget>[
          _secao(trApp('Geral', en: 'General', zh: '通用'), <Widget>[
            ListTile(
              leading: const Icon(Icons.language, color: _verde),
              title: Text(trApp('Idioma', en: 'Language', zh: '语言')),
              subtitle: Text(model.currentLanguage),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.to<void>(LanguagePage()),
            ),
          ]),
          _secao(trApp('Privacidade', en: 'Privacy', zh: '隐私'), <Widget>[
            ValueListenableBuilder<bool>(
              valueListenable: PresenceService.instance.compartilhando,
              builder: (BuildContext context, bool ligado, Widget? _) {
                return SwitchListTile(
                  secondary:
                      const Icon(Icons.visibility_outlined, color: _verde),
                  activeColor: _verde,
                  title: Text(trApp('Mostrar quando estou online',
                      en: 'Show when I am online', zh: '显示我的在线状态')),
                  subtitle: Text(trApp(
                      'Seu "online" e "visto por último" ficam visíveis para outros usuários.',
                      en: 'Your "online" and "last seen" are visible to other users.',
                      zh: '其他用户可以看到您的在线状态和最后在线时间。')),
                  value: ligado,
                  onChanged: (bool v) =>
                      PresenceService.instance.definirCompartilhamento(v),
                );
              },
            ),
          ]),
          _secao(trApp('Conta', en: 'Account', zh: '账号'), <Widget>[
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                trApp('Sair da conta', en: 'Log out', zh: '退出登录'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => confirmarSairDaConta(context),
            ),
          ]),
        ],
      ),
    );
  }
}
