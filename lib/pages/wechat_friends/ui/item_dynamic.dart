import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/w_pop/friend_pop.dart';

/// Azul dos nomes e do ⋯ (padrão do Momentos do WeChat).
const Color _azulNome = Color(0xff576b95);

/// Um Momento no feed (dados reais, guardados só neste aparelho).
class ItemDynamic extends StatelessWidget {
  final MomentPost post;

  const ItemDynamic(this.post, {Key? key}) : super(key: key);

  static const double _avatar = 40.0;
  static const double _espaco = 4.0;

  String _tempo() {
    final DateTime quando = DateTime.fromMillisecondsSinceEpoch(post.ts);
    final DateTime agora = DateTime.now();
    final Duration d = agora.difference(quando);
    if (d.inMinutes < 1) return 'Agora';
    if (d.inMinutes < 60) return 'Há ${d.inMinutes} min';
    final bool ontem =
        DateTime(agora.year, agora.month, agora.day)
                .difference(DateTime(quando.year, quando.month, quando.day))
                .inDays ==
            1;
    if (ontem) return 'Ontem';
    return 'Há ${d.inHours} h';
  }

  void _abrirImagem(int indice) {
    Get.to<void>(_Visualizador(post.images, indice));
  }

  Future<void> _confirmarExcluir(BuildContext context) async {
    final bool? sim = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Excluir este momento?'),
        content: const Text(
            'Ele será apagado deste aparelho e dos aparelhos dos seus contatos.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Excluir', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (sim == true) await MomentsService.instance.excluir(post);
  }

  void _comentar(BuildContext context) {
    final TextEditingController controle = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controle,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'Comentar',
                      filled: true,
                      fillColor: Colors.white,
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                TextButton(
                  onPressed: () async {
                    final String texto = controle.text;
                    Navigator.pop(ctx);
                    await MomentsService.instance.comentar(post, texto);
                  },
                  child: const Text('Enviar'),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controle.dispose);
  }

  /// Grade igual à do WeChat: células quadradas, 3 por linha, preenchendo a
  /// largura do conteúdo (2 fotos ficam lado a lado, 4 fotos em 2 x 2).
  Widget _fotos(double larguraConteudo) {
    final int total = post.images.length;
    if (total == 0) return const SizedBox.shrink();

    if (total == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: GestureDetector(
          onTap: () => _abrirImagem(0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: larguraConteudo * 0.65,
                maxHeight: larguraConteudo * 0.8),
            child: Image.memory(post.images.first, gaplessPlayback: true),
          ),
        ),
      );
    }

    final double celula = (larguraConteudo - 2 * _espaco) / 3;
    final int colunas = total == 4 ? 2 : 3;
    final double larguraGrade = colunas * celula + (colunas - 1) * _espaco;

    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: SizedBox(
        width: larguraGrade,
        child: Wrap(
          spacing: _espaco,
          runSpacing: _espaco,
          children: List<Widget>.generate(total, (int i) {
            return GestureDetector(
              onTap: () => _abrirImagem(i),
              child: SizedBox(
                width: celula,
                height: celula,
                child: Image.memory(post.images[i],
                    fit: BoxFit.cover, gaplessPlayback: true),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _curtidasEComentarios() {
    if (post.likes.isEmpty && post.comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      width: double.infinity,
      color: Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (post.likes.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 2.0, right: 4.0),
                  child: Icon(Icons.favorite_border,
                      size: 14.0, color: _azulNome),
                ),
                Expanded(
                  child: Text(
                    post.likes
                        .map((Map<String, String> l) => l['name'] ?? '')
                        .join(', '),
                    style: const TextStyle(color: _azulNome, fontSize: 14.0),
                  ),
                ),
              ],
            ),
          if (post.likes.isNotEmpty && post.comments.isNotEmpty)
            const Divider(height: 10.0),
          for (final MomentComment c in post.comments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.0),
              child: Text.rich(TextSpan(children: <InlineSpan>[
                TextSpan(
                    text: '${c.name}: ',
                    style: const TextStyle(color: _azulNome, fontSize: 14.0)),
                TextSpan(text: c.text, style: const TextStyle(fontSize: 14.0)),
              ])),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 10 (borda) + 40 (avatar) + 10 (espaço) + 10 (borda)
    final double larguraConteudo = Get.width - 70.0;
    final String nome = MomentsService.instance.nomeDe(post);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10.0, 12.0, 10.0, 0.0),
      child: Column(children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: ImageView(
                img: 'perfil:${post.author}',
                width: _avatar,
                height: _avatar,
                fit: BoxFit.cover,
                isRadius: false,
              ),
            ),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  /// Autor
                  Text(nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _azulNome,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w600)),

                  /// Texto
                  if (post.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(post.text,
                          style:
                              const TextStyle(fontSize: 16.0, height: 1.3)),
                    ),

                  /// Fotos
                  _fotos(larguraConteudo),

                  /// Hora, "Excluir" e botão ⋯
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Row(
                      children: <Widget>[
                        Text(_tempo(),
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13.0)),
                        if (post.mine)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _confirmarExcluir(context),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 12.0),
                              child: Text('Excluir',
                                  style: TextStyle(
                                      color: _azulNome, fontSize: 13.0)),
                            ),
                          ),
                        const Spacer(),
                        _BotaoReacao(
                          curtido: MomentsService.instance.jaCurti(post),
                          aoCurtir: () => MomentsService.instance.curtir(post),
                          aoComentar: () => _comentar(context),
                        ),
                      ],
                    ),
                  ),

                  /// Curtidas e comentários
                  _curtidasEComentarios(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12.0),
        Container(height: 0.5, color: Colors.grey[300]),
      ]),
    );
  }
}

/// Botão pequeno "••" (cinza claro) que abre o mini menu Curtir | Comentar.
class _BotaoReacao extends StatelessWidget {
  final bool curtido;
  final VoidCallback aoCurtir;
  final VoidCallback aoComentar;

  const _BotaoReacao({
    required this.curtido,
    required this.aoCurtir,
    required this.aoComentar,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final RenderBox caixa = ctx.findRenderObject() as RenderBox;
          final Offset pos = caixa.localToGlobal(Offset.zero);
          Navigator.push(
            ctx,
            PopRoute(
              child: _MenuReacao(
                posicao: pos,
                alturaBotao: caixa.size.height,
                curtido: curtido,
                aoCurtir: aoCurtir,
                aoComentar: aoComentar,
              ),
            ),
          );
        },
        child: Container(
          width: 34.0,
          height: 22.0,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: const Icon(Icons.more_horiz, size: 18.0, color: _azulNome),
        ),
      ),
    );
  }
}

class _MenuReacao extends StatelessWidget {
  final Offset posicao;
  final double alturaBotao;
  final bool curtido;
  final VoidCallback aoCurtir;
  final VoidCallback aoComentar;

  const _MenuReacao({
    required this.posicao,
    required this.alturaBotao,
    required this.curtido,
    required this.aoCurtir,
    required this.aoComentar,
  });

  Widget _acao(BuildContext context, IconData icone, String texto,
      VoidCallback aoTocar) {
    return Expanded(
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          aoTocar();
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icone, color: Colors.white, size: 16.0),
            const SizedBox(width: 4.0),
            Text(texto,
                style: const TextStyle(color: Colors.white, fontSize: 14.0)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double largura = 190.0;
    const double altura = 36.0;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: posicao.dy + alturaBotao / 2 - altura / 2,
              left: max(8.0, posicao.dx - largura - 6.0),
              child: Container(
                width: largura,
                height: altura,
                decoration: const BoxDecoration(
                  color: itemBgColor,
                  borderRadius: BorderRadius.all(Radius.circular(4.0)),
                ),
                child: Row(
                  children: <Widget>[
                    _acao(
                        context,
                        curtido ? Icons.favorite : Icons.favorite_border,
                        curtido ? 'Descurtir' : 'Curtir',
                        aoCurtir),
                    Container(width: 0.5, height: 20.0, color: Colors.white38),
                    _acao(context, Icons.chat_bubble_outline, 'Comentar',
                        aoComentar),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tela cheia com zoom para as fotos do Momento.
class _Visualizador extends StatelessWidget {
  final List<Uint8List> imagens;
  final int inicial;

  const _Visualizador(this.imagens, this.inicial);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PhotoViewGallery.builder(
        itemCount: imagens.length,
        pageController: PageController(initialPage: inicial),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        builder: (BuildContext context, int i) =>
            PhotoViewGalleryPageOptions(
          imageProvider: MemoryImage(imagens[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (BuildContext c, TapUpDetails d, PhotoViewControllerValue v) =>
              Get.back<void>(),
        ),
      ),
    );
  }
}
