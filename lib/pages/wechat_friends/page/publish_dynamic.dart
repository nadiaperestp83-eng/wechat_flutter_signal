import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import '../chat_style.dart';

/// Publicar um Momento: texto e até 9 fotos.
/// O post é cifrado no aparelho e entregue só a quem está conectado agora;
/// nada fica gravado no servidor e tudo some em 24 horas.
class PublishDynamicPage extends StatefulWidget {
  final List<Uint8List> images;
  final int maxImages;

  const PublishDynamicPage(
      {Key? key, this.images = const <Uint8List>[], this.maxImages = 9})
      : super(key: key);

  @override
  createState() => _PublishDynamicPageState();
}

class _PublishDynamicPageState extends State<PublishDynamicPage> {
  late List<Uint8List> _imagens;
  final TextEditingController _texto = TextEditingController();
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _imagens = List<Uint8List>.from(widget.images);
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  int get _total =>
      _imagens.fold<int>(0, (int s, Uint8List b) => s + b.length);

  Future<void> _adicionar() async {
    final int faltam = widget.maxImages - _imagens.length;
    if (faltam <= 0) return;
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

  Future<void> _publicar() async {
    if (_enviando) return;
    if (_texto.text.trim().isEmpty && _imagens.isEmpty) {
      showToast('Escreva algo ou escolha uma foto');
      return;
    }
    if (_total > MomentsService.maxBytesTotal) {
      showToast('As fotos estão pesadas demais. Remova algumas.');
      return;
    }
    setState(() => _enviando = true);
    try {
      await MomentsService.instance
          .publicar(texto: _texto.text, imagens: _imagens);
      showToast('Momento publicado. Ele some em 24 horas.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showToast('Não foi possível publicar: $e');
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _miniatura(int indice) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.memory(_imagens[indice], fit: BoxFit.cover),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => setState(() => _imagens.removeAt(indice)),
            child: Container(
              color: Colors.black54,
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool podeAdicionar = _imagens.length < widget.maxImages;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        elevation: 0.0,
        actions: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10),
            child: ElevatedButton(
                onPressed: _enviando ? null : _publicar,
                child: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Publicar',
                        style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom()),
          )
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: <Widget>[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10.0),
              height: 120,
              child: TextField(
                controller: _texto,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'O que você está pensando?',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Line(color: Colors.grey),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10.0),
              child: GridView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _imagens.length + (podeAdicionar ? 1 : 0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4.0,
                    mainAxisSpacing: 4.0),
                itemBuilder: (BuildContext context, int i) {
                  if (i == _imagens.length) {
                    return GestureDetector(
                      onTap: _adicionar,
                      child: Container(
                        color: Colors.grey[200],
                        child:
                            const Icon(Icons.add, size: 36, color: Colors.grey),
                      ),
                    );
                  }
                  return _miniatura(i);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Seu momento é criptografado neste aparelho e enviado só para '
                'os contatos conectados agora. Nada fica guardado no servidor '
                'e ele some em 24 horas.',
                style: TextStyles.textGrey14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
