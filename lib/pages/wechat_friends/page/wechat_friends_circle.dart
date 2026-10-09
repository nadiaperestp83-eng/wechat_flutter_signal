import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/pages/wechat_friends/page/publish_dynamic.dart';
import 'package:wechat_flutter/pages/wechat_friends/page/story_viewer.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

/// Posts de uma pessoa, do mais antigo ao mais novo.
class _Grupo {
  final String autor;
  final bool meu;
  final List<MomentPost> posts;

  const _Grupo(this.autor, this.meu, this.posts);

  bool get novo => !meu && posts.any((MomentPost p) => !p.seen);

  int get slides => posts.fold<int>(
      0, (int s, MomentPost p) => s + (p.images.isEmpty ? 1 : p.images.length));

  int get ultimo => posts.last.ts;
}

/// Anel em volta do avatar: um arco por slide (verde = novo, cinza = visto).
class _AnelPainter extends CustomPainter {
  final int segmentos;
  final Color cor;

  const _AnelPainter(this.segmentos, this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = cor;
    final Rect rect = Rect.fromLTWH(1.5, 1.5, size.width - 3.0, size.height - 3.0);
    final int n = segmentos.clamp(1, 30);

    if (n == 1) {
      canvas.drawArc(rect, 0.0, 2 * pi, false, pincel);
      return;
    }
    const double vao = 0.16;
    final double arco = (2 * pi - n * vao) / n;
    for (int i = 0; i < n; i++) {
      canvas.drawArc(rect, -pi / 2 + i * (arco + vao) + vao / 2, arco, false, pincel);
    }
  }

  @override
  bool shouldRepaint(covariant _AnelPainter antigo) =>
      antigo.segmentos != segmentos || antigo.cor != cor;
}

/// Aba Momentos no estilo "status": meu status no topo, depois as
/// atualizações recentes e as já vistas. Tudo some em 24 horas.
class WeChatFriendsCircle extends StatefulWidget {
  WeChatFriendsCircle({Key? key}) : super(key: key);

  @override
  createState() => _WeChatFriendsCircleState();
}

class _WeChatFriendsCircleState extends State<WeChatFriendsCircle> {
  @override
  void initState() {
    super.initState();
    // Tudo que passou de 24 h some ao abrir a tela.
    MomentsService.instance.purgarExpirados();
  }

  List<_Grupo> _agrupar(List<MomentPost> lista) {
    final Map<String, List<MomentPost>> mapa = <String, List<MomentPost>>{};
    for (final MomentPost p in lista) {
      mapa.putIfAbsent(p.mine ? '_eu' : p.author, () => <MomentPost>[]).add(p);
    }
    return mapa.entries.map((MapEntry<String, List<MomentPost>> e) {
      // listar() vem do mais novo para o mais antigo: inverte.
      final List<MomentPost> posts = e.value.reversed.toList();
      return _Grupo(posts.first.author, e.key == '_eu', posts);
    }).toList();
  }

  void _abrirViewer(List<_Grupo> ordem, int indice) {
    Get.to<void>(StoryViewerPage(
      grupos: ordem.map((_Grupo g) => g.posts).toList(),
      inicial: indice,
    ));
  }

  // ------------------------------------------------------------ publicar

  Future<void> _escolherFoto() async {
    final String? escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, 'galeria'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || escolha == null) return;

    try {
      final List<Uint8List> bytes = <Uint8List>[];
      if (escolha == 'camera') {
        final XFile? foto = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1080,
          maxHeight: 1080,
          imageQuality: 50,
        );
        if (foto == null) return;
        bytes.add(await foto.readAsBytes());
      } else {
        final List<XFile>? fotos = await ImagePicker().pickMultiImage(
          maxWidth: 1080,
          maxHeight: 1080,
          imageQuality: 50,
        );
        if (fotos == null || fotos.isEmpty) return;
        for (final XFile f in fotos.take(MomentsService.maxImagens)) {
          bytes.add(await f.readAsBytes());
        }
      }
      if (!mounted) return;
      Get.to<void>(PublishDynamicPage(images: bytes));
    } catch (e) {
      showToast('Não foi possível abrir: $e');
    }
  }

  void _escreverTexto() => Get.to<void>(const PublishDynamicPage(modoTexto: true));

  // ------------------------------------------------------------ pedaços

  Widget _avatarComAnel(String autor, int slides, bool novo, {bool meu = false}) {
    final Color cor = (novo || meu) ? _verde : Colors.grey.shade400;
    return SizedBox(
      width: 58.0,
      height: 58.0,
      child: CustomPaint(
        painter: _AnelPainter(slides, cor),
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: ClipOval(
            child: ImageView(
              img: 'perfil:$autor',
              width: 48.0,
              height: 48.0,
              fit: BoxFit.cover,
              isRadius: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _linha({
    required Widget avatar,
    required String titulo,
    required String subtitulo,
    required VoidCallback aoTocar,
  }) {
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: <Widget>[
            avatar,
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17.0, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3.0),
                  Text(subtitulo,
                      style: TextStyle(fontSize: 13.5, color: mainTextColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho(String texto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 18.0, 16.0, 6.0),
      child: Text(texto,
          style: TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.w600,
              color: mainTextColor)),
    );
  }

  Widget _meuStatus(_Grupo? meu, String meuId) {
    if (meu == null) {
      return _linha(
        avatar: SizedBox(
          width: 58.0,
          height: 58.0,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(5.0),
                child: ClipOval(
                  child: ImageView(
                    img: 'perfil:$meuId',
                    width: 48.0,
                    height: 48.0,
                    fit: BoxFit.cover,
                    isRadius: false,
                  ),
                ),
              ),
              Positioned(
                right: 0.0,
                bottom: 0.0,
                child: Container(
                  width: 22.0,
                  height: 22.0,
                  decoration: BoxDecoration(
                    color: _verde,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.0),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 14.0),
                ),
              ),
            ],
          ),
        ),
        titulo: 'Meu status',
        subtitulo: 'Toque para adicionar um momento',
        aoTocar: _escolherFoto,
      );
    }
    return _linha(
      avatar: _avatarComAnel(meuId, meu.slides, true, meu: true),
      titulo: 'Meu status',
      subtitulo: quandoStatus(meu.ultimo),
      aoTocar: () => _abrirViewer(<_Grupo>[meu], 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: ComMomBar(title: 'Momentos'),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'status_texto',
            backgroundColor: Colors.grey.shade200,
            elevation: 1.0,
            onPressed: _escreverTexto,
            child: const Icon(Icons.edit, color: Colors.black54),
          ),
          const SizedBox(height: 14.0),
          FloatingActionButton(
            heroTag: 'status_foto',
            backgroundColor: _verde,
            onPressed: _escolherFoto,
            child: const Icon(Icons.camera_alt, color: Colors.white),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: MomentsService.instance.versao,
        builder: (BuildContext context, int _, Widget? __) {
          final List<_Grupo> grupos =
              _agrupar(MomentsService.instance.listar());

          _Grupo? meu;
          final List<_Grupo> novos = <_Grupo>[];
          final List<_Grupo> vistos = <_Grupo>[];
          for (final _Grupo g in grupos) {
            if (g.meu) {
              meu = g;
            } else if (g.novo) {
              novos.add(g);
            } else {
              vistos.add(g);
            }
          }
          int porRecente(_Grupo a, _Grupo b) => b.ultimo.compareTo(a.ultimo);
          novos.sort(porRecente);
          vistos.sort(porRecente);
          final List<_Grupo> ordem = <_Grupo>[...novos, ...vistos];

          Widget linhaDe(_Grupo g, int indice) {
            final MomentPost ref = g.posts.last;
            return _linha(
              avatar: _avatarComAnel(g.autor, g.slides, g.novo),
              titulo: MomentsService.instance.nomeDe(ref),
              subtitulo: quandoStatus(g.ultimo),
              aoTocar: () => _abrirViewer(ordem, indice),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 120.0),
            children: <Widget>[
              const SizedBox(height: 6.0),
              _meuStatus(meu, model.account),
              if (ordem.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 50.0, horizontal: 30.0),
                  child: Text(
                    'Nenhum momento recente.\nOs momentos dos seus contatos aparecem aqui e somem em 24 horas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mainTextColor),
                  ),
                ),
              if (novos.isNotEmpty) _cabecalho('Atualizações recentes'),
              for (int i = 0; i < novos.length; i++) linhaDe(novos[i], i),
              if (vistos.isNotEmpty) _cabecalho('Vistos'),
              for (int i = 0; i < vistos.length; i++)
                linhaDe(vistos[i], novos.length + i),
            ],
          );
        },
      ),
    );
  }
}
