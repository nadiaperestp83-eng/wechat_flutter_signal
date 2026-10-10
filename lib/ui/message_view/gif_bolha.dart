import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Bolha de GIF do chat. O GIF viaja como texto `[gif]<url>` (cifrado como
/// qualquer mensagem) e só é mostrado se a URL for do próprio Giphy.
class GifBolha extends StatelessWidget {
  static const String marcador = '[gif]';

  final String url;
  final bool meu;

  const GifBolha({Key? key, required this.url, required this.meu})
      : super(key: key);

  /// Devolve a URL se [texto] for um GIF válido do Giphy; senão, null.
  static String? extrair(String texto) {
    if (!texto.startsWith(marcador)) return null;
    final Uri? uri = Uri.tryParse(texto.substring(marcador.length).trim());
    if (uri == null || uri.scheme != 'https') return null;
    final String host = uri.host.toLowerCase();
    if (host != 'giphy.com' && !host.endsWith('.giphy.com')) return null;
    return uri.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5.0),
      margin: const EdgeInsets.only(right: 7.0),
      decoration: BoxDecoration(
        color: meu ? const Color(0xff98E165) : Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(5.0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 190.0,
          fit: BoxFit.fitWidth,
          placeholder: (BuildContext c, String u) => const SizedBox(
            width: 190.0,
            height: 140.0,
            child: Center(
                child: SizedBox(
                    width: 22.0,
                    height: 22.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0))),
          ),
          errorWidget: (BuildContext c, String u, Object e) => const SizedBox(
            width: 190.0,
            height: 80.0,
            child: Center(
                child: Text('GIF indisponível',
                    style: TextStyle(color: Colors.black45))),
          ),
        ),
      ),
    );
  }
}
