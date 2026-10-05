import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wechat_flutter/config/const.dart';
import 'package:wechat_flutter/core/profile_service.dart';

/// Prefixo usado no lugar de uma URL para dizer "a foto de perfil deste
/// usuário, cifrada". Ex.: `perfil:ana@email.com`.
/// O [ImageView] reconhece esse prefixo e usa este widget.
const String kPrefixoPerfil = 'perfil:';

String urlDePerfil(String userId) => '$kPrefixoPerfil$userId';

/// Mostra a foto de perfil de [userId] já decifrada no aparelho.
/// Enquanto não houver foto (ou a Profile Key do contato), mostra o
/// [placeholder] (ou o avatar padrão do app).
class PerfilFoto extends StatefulWidget {
  final String userId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final WidgetBuilder? placeholder;

  const PerfilFoto({
    Key? key,
    required this.userId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  }) : super(key: key);

  @override
  State<PerfilFoto> createState() => _PerfilFotoState();
}

class _PerfilFotoState extends State<PerfilFoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = ProfileService.instance.fotoEmCache(widget.userId);
    ProfileService.instance.versao.addListener(_aoMudar);
    _carregar();
  }

  @override
  void didUpdateWidget(covariant PerfilFoto antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.userId != widget.userId) {
      _bytes = ProfileService.instance.fotoEmCache(widget.userId);
      _carregar();
    }
  }

  @override
  void dispose() {
    ProfileService.instance.versao.removeListener(_aoMudar);
    super.dispose();
  }

  void _aoMudar() {
    if (!mounted) return;
    final Uint8List? novo = ProfileService.instance.fotoEmCache(widget.userId);
    if (!identical(novo, _bytes)) {
      setState(() => _bytes = novo);
    }
  }

  Future<void> _carregar() async {
    final String id = widget.userId;
    final Uint8List? foto = await ProfileService.instance.carregarFoto(id);
    if (!mounted || id != widget.userId) return;
    if (_bytes == null && foto != null) {
      setState(() => _bytes = foto);
    }
  }

  Widget _padrao(BuildContext context) {
    final WidgetBuilder? construtor = widget.placeholder;
    if (construtor != null) return construtor(context);
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black26.withOpacity(0.1),
        border: Border.all(color: Colors.black.withOpacity(0.2), width: 0.3),
      ),
      child: Image.asset(
        defIcon,
        width: widget.width != null ? widget.width! - 1 : null,
        height: widget.height != null ? widget.height! - 1 : null,
        fit: widget.width != null && widget.height != null
            ? BoxFit.fill
            : widget.fit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;
    if (bytes == null) return _padrao(context);
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => _padrao(c),
    );
  }
}
