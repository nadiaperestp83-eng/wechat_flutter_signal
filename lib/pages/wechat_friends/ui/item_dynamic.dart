import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/w_pop/friend_pop.dart';

/// Um Momento no feed (dados reais, guardados só neste aparelho).
class ItemDynamic extends StatelessWidget {
  final MomentPost post;

  const ItemDynamic(this.post, {Key? key}) : super(key: key);

  String _tempo() {
    final Duration d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(post.ts));
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
    return 'há ${d.inHours} h';
  }

  String _expira() {
    final Duration r = post.restante;
    if (r.inMinutes < 60) return 'some em ${max(1, r.inMinutes)} min';
    return 'some em ${r.inHours} h';
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

  Widget _fotos(double larguraImagem) {
    final int total = post.images.length;
    if (total == 0) return const SizedBox.shrink();

    if (total == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: GestureDetector(
          onTap: () => _abrirImagem(0),
          child: Image.memory(post.images.first,
              width: larguraImagem,
              height: larguraImagem,
              fit: BoxFit.cover,
              gaplessPlayback: true),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: total,
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: larguraImagem,
          crossAxisSpacing: 2.0,
          mainAxisSpacing: 2.0,
          childAspectRatio: 1),
      itemBuilder: (BuildContext context, int i) => GestureDetector(
        onTap: () => _abrirImagem(i),
        child: Image.memory(post.images[i],
            fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }

  Widget _curtidasEComentarios() {
    if (post.likes.isEmpty && post.comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.all(6.0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4.0),
      ),
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
                      size: 14.0, color: Colors.blueAccent),
                ),
                Expanded(
                  child: Text(
                    post.likes
                        .map((Map<String, String> l) => l['name'] ?? '')
                        .join(', '),
                    style: const TextStyle(
                        color: Colors.blueAccent, fontSize: 13.0),
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
                    style: const TextStyle(
                        color: Colors.blueAccent, fontSize: 13.0)),
                TextSpan(text: c.text, style: const TextStyle(fontSize: 13.0)),
              ])),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int imageSize = post.images.length;
    final double larguraImagem = (Get.width - 20 - 50 - 10) /
        ((imageSize == 3 || imageSize > 4)
            ? 3.0
            : (imageSize == 2 || imageSize == 4)
                ? 2.0
                : 1.5);
    final String nome = MomentsService.instance.nomeDe(post);

    return Container(
      padding: const EdgeInsets.all(10.0),
      child: Column(children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(5.0),
              child: ImageView(
                img: 'perfil:${post.author}',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                isRadius: false,
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 10.0, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    /// Autor
                    Text(nome),

                    /// Texto
                    if (post.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(post.text),
                      ),

                    /// Fotos
                    _fotos(larguraImagem),

                    /// Hora, "Excluir" e menu de reação
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(
                                child: Text('${_tempo()} · ${_expira()}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13)),
                              ),
                              if (post.mine)
                                GestureDetector(
                                  onTap: () => _confirmarExcluir(context),
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 10.0),
                                    child: Text('Excluir',
                                        style: TextStyle(
                                            color: Colors.blueAccent)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _BotaoReacao(
                          curtido: MomentsService.instance.jaCurti(post),
                          aoCurtir: () => MomentsService.instance.curtir(post),
                          aoComentar: () => _comentar(context),
                        ),
                      ],
                    ),

                    /// Curtidas e comentários
                    _curtidasEComentarios(),
                  ],
                ),
              ),
            ),
          ],
        ),
        Container(
            height: 0.5,
            color: Colors.grey[200],
            margin: const EdgeInsets.only(top: 10)),
      ]),
    );
  }
}

/// Botão ⋯ que abre o mini menu "Curtir | Comentar".
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
      builder: (BuildContext ctx) => IconButton(
        icon: const Icon(Icons.more_horiz, color: Colors.black),
        onPressed: () {
          final RenderBox caixa = ctx.findRenderObject() as RenderBox;
          final Offset pos = caixa.localToGlobal(Offset.zero);
          Navigator.push(
            ctx,
            PopRoute(
              child: _MenuReacao(
                posicao: pos,
                curtido: curtido,
                aoCurtir: aoCurtir,
                aoComentar: aoComentar,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuReacao extends StatelessWidget {
  final Offset posicao;
  final bool curtido;
  final VoidCallback aoCurtir;
  final VoidCallback aoComentar;

  const _MenuReacao({
    required this.posicao,
    required this.curtido,
    required this.aoCurtir,
    required this.aoComentar,
  });

  @override
  Widget build(BuildContext context) {
    const TextStyle estilo = TextStyle(color: Colors.white);
    const double largura = 190.0;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: posicao.dy + 6,
              left: max(8.0, posicao.dx - largura),
              child: Container(
                width: largura,
                height: 36,
                decoration: const BoxDecoration(
                  color: itemBgColor,
                  borderRadius: BorderRadius.all(Radius.circular(4.0)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          aoCurtir();
                        },
                        child: Text(curtido ? 'Descurtir' : 'Curtir',
                            style: estilo),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          aoComentar();
                        },
                        child: const Text('Comentar', style: estilo),
                      ),
                    ),
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
