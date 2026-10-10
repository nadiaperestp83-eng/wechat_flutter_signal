import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wechat_flutter/config/giphy_config.dart';

/// Um GIF do Giphy.
class GiphyGif {
  final String id;

  /// Versão leve (para a grade).
  final String previewUrl;

  /// Versão enviada no chat (200 px de largura).
  final String url;

  const GiphyGif({
    required this.id,
    required this.previewUrl,
    required this.url,
  });
}

/// Busca de GIFs na API do Giphy.
class GiphyService {
  GiphyService._();
  static final GiphyService instance = GiphyService._();

  static const int porPagina = 24;

  Future<List<GiphyGif>> tendencias({int offset = 0}) {
    return _pedir('/v1/gifs/trending', <String, String>{
      'limit': '$porPagina',
      'offset': '$offset',
    });
  }

  Future<List<GiphyGif>> buscar(String termo, {int offset = 0}) {
    return _pedir('/v1/gifs/search', <String, String>{
      'q': termo,
      'limit': '$porPagina',
      'offset': '$offset',
      'lang': 'pt',
    });
  }

  Future<List<GiphyGif>> _pedir(
      String caminho, Map<String, String> parametros) async {
    if (kGiphyApiKey.isEmpty) {
      throw StateError('GIPHY_API_KEY ausente');
    }

    final Uri uri = Uri.https('api.giphy.com', caminho, <String, String>{
      'api_key': kGiphyApiKey,
      'rating': 'pg',
      ...parametros,
    });

    final http.Response resposta =
        await http.get(uri).timeout(const Duration(seconds: 12));
    if (resposta.statusCode != 200) {
      throw StateError('Giphy respondeu ${resposta.statusCode}');
    }

    final dynamic corpo = jsonDecode(resposta.body);
    final List<dynamic> dados = (corpo is Map ? corpo['data'] : null) as List<dynamic>? ?? <dynamic>[];

    final List<GiphyGif> lista = <GiphyGif>[];
    for (final dynamic item in dados) {
      if (item is! Map) continue;
      final dynamic imagens = item['images'];
      if (imagens is! Map) continue;
      final String? url = _url(imagens['fixed_width']);
      if (url == null) continue;
      lista.add(GiphyGif(
        id: item['id'] as String,
        previewUrl: _url(imagens['fixed_width_small']) ?? url,
        url: url,
      ));
    }
    return lista;
  }

  String? _url(dynamic rendicao) {
    if (rendicao is Map) {
      final dynamic u = rendicao['url'];
      if (u is String && u.isNotEmpty) return u;
    }
    return null;
  }
}
