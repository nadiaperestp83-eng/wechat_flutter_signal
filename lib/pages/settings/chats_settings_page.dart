import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// Configurações > Chats.
///
/// Por enquanto é só visual: os interruptores mexem na tela, mas não gravam
/// nada e ainda não têm efeito (os recursos chegam numa próxima versão).
class ChatsSettingsPage extends StatefulWidget {
  const ChatsSettingsPage({Key? key}) : super(key: key);

  @override
  State<ChatsSettingsPage> createState() => _ChatsSettingsPageState();
}

class _ChatsSettingsPageState extends State<ChatsSettingsPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  // Só em memória: ao sair da tela voltam ao padrão.
  bool _previaDeLinks = true;
  bool _fotosDosContatos = false;
  bool _manterArquivadas = false;

  Widget _opcao({
    required String titulo,
    required String descricao,
    required bool valor,
    required ValueChanged<bool> aoMudar,
  }) {
    return InkWell(
      onTap: () => aoMudar(!valor),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(titulo, style: _inter(17.0, FontWeight.w400)),
                  const SizedBox(height: 5.0),
                  Text(descricao,
                      style: _inter(14.0, FontWeight.w400,
                          cor: Colors.black45, altura: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 14.0),
            Switch(
              value: valor,
              activeColor: _verde,
              onChanged: aoMudar,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(title: trApp('Chats', en: 'Chats')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24.0),
        children: <Widget>[
          Container(
            color: Colors.white,
            child: Column(
              children: <Widget>[
                _opcao(
                  titulo: trApp('Gerar pré-visualização de links',
                      en: 'Generate link previews'),
                  descricao: trApp(
                      'Carregar pré-visualizações de links diretamente dos sites em mensagens que você envia.',
                      en: 'Load link previews directly from websites in messages you send.'),
                  valor: _previaDeLinks,
                  aoMudar: (bool v) => setState(() => _previaDeLinks = v),
                ),
                _opcao(
                  titulo: trApp('Preferir fotos da lista de contatos',
                      en: 'Prefer contact list photos'),
                  descricao: trApp(
                      'Preferir fotos de contatos da lista de contatos, se disponíveis.',
                      en: 'Prefer contact photos from the contact list, if available.'),
                  valor: _fotosDosContatos,
                  aoMudar: (bool v) => setState(() => _fotosDosContatos = v),
                ),
                _opcao(
                  titulo: trApp('Manter as conversas silenciadas arquivadas',
                      en: 'Keep muted chats archived'),
                  descricao: trApp(
                      'Chats silenciados que estão arquivados permanecerão arquivados quando uma nova mensagem chegar.',
                      en: 'Muted chats that are archived will stay archived when a new message arrives.'),
                  valor: _manterArquivadas,
                  aoMudar: (bool v) => setState(() => _manterArquivadas = v),
                ),
                const SizedBox(height: 8.0),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
            child: Text(
              trApp('Estas opções serão ativadas numa próxima versão.',
                  en: 'These options will be enabled in a future version.'),
              style: _inter(13.0, FontWeight.w400, cor: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}
