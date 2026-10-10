import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wechat_flutter/core/giphy_service.dart';

/// Grade de GIFs com rolagem infinita. Serve para as tendências (painel do
/// chat) e para os resultados da busca.
class GifGrade extends StatefulWidget {
  /// Busca uma página a partir de [offset].
  final Future<List<GiphyGif>> Function(int offset) carregar;
  final ValueChanged<GiphyGif> aoSelecionar;
  final double paddingInferior;

  const GifGrade({
    Key? key,
    required this.carregar,
    required this.aoSelecionar,
    this.paddingInferior = 0.0,
  }) : super(key: key);

  @override
  State<GifGrade> createState() => _GifGradeState();
}

class _GifGradeState extends State<GifGrade> {
  static const int _maximo = 200;

  final List<GiphyGif> _itens = <GiphyGif>[];
  final ScrollController _rolagem = ScrollController();
  int _offset = 0;
  bool _carregando = false;
  bool _fim = false;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _rolagem.addListener(() {
      if (_rolagem.hasClients &&
          _rolagem.position.pixels > _rolagem.position.maxScrollExtent - 300.0) {
        _carregarMais();
      }
    });
    _carregarMais();
  }

  @override
  void dispose() {
    _rolagem.dispose();
    super.dispose();
  }

  Future<void> _carregarMais() async {
    if (_carregando || _fim) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final List<GiphyGif> novos = await widget.carregar(_offset);
      if (!mounted) return;
      setState(() {
        _offset += novos.length;
        for (final GiphyGif g in novos) {
          if (!_itens.any((GiphyGif x) => x.id == g.id)) _itens.add(g);
        }
        if (novos.length < GiphyService.porPagina || _offset >= _maximo) {
          _fim = true;
        }
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  String _mensagemDoErro() {
    final String texto = '$_erro';
    if (texto.contains('GIPHY_API_KEY')) {
      return 'Chave do Giphy ausente.\nCrie o secret GIPHY_API_KEY no GitHub.';
    }
    return 'Não foi possível carregar os GIFs.';
  }

  @override
  Widget build(BuildContext context) {
    if (_itens.isEmpty) {
      if (_erro != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_mensagemDoErro(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
              TextButton(
                  onPressed: _carregarMais,
                  child: const Text('Tentar de novo')),
            ],
          ),
        );
      }
      if (_fim) {
        return const Center(
          child: Text('Nenhum GIF encontrado',
              style: TextStyle(color: Colors.black54)),
        );
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    return GridView.builder(
      controller: _rolagem,
      padding: EdgeInsets.fromLTRB(4.0, 4.0, 4.0, 4.0 + widget.paddingInferior),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4.0,
        crossAxisSpacing: 4.0,
      ),
      itemCount: _itens.length + (_carregando ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i >= _itens.length) {
          return const Center(
              child: SizedBox(
                  width: 22.0,
                  height: 22.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0)));
        }
        final GiphyGif g = _itens[i];
        return GestureDetector(
          onTap: () => widget.aoSelecionar(g),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: CachedNetworkImage(
              imageUrl: g.previewUrl,
              fit: BoxFit.cover,
              placeholder: (BuildContext c, String u) =>
                  Container(color: Colors.black12),
              errorWidget: (BuildContext c, String u, Object e) =>
                  Container(color: Colors.black12),
            ),
          ),
        );
      },
    );
  }
}
