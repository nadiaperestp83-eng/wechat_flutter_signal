import 'package:flutter/material.dart';
import 'package:wechat_flutter/ui/edit/emoji_text.dart';

enum _AbaEmoji { emoji, gif, figurinha }

/// Painel de emojis do chat, no estilo do WhatsApp: seletor com 3 abas
/// (Emoji, GIF e Figurinhas) fixo no topo e o conteúdo da aba escolhida
/// logo abaixo, ocupando todo o espaço restante.
///
/// [height] é a altura "útil" do painel (igual à altura do teclado).
/// [bottomInset] é o padding inferior do dispositivo (barra de gestos /
/// botões de navegação). Ele é SOMADO à altura, de modo que o conteúdo
/// nunca fica escondido atrás da área do sistema.
/// GIF e Figurinhas ainda são placeholders ("Em breve").
class EmojiPanel extends StatefulWidget {
  final double height;
  final double bottomInset;
  final ValueChanged<String> onEmojiSelected;

  const EmojiPanel({
    Key? key,
    required this.height,
    required this.onEmojiSelected,
    this.bottomInset = 0.0,
  }) : super(key: key);

  @override
  _EmojiPanelState createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  static const Color _fundo = Color(0xfff6f6f6);
  static const Color _icone = Color(0xff54656f);
  static const double _alturaSeletor = 54.0;

  _AbaEmoji _aba = _AbaEmoji.emoji;

  Widget _segmento({
    required _AbaEmoji aba,
    required Widget filho,
  }) {
    final bool selecionada = _aba == aba;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _aba = aba),
        child: Container(
          height: 38.0,
          alignment: Alignment.center,
          color: selecionada ? Colors.black.withOpacity(0.09) : Colors.transparent,
          child: filho,
        ),
      ),
    );
  }

  /// Barra de abas fixa no topo do painel (nunca rola junto com a grade).
  Widget _seletorDeAbas() {
    return Container(
      height: _alturaSeletor,
      alignment: Alignment.center,
      child: Container(
        width: 250.0,
        height: 38.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19.0),
          border: Border.all(color: Colors.black26, width: 1.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18.0),
          child: Row(
            children: <Widget>[
              _segmento(
                aba: _AbaEmoji.emoji,
                filho: const Icon(Icons.emoji_emotions_outlined,
                    color: _icone, size: 24.0),
              ),
              Container(width: 1.0, height: 38.0, color: Colors.black26),
              _segmento(
                aba: _AbaEmoji.gif,
                filho: const Text(
                  'GIF',
                  style: TextStyle(
                      color: _icone,
                      fontSize: 15.0,
                      fontWeight: FontWeight.w800),
                ),
              ),
              Container(width: 1.0, height: 38.0, color: Colors.black26),
              _segmento(
                aba: _AbaEmoji.figurinha,
                filho: const Icon(Icons.sticky_note_2_outlined,
                    color: _icone, size: 24.0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradeDeEmojis() {
    final int total = EmojiUitl.instance.emojiMap.length;
    return GridView.builder(
      // O padding inferior garante que a última linha de emojis nunca fique
      // atrás da barra de gestos/navegação do dispositivo.
      padding: EdgeInsets.fromLTRB(10.0, 4.0, 10.0, 10.0 + widget.bottomInset),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
      ),
      itemCount: total,
      itemBuilder: (BuildContext context, int index) {
        final String codigo = '[${index + 1}]';
        final String? imagem = EmojiUitl.instance.emojiMap[codigo];
        if (imagem == null) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onEmojiSelected(codigo),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Image.asset(imagem),
          ),
        );
      },
    );
  }

  Widget _emBreve(IconData icone, String titulo) {
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomInset),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icone, size: 56.0, color: Colors.black26),
            const SizedBox(height: 10.0),
            Text(
              titulo,
              style: const TextStyle(
                  fontSize: 16.0,
                  color: _icone,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4.0),
            const Text(
              'Em breve',
              style: TextStyle(fontSize: 14.0, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conteudo() {
    switch (_aba) {
      case _AbaEmoji.emoji:
        return _gradeDeEmojis();
      case _AbaEmoji.gif:
        return _emBreve(Icons.gif, 'GIFs');
      case _AbaEmoji.figurinha:
        return _emBreve(Icons.sticky_note_2_outlined, 'Figurinhas');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Altura total = altura do teclado + padding inferior do dispositivo.
    // Quando o painel está fechado (height == 0) ele colapsa por completo.
    final double alturaTotal =
        widget.height > 0 ? widget.height + widget.bottomInset : 0.0;

    return SizedBox(
      height: alturaTotal,
      width: double.infinity,
      child: ClipRect(
        child: ColoredBox(
          color: _fundo,
          child: Column(
            children: <Widget>[
              // Fixo no topo do painel.
              _seletorDeAbas(),
              // Ocupa todo o resto, sem estourar a altura.
              Expanded(child: _conteudo()),
            ],
          ),
        ),
      ),
    );
  }
}
