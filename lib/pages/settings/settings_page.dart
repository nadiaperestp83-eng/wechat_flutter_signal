import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
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

TextStyle _inter(double tam, FontWeight peso, {Color? cor, double? altura}) {
  return GoogleFonts.inter(
    fontSize: tam,
    fontWeight: peso,
    color: cor ?? Colors.black87,
    height: altura,
  );
}

/// Tela "Em breve" dos itens que ainda não têm função.
class _EmBrevePage extends StatelessWidget {
  final String titulo;
  final IconData icone;

  const _EmBrevePage({Key? key, required this.titulo, required this.icone})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: ComMomBar(title: titulo),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icone, size: 56.0, color: Colors.black26),
            const SizedBox(height: 14.0),
            Text(trApp('Em breve', en: 'Coming soon', zh: '敬请期待'),
                style: _inter(20.0, FontWeight.w600)),
            const SizedBox(height: 6.0),
            Text(
              trApp('Esta área ainda está sendo preparada.',
                  en: 'This area is still being prepared.'),
              textAlign: TextAlign.center,
              style: _inter(14.5, FontWeight.w400, cor: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Privacidade: o interruptor de "online" continua funcionando aqui.
class _PrivacidadePage extends StatelessWidget {
  const _PrivacidadePage({Key? key}) : super(key: key);

  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(
          title: trApp('Privacidade', en: 'Privacy', zh: '隐私')),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: 10.0),
          Container(
            color: Colors.white,
            child: ValueListenableBuilder<bool>(
              valueListenable: PresenceService.instance.compartilhando,
              builder: (BuildContext context, bool ligado, Widget? _) {
                return SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined,
                      color: Colors.black87, size: 26.0),
                  activeColor: _verde,
                  title: Text(
                      trApp('Mostrar quando estou online',
                          en: 'Show when I am online', zh: '显示我的在线状态'),
                      style: _inter(17.0, FontWeight.w400)),
                  subtitle: Text(
                      trApp(
                          'Seu "online" e "visto por último" ficam visíveis para outros usuários.',
                          en: 'Your "online" and "last seen" are visible to other users.',
                          zh: '其他用户可以看到您的在线状态和最后在线时间。'),
                      style: _inter(13.0, FontWeight.w400, cor: Colors.black45)),
                  value: ligado,
                  onChanged: (bool v) =>
                      PresenceService.instance.definirCompartilhamento(v),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 18.0, 20.0, 0.0),
            child: Text(
              trApp('Mais opções de privacidade: em breve.',
                  en: 'More privacy options: coming soon.'),
              style: _inter(13.5, FontWeight.w400, cor: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Configurações: lista no estilo do Signal, com o tema claro do fork.
/// Os itens sem função mostram "Em breve".
class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  /// Uma linha da lista: ícone de contorno + título (Inter).
  Widget _linha({
    required IconData icone,
    required String titulo,
    required VoidCallback aoTocar,
    String? valor,
    Color? cor,
  }) {
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 17.0),
        child: Row(
          children: <Widget>[
            Icon(icone, size: 26.0, color: cor ?? Colors.black87),
            const SizedBox(width: 22.0),
            Expanded(
              child: Text(titulo,
                  style: _inter(17.0, FontWeight.w400, cor: cor)),
            ),
            if (valor != null)
              Text(valor,
                  style: _inter(14.5, FontWeight.w400, cor: Colors.black45)),
          ],
        ),
      ),
    );
  }

  /// Bloco branco com divisórias finas entre as linhas.
  Widget _grupo(List<Widget> linhas) {
    final List<Widget> filhos = <Widget>[];
    for (int i = 0; i < linhas.length; i++) {
      if (i > 0) {
        filhos.add(Divider(height: 0.5, indent: 68.0, color: Colors.grey[300]));
      }
      filhos.add(linhas[i]);
    }
    return Container(color: Colors.white, child: Column(children: filhos));
  }

  void _emBreve(String titulo, IconData icone) {
    Get.to<void>(_EmBrevePage(titulo: titulo, icone: icone));
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);

    // Título e ícone de cada item "Em breve".
    Widget emBreve(IconData icone, String titulo, String en) => _linha(
          icone: icone,
          titulo: trApp(titulo, en: en),
          aoTocar: () => _emBreve(trApp(titulo, en: en), icone),
        );

    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(title: trApp('Configurações', en: 'Settings', zh: '设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24.0),
        children: <Widget>[
          _grupo(<Widget>[
            emBreve(Icons.account_circle_outlined, 'Conta', 'Account'),
            emBreve(Icons.favorite_border, 'Doar para o Kakaô', 'Donate to Kakaô'),
          ]),
          const SizedBox(height: 10.0),
          _grupo(<Widget>[
            emBreve(Icons.brightness_6_outlined, 'Aparência', 'Appearance'),
            _linha(
              icone: Icons.language,
              titulo: trApp('Idioma', en: 'Language', zh: '语言'),
              valor: model.currentLanguage,
              aoTocar: () => Get.to<void>(LanguagePage()),
            ),
            emBreve(Icons.chat_bubble_outline, 'Chats', 'Chats'),
            emBreve(Icons.notifications_none, 'Notificações', 'Notifications'),
            _linha(
              icone: Icons.lock_outline,
              titulo: trApp('Privacidade', en: 'Privacy', zh: '隐私'),
              aoTocar: () => Get.to<void>(const _PrivacidadePage()),
            ),
            emBreve(Icons.history, 'Backups', 'Backups'),
            emBreve(Icons.data_usage, 'Dados e armazenamento', 'Data and storage'),
          ]),
          const SizedBox(height: 10.0),
          _grupo(<Widget>[
            emBreve(Icons.help_outline, 'Ajuda', 'Help'),
            emBreve(Icons.mail_outline, 'Convide seus amigos', 'Invite your friends'),
          ]),
          const SizedBox(height: 10.0),
          _grupo(<Widget>[
            _linha(
              icone: Icons.logout,
              titulo: trApp('Sair da conta', en: 'Log out', zh: '退出登录'),
              cor: Colors.red,
              aoTocar: () => confirmarSairDaConta(context),
            ),
          ]),
        ],
      ),
    );
  }
}
