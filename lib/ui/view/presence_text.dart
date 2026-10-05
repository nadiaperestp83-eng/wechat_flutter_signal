import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wechat_flutter/core/presence_service.dart';
import 'package:wechat_flutter/tools/tr_app.dart';

/// Texto de presença: "online" ou "visto por último ...".
/// Para o próprio usuário ([isSelf]) usa o estado local; para contatos
/// acompanha o canal de presença no Supabase.
class PresenceText extends StatefulWidget {
  final String userId;
  final bool isSelf;
  final TextStyle? style;
  final TextAlign textAlign;

  const PresenceText({
    Key? key,
    required this.userId,
    this.isSelf = false,
    this.style,
    this.textAlign = TextAlign.center,
  }) : super(key: key);

  @override
  State<PresenceText> createState() => _PresenceTextState();
}

class _PresenceTextState extends State<PresenceText> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  ValueListenable<PresencaContato>? _ouvinte;

  @override
  void initState() {
    super.initState();
    _assinar();
  }

  @override
  void didUpdateWidget(covariant PresenceText antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.userId != widget.userId || antigo.isSelf != widget.isSelf) {
      _soltar(antigo.userId);
      _assinar();
    }
  }

  @override
  void dispose() {
    _soltar(widget.userId);
    super.dispose();
  }

  void _assinar() {
    if (widget.isSelf || widget.userId.isEmpty) {
      _ouvinte = null;
      return;
    }
    _ouvinte = PresenceService.instance.observar(widget.userId);
  }

  void _soltar(String userId) {
    if (_ouvinte != null) {
      PresenceService.instance.liberar(userId);
      _ouvinte = null;
    }
  }

  TextStyle _estilo(bool destaque) {
    final TextStyle base = widget.style ??
        const TextStyle(fontSize: 15.0, color: Colors.black54);
    return destaque ? base.copyWith(color: _verde) : base;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSelf) {
      return ValueListenableBuilder<bool>(
        valueListenable: PresenceService.instance.compartilhando,
        builder: (BuildContext context, bool compartilhando, Widget? _) {
          return Text(
            compartilhando
                ? trApp('online', en: 'online', zh: '在线')
                : trApp('status oculto', en: 'status hidden', zh: '状态已隐藏'),
            textAlign: widget.textAlign,
            style: _estilo(compartilhando),
          );
        },
      );
    }

    final ValueListenable<PresencaContato>? ouvinte = _ouvinte;
    if (ouvinte == null) return const SizedBox.shrink();
    return ValueListenableBuilder<PresencaContato>(
      valueListenable: ouvinte,
      builder: (BuildContext context, PresencaContato p, Widget? _) {
        final String texto = textoDePresenca(p);
        if (texto.isEmpty) return const SizedBox.shrink();
        return Text(texto,
            textAlign: widget.textAlign, style: _estilo(p.online));
      },
    );
  }
}

String _dois(int n) => n.toString().padLeft(2, '0');

/// Converte a presença em texto ("online", "visto por último hoje às 14:05").
String textoDePresenca(PresencaContato p, {DateTime? agora}) {
  if (!p.carregado) return '';
  if (p.online) return trApp('online', en: 'online', zh: '在线');
  final DateTime? quando = p.ultimaVez;
  if (quando == null) return '';

  final DateTime hoje = agora ?? DateTime.now();
  final String hora = '${_dois(quando.hour)}:${_dois(quando.minute)}';
  final DateTime diaHoje = DateTime(hoje.year, hoje.month, hoje.day);
  final DateTime diaQuando = DateTime(quando.year, quando.month, quando.day);
  final int dias = diaHoje.difference(diaQuando).inDays;

  if (hoje.difference(quando).inSeconds < 60) {
    return trApp('visto por último agora há pouco',
        en: 'last seen just now', zh: '刚刚在线');
  }
  if (dias == 0) {
    return trApp('visto por último hoje às $hora',
        en: 'last seen today at $hora', zh: '最后在线 今天 $hora');
  }
  if (dias == 1) {
    return trApp('visto por último ontem às $hora',
        en: 'last seen yesterday at $hora', zh: '最后在线 昨天 $hora');
  }
  final String data = '${_dois(quando.day)}/${_dois(quando.month)}'
      '${quando.year != hoje.year ? '/${quando.year}' : ''}';
  return trApp('visto por último em $data às $hora',
      en: 'last seen on $data at $hora', zh: '最后在线 $data $hora');
}
