import 'package:flutter/material.dart';
import 'package:wechat_flutter/core/call_log.dart';
import 'package:wechat_flutter/core/call_service.dart';
import 'package:wechat_flutter/im/nome_contato.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Aba "Ligações": chamadas feitas, recebidas e perdidas.
/// O histórico fica só neste aparelho (Hive) e só some quando você apaga.
class CallsPage extends StatefulWidget {
  const CallsPage({Key? key}) : super(key: key);

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage>
    with AutomaticKeepAliveClientMixin<CallsPage> {
  @override
  bool get wantKeepAlive => true;

  String _hora(int ts) {
    final DateTime quando = DateTime.fromMillisecondsSinceEpoch(ts);
    final DateTime agora = DateTime.now();
    String dois(int n) => n.toString().padLeft(2, '0');

    final DateTime diaHoje = DateTime(agora.year, agora.month, agora.day);
    final DateTime diaQuando = DateTime(quando.year, quando.month, quando.day);
    final int dias = diaHoje.difference(diaQuando).inDays;

    if (dias == 0) return '${dois(quando.hour)}:${dois(quando.minute)}';
    if (dias == 1) return 'Ontem';
    final String data = '${dois(quando.day)}/${dois(quando.month)}';
    return quando.year == agora.year ? data : '$data/${quando.year}';
  }

  String _duracao(int seg) {
    final int m = seg ~/ 60;
    final int s = seg % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _rotulo(CallRecord r) {
    final String tipo = r.video ? 'Vídeo' : 'Voz';
    switch (r.resultado) {
      case 'atendida':
        return '${r.entrada ? 'Recebida' : 'Feita'} · $tipo · ${_duracao(r.dur)}';
      case 'recusada':
        return 'Recusada · $tipo';
      case 'ocupado':
        return 'Ocupado · $tipo';
      case 'semResposta':
        return 'Sem resposta · $tipo';
      default:
        return 'Perdida · $tipo';
    }
  }

  IconData _seta(CallRecord r) {
    if (!r.entrada) return Icons.call_made;
    return r.perdida ? Icons.call_missed : Icons.call_received;
  }

  Future<void> _confirmarApagar(CallRecord r) async {
    final bool? sim = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Apagar esta ligação?'),
        content: const Text('Ela será removida do histórico deste aparelho.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Apagar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (sim == true) await CallLog.instance.apagar(r.id);
  }

  Future<void> _confirmarLimpar() async {
    final bool? sim = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Limpar o histórico?'),
        content: const Text(
            'Todas as ligações serão removidas deste aparelho.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Limpar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (sim == true) await CallLog.instance.limpar();
  }

  Widget _item(CallRecord r) {
    final String nome = NomeContato.nome(r.peer);
    final Color corLinha = r.perdida ? Colors.red : mainTextColor;

    return InkWell(
      // Toque: liga de volta no mesmo tipo (voz ou vídeo).
      onTap: () => CallService.instance.ligar(r.peer, video: r.video),
      onLongPress: () => _confirmarApagar(r),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10.0),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(5.0),
              child: ImageView(
                img: 'perfil:${r.peer}',
                width: 50.0,
                height: 50.0,
                fit: BoxFit.cover,
                isRadius: false,
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17.0,
                      color: r.perdida ? Colors.red : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Row(
                    children: <Widget>[
                      Icon(_seta(r), size: 14.0, color: corLinha),
                      const SizedBox(width: 4.0),
                      Flexible(
                        child: Text(
                          _rotulo(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: corLinha),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(_hora(r.ts),
                    style: TextStyle(fontSize: 13.0, color: mainTextColor)),
                const SizedBox(height: 6.0),
                // Ícones do próprio fork.
                Image.asset(
                  r.video
                      ? 'assets/images/contact/ic_video.png'
                      : 'assets/images/contact/ic_voice.png',
                  width: 22.0,
                  height: 22.0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: chatBg,
      child: ValueListenableBuilder<int>(
        valueListenable: CallLog.instance.versao,
        builder: (BuildContext context, int _, Widget? __) {
          final List<CallRecord> lista = CallLog.instance.listar();

          if (lista.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Text(
                  'Nenhuma ligação ainda.\nAs chamadas feitas, recebidas e perdidas aparecem aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mainTextColor),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: lista.length + 1,
            separatorBuilder: (BuildContext c, int i) =>
                Divider(height: 0.5, indent: 77.0, color: Colors.grey[300]),
            itemBuilder: (BuildContext context, int i) {
              if (i == lista.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18.0),
                  child: Center(
                    child: TextButton(
                      onPressed: _confirmarLimpar,
                      child: Text('Limpar histórico',
                          style: TextStyle(color: mainTextColor)),
                    ),
                  ),
                );
              }
              return _item(lista[i]);
            },
          );
        },
      ),
    );
  }
}
