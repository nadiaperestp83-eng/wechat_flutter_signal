import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/im/send_handle.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Um slide do status: cada foto de um post é um slide; post só de texto é um
/// cartão colorido.
class _Slide {
  final MomentPost post;
  final int indice;
  const _Slide(this.post, this.indice);

  Uint8List? get imagem => post.images.isEmpty ? null : post.images[indice];
}

String _dois(int n) => n.toString().padLeft(2, '0');

/// "hoje às 09:51", "ontem às 09:51" ou "08/09 às 09:51".
String quandoStatus(int ts) {
  final DateTime q = DateTime.fromMillisecondsSinceEpoch(ts);
  final DateTime agora = DateTime.now();
  final int dias = DateTime(agora.year, agora.month, agora.day)
      .difference(DateTime(q.year, q.month, q.day))
      .inDays;
  final String hora = '${_dois(q.hour)}:${_dois(q.minute)}';
  if (dias == 0) return 'hoje às $hora';
  if (dias == 1) return 'ontem às $hora';
  return '${_dois(q.day)}/${_dois(q.month)} às $hora';
}

/// Visualizador de status em tela cheia (barras de progresso, toque nos lados,
/// segurar para pausar, arrastar para baixo para fechar).
class StoryViewerPage extends StatefulWidget {
  /// Cada item é o conjunto de posts de UMA pessoa, do mais antigo ao mais novo.
  final List<List<MomentPost>> grupos;
  final int inicial;

  const StoryViewerPage({Key? key, required this.grupos, this.inicial = 0})
      : super(key: key);

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with SingleTickerProviderStateMixin {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  late List<List<MomentPost>> _grupos;
  int _g = 0;
  int _s = 0;
  late final AnimationController _anim;
  final TextEditingController _respostaC = TextEditingController();
  final FocusNode _respostaF = FocusNode();
  bool _fechando = false;

  @override
  void initState() {
    super.initState();
    _grupos = widget.grupos
        .where((List<MomentPost> g) => g.isNotEmpty)
        .map((List<MomentPost> g) => List<MomentPost>.from(g))
        .toList();
    _g = widget.inicial.clamp(0, _grupos.isEmpty ? 0 : _grupos.length - 1);

    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addStatusListener((AnimationStatus st) {
        if (st == AnimationStatus.completed) _proximo();
      });
    _respostaF.addListener(() {
      if (_respostaF.hasFocus) {
        _anim.stop();
      } else {
        _anim.forward();
      }
    });
    _respostaC.addListener(() => setState(() {}));

    if (_grupos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fechar());
    } else {
      _abrirSlide();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _respostaC.dispose();
    _respostaF.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- navegação

  List<_Slide> _slides(int g) {
    final List<_Slide> out = <_Slide>[];
    for (final MomentPost p in _grupos[g]) {
      final int n = p.images.isEmpty ? 1 : p.images.length;
      for (int i = 0; i < n; i++) {
        out.add(_Slide(p, i));
      }
    }
    return out;
  }

  _Slide get _atual => _slides(_g)[_s];

  void _abrirSlide() {
    final _Slide sl = _atual;
    _anim.duration = Duration(seconds: sl.post.images.isEmpty ? 7 : 6);
    _anim.forward(from: 0);
    MomentsService.instance.marcarVisto(sl.post);
    if (mounted) setState(() {});
  }

  void _proximo() {
    if (_fechando || _grupos.isEmpty) return;
    if (_s < _slides(_g).length - 1) {
      _s++;
    } else if (_g < _grupos.length - 1) {
      _g++;
      _s = 0;
    } else {
      _fechar();
      return;
    }
    _abrirSlide();
  }

  void _anterior() {
    if (_s > 0) {
      _s--;
    } else if (_g > 0) {
      _g--;
      _s = _slides(_g).length - 1;
    }
    _abrirSlide();
  }

  void _fechar() {
    if (_fechando) return;
    _fechando = true;
    if (mounted) Navigator.of(context).maybePop();
  }

  void _aoTocar(TapUpDetails d, double largura) {
    if (_respostaF.hasFocus) {
      _respostaF.unfocus();
      return;
    }
    if (d.localPosition.dx < largura / 3) {
      _anterior();
    } else {
      _proximo();
    }
  }

  // ------------------------------------------------------------- ações

  Future<void> _responder(MomentPost post) async {
    final String texto = _respostaC.text.trim();
    if (texto.isEmpty) return;
    _respostaC.clear();
    _respostaF.unfocus();
    // Vira uma mensagem comum no chat com o autor.
    await sendTextMsg(
        post.author, ConversationType.V2TIM_C2C, 'Resposta ao status: $texto');
    showToast('Resposta enviada');
  }

  Future<void> _excluir(MomentPost post) async {
    _anim.stop();
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
    if (sim != true) {
      _anim.forward();
      return;
    }

    await MomentsService.instance.excluir(post);
    _grupos[_g].removeWhere((MomentPost p) => p.id == post.id);
    if (_grupos[_g].isEmpty) {
      _grupos.removeAt(_g);
      if (_grupos.isEmpty) {
        _fechar();
        return;
      }
      if (_g >= _grupos.length) _g = _grupos.length - 1;
      _s = 0;
    } else {
      final int total = _slides(_g).length;
      if (_s >= total) _s = total - 1;
    }
    _abrirSlide();
  }

  void _abrirVisualizacoes(MomentPost post) {
    _anim.stop();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18.0))),
      builder: (BuildContext ctx) {
        return ValueListenableBuilder<int>(
          valueListenable: MomentsService.instance.versao,
          builder: (BuildContext c, int _, Widget? __) {
            final MomentPost fresco =
                MomentsService.instance.obter(post.id) ?? post;
            final List<Map<String, dynamic>> vistos =
                List<Map<String, dynamic>>.from(fresco.views)
                  ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
                      ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0));
            final Set<String> reagiram = fresco.likes
                .map((Map<String, String> l) => l['id'] ?? '')
                .toSet();

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20.0, 18.0, 20.0, 8.0),
                      child: Text(
                        vistos.isEmpty
                            ? 'Ninguém viu ainda'
                            : 'Visto por ${vistos.length}',
                        style: const TextStyle(
                            fontSize: 17.0, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: vistos.length,
                        itemBuilder: (BuildContext c2, int i) {
                          final Map<String, dynamic> v = vistos[i];
                          final String id = v['id'] as String;
                          final String nome =
                              MomentsService.instance.nomeDeId(id, v['name'] as String?);
                          return ListTile(
                            leading: ClipOval(
                              child: ImageView(
                                img: 'perfil:$id',
                                width: 42.0,
                                height: 42.0,
                                fit: BoxFit.cover,
                                isRadius: false,
                              ),
                            ),
                            title: Text(nome),
                            subtitle: Text(
                                quandoStatus((v['ts'] as num?)?.toInt() ?? 0)),
                            trailing: reagiram.contains(id)
                                ? const Icon(Icons.favorite,
                                    color: Colors.red, size: 20.0)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted && !_fechando) _anim.forward();
    });
  }

  // ------------------------------------------------------------ pedaços

  Widget _conteudo(_Slide sl) {
    final MomentPost p = sl.post;
    final Uint8List? img = sl.imagem;

    if (img != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Container(color: Colors.black),
          Center(
              child: Image.memory(img,
                  fit: BoxFit.contain, gaplessPlayback: true)),
          if (p.text.isNotEmpty)
            Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 96.0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 12.0),
                color: Colors.black45,
                child: Text(
                  p.text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 17.0, height: 1.3),
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      color: Color(p.bg ?? 0xff08bf62),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Text(
        p.text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: p.text.length > 90 ? 24.0 : 34.0,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _barras(int total) {
    return Row(
      children: List<Widget>.generate(total, (int i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2.0),
              child: AnimatedBuilder(
                animation: _anim,
                builder: (BuildContext context, Widget? _) {
                  final double v = i < _s ? 1.0 : (i == _s ? _anim.value : 0.0);
                  return LinearProgressIndicator(
                    value: v,
                    minHeight: 3.0,
                    backgroundColor: Colors.white30,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  );
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _topo(_Slide sl, int total) {
    final MomentPost p = sl.post;
    final String nome = p.mine ? 'Meu status' : MomentsService.instance.nomeDe(p);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 14.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _barras(total),
              const SizedBox(height: 8.0),
              Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _fechar,
                  ),
                  ClipOval(
                    child: ImageView(
                      img: 'perfil:${p.author}',
                      width: 40.0,
                      height: 40.0,
                      fit: BoxFit.cover,
                      isRadius: false,
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.0,
                                fontWeight: FontWeight.w600)),
                        Text(quandoStatus(p.ts),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (p.mine)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onOpened: _anim.stop,
                      onCanceled: _anim.forward,
                      onSelected: (String v) {
                        if (v == 'excluir') _excluir(p);
                      },
                      itemBuilder: (BuildContext c) =>
                          const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                            value: 'excluir',
                            child: Text('Excluir',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rodapeMeu(MomentPost post) {
    return ValueListenableBuilder<int>(
      valueListenable: MomentsService.instance.versao,
      builder: (BuildContext context, int _, Widget? __) {
        final MomentPost fresco =
            MomentsService.instance.obter(post.id) ?? post;
        final int n = fresco.views.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _abrirVisualizacoes(fresco),
          child: Container(
            width: double.infinity,
            color: Colors.black,
            padding: EdgeInsets.fromLTRB(
                20.0, 12.0, 20.0, 12.0 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: <Widget>[
                const Icon(Icons.visibility_outlined,
                    color: Colors.white, size: 22.0),
                const SizedBox(width: 10.0),
                Text(n == 1 ? '1 viu' : '$n viram',
                    style: const TextStyle(color: Colors.white, fontSize: 16.0)),
                const Spacer(),
                const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rodapeAmigo(MomentPost post) {
    return ValueListenableBuilder<int>(
      valueListenable: MomentsService.instance.versao,
      builder: (BuildContext context, int _, Widget? __) {
        final MomentPost fresco =
            MomentsService.instance.obter(post.id) ?? post;
        final bool curtido = MomentsService.instance.jaCurti(fresco);
        final bool temTexto = _respostaC.text.trim().isNotEmpty;

        return Container(
          color: Colors.black,
          padding: EdgeInsets.fromLTRB(
              12.0, 8.0, 12.0, 8.0 + MediaQuery.of(context).padding.bottom),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _respostaC,
                  focusNode: _respostaF,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _responder(post),
                  style: const TextStyle(color: Colors.white, fontSize: 16.0),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: 'Responder',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white12,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18.0, vertical: 12.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26.0),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: temTexto
                        ? IconButton(
                            icon: const Icon(Icons.send, color: _verde),
                            onPressed: () => _responder(post),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
              IconButton(
                icon: Icon(curtido ? Icons.favorite : Icons.favorite_border,
                    color: curtido ? Colors.red : Colors.white, size: 28.0),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  MomentsService.instance.curtir(fresco);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_grupos.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final List<_Slide> slides = _slides(_g);
    final _Slide sl = slides[_s.clamp(0, slides.length - 1)];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (TapUpDetails d) => _aoTocar(d, c.maxWidth),
                        onLongPressStart: (_) => _anim.stop(),
                        onLongPressEnd: (_) {
                          if (!_respostaF.hasFocus) _anim.forward();
                        },
                        onVerticalDragEnd: (DragEndDetails d) {
                          final double v = d.primaryVelocity ?? 0.0;
                          if (v > 300.0) {
                            _fechar();
                          } else if (v < -300.0 && sl.post.mine) {
                            _abrirVisualizacoes(sl.post);
                          }
                        },
                        child: _conteudo(sl),
                      ),
                      Positioned(
                        top: 0.0,
                        left: 0.0,
                        right: 0.0,
                        child: _topo(sl, slides.length),
                      ),
                    ],
                  );
                },
              ),
            ),
            sl.post.mine ? _rodapeMeu(sl.post) : _rodapeAmigo(sl.post),
          ],
        ),
      ),
    );
  }
}
