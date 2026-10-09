import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Criar um status: fotos com legenda, ou um cartão de texto com fundo colorido.
/// O post é cifrado no aparelho e entregue aos contatos conectados agora;
/// nada fica gravado no servidor e tudo some em 24 horas.
class PublishDynamicPage extends StatefulWidget {
  final List<Uint8List> images;
  final bool modoTexto;

  const PublishDynamicPage(
      {Key? key, this.images = const <Uint8List>[], this.modoTexto = false})
      : super(key: key);

  @override
  createState() => _PublishDynamicPageState();
}

class _PublishDynamicPageState extends State<PublishDynamicPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  /// Fundos dos cartões de texto (o primeiro é o verde do app).
  static const List<int> _cores = <int>[
    0xff08bf62,
    0xff1f2c34,
    0xff7e57c2,
    0xffe65100,
    0xff0277bd,
    0xffc2185b,
    0xff455a64,
    0xff2e7d32,
  ];

  late List<Uint8List> _imagens;
  final TextEditingController _textoC = TextEditingController();
  final PageController _paginas = PageController();
  int _cor = 0;
  int _pagina = 0;
  bool _enviando = false;

  bool get _modoTexto => _imagens.isEmpty;

  @override
  void initState() {
    super.initState();
    _imagens = List<Uint8List>.from(widget.images);
  }

  @override
  void dispose() {
    _textoC.dispose();
    _paginas.dispose();
    super.dispose();
  }

  Future<void> _adicionarFotos() async {
    final int faltam = MomentsService.maxImagens - _imagens.length;
    if (faltam <= 0) {
      showToast('No máximo ${MomentsService.maxImagens} fotos');
      return;
    }
    try {
      final List<XFile>? fotos = await ImagePicker().pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 50,
      );
      if (fotos == null || fotos.isEmpty) return;
      final List<Uint8List> novas = <Uint8List>[];
      for (final XFile f in fotos.take(faltam)) {
        novas.add(await f.readAsBytes());
      }
      if (mounted) setState(() => _imagens.addAll(novas));
    } catch (e) {
      showToast('Não foi possível abrir a galeria: $e');
    }
  }

  void _removerAtual() {
    if (_imagens.isEmpty) return;
    setState(() {
      _imagens.removeAt(_pagina.clamp(0, _imagens.length - 1));
      if (_pagina >= _imagens.length) _pagina = _imagens.isEmpty ? 0 : _imagens.length - 1;
    });
  }

  Future<void> _publicar() async {
    if (_enviando) return;
    final String texto = _textoC.text.trim();
    if (_modoTexto && texto.isEmpty) {
      showToast('Digite algo para publicar');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _enviando = true);
    try {
      await MomentsService.instance.publicar(
        texto: texto,
        imagens: _imagens,
        bg: _modoTexto ? _cores[_cor] : null,
      );
      showToast('Momento publicado. Ele some em 24 horas.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showToast('Não foi possível publicar: $e');
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _botaoEnviar() {
    return FloatingActionButton(
      heroTag: 'status_enviar',
      backgroundColor: _verde,
      onPressed: _enviando ? null : _publicar,
      child: _enviando
          ? const SizedBox(
              width: 22.0,
              height: 22.0,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          : const Icon(Icons.send, color: Colors.white),
    );
  }

  // ------------------------------------------------------- cartão de texto

  Widget _telaTexto() {
    return Scaffold(
      backgroundColor: Color(_cores[_cor]),
      floatingActionButton: _botaoEnviar(),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Adicionar fotos',
                  icon: const Icon(Icons.photo_library_outlined,
                      color: Colors.white),
                  onPressed: _adicionarFotos,
                ),
                IconButton(
                  tooltip: 'Trocar a cor',
                  icon: const Icon(Icons.palette_outlined, color: Colors.white),
                  onPressed: () =>
                      setState(() => _cor = (_cor + 1) % _cores.length),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: TextField(
                    controller: _textoC,
                    autofocus: true,
                    maxLines: null,
                    maxLength: 400,
                    textAlign: TextAlign.center,
                    cursorColor: Colors.white,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 32.0,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      hintText: 'Digite um momento',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 32.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 80.0),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- fotos

  Widget _telaFotos() {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: _paginas,
            itemCount: _imagens.length,
            onPageChanged: (int i) => setState(() => _pagina = i),
            itemBuilder: (BuildContext c, int i) => Center(
              child: Image.memory(_imagens[i],
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (_imagens.length > 1)
                      Text('${_pagina + 1}/${_imagens.length}',
                          style: const TextStyle(color: Colors.white)),
                    IconButton(
                      tooltip: 'Adicionar mais fotos',
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white),
                      onPressed: _adicionarFotos,
                    ),
                    IconButton(
                      tooltip: 'Remover esta foto',
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                      onPressed: _removerAtual,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                color: Colors.black45,
                padding: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 10.0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _textoC,
                        maxLines: 3,
                        minLines: 1,
                        maxLength: 400,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Adicionar legenda…',
                          hintStyle: const TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Colors.white12,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18.0, vertical: 12.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26.0),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    SizedBox(width: 56.0, height: 56.0, child: _botaoEnviar()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _modoTexto ? _telaTexto() : _telaFotos();
  }
}
