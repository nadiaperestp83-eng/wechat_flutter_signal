import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wechat_flutter/core/giphy_service.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/chat/gif_grade.dart';

/// Busca de GIFs em tela cheia. Ao tocar num GIF, devolve o [GiphyGif]
/// escolhido para quem abriu a tela.
class GifSearchPage extends StatefulWidget {
  const GifSearchPage({Key? key}) : super(key: key);

  @override
  State<GifSearchPage> createState() => _GifSearchPageState();
}

class _GifSearchPageState extends State<GifSearchPage> {
  final TextEditingController _campo = TextEditingController();
  Timer? _espera;
  String _termo = '';

  @override
  void dispose() {
    _espera?.cancel();
    _campo.dispose();
    super.dispose();
  }

  void _aoDigitar(String texto) {
    _espera?.cancel();
    // Só busca quando a pessoa para de digitar.
    _espera = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _termo = texto.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0.0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: TextField(
          controller: _campo,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _aoDigitar,
          onSubmitted: (String t) {
            _espera?.cancel();
            setState(() => _termo = t.trim());
          },
          decoration: InputDecoration(
            hintText: 'Buscar GIFs',
            border: InputBorder.none,
            suffixIcon: _campo.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, color: Colors.black45),
                    onPressed: () {
                      _campo.clear();
                      setState(() => _termo = '');
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: GifGrade(
              // Nova busca = grade nova.
              key: ValueKey<String>('busca:$_termo'),
              carregar: (int offset) => _termo.isEmpty
                  ? GiphyService.instance.tendencias(offset: offset)
                  : GiphyService.instance.buscar(_termo, offset: offset),
              aoSelecionar: (GiphyGif g) => Navigator.of(context).pop(g),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Text('Powered by GIPHY',
                  style: TextStyle(fontSize: 11.0, color: Colors.grey[500])),
            ),
          ),
        ],
      ),
    );
  }
}
