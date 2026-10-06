import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:wechat_flutter/core/call_service.dart';
import 'package:wechat_flutter/im/nome_contato.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Tela de chamada de voz/vídeo. Quem manda é o [CallService]; esta tela só
/// mostra o estado e envia os toques (mudo, alto-falante, câmera, desligar).
class CallPage extends StatefulWidget {
  const CallPage({Key? key}) : super(key: key);

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final CallService _servico = CallService.instance;
  bool _fechando = false;

  @override
  void initState() {
    super.initState();
    _servico.estado.addListener(_aoMudarEstado);
  }

  @override
  void dispose() {
    _servico.estado.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    if (_servico.estado.value == EstadoChamada.encerrada && !_fechando) {
      _fechando = true;
      // Deixa a mensagem final ("Chamada recusada"...) aparecer um instante.
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  String _tempo(int total) {
    final int m = total ~/ 60;
    final int s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _botao({
    required IconData icone,
    required VoidCallback aoTocar,
    Color fundo = const Color(0x33FFFFFF),
    Color cor = Colors.white,
  }) {
    return GestureDetector(
      onTap: aoTocar,
      child: Container(
        width: 62.0,
        height: 62.0,
        decoration: BoxDecoration(color: fundo, shape: BoxShape.circle),
        child: Icon(icone, color: cor, size: 28.0),
      ),
    );
  }

  Widget _videoRemoto(RtcEngine motor, int uid) {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: motor,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: _servico.canalAtual),
      ),
    );
  }

  Widget _videoLocal(RtcEngine motor) {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: motor,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _cabecalho(String nome) {
    return Column(
      children: <Widget>[
        ClipOval(
          child: ImageView(
            img: 'perfil:${_servico.peerAtual}',
            width: 110.0,
            height: 110.0,
            fit: BoxFit.cover,
            isRadius: false,
          ),
        ),
        const SizedBox(height: 18.0),
        Text(
          nome,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontSize: 26.0, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8.0),
        ValueListenableBuilder<EstadoChamada>(
          valueListenable: _servico.estado,
          builder: (BuildContext context, EstadoChamada estado, Widget? _) {
            return ValueListenableBuilder<String>(
              valueListenable: _servico.mensagem,
              builder: (BuildContext context, String texto, Widget? __) {
                return ValueListenableBuilder<int>(
                  valueListenable: _servico.segundos,
                  builder: (BuildContext context, int seg, Widget? ___) {
                    final String linha = estado == EstadoChamada.conectada
                        ? _tempo(seg)
                        : (texto.isNotEmpty ? texto : 'Chamando…');
                    return Text(linha,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16.0));
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String nome = NomeContato.nome(_servico.peerAtual);
    final bool video = _servico.videoAtual;

    return PopScope(
      // Voltar não desliga a chamada: ela segue em segundo plano.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xff1c1c1e),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Vídeo da outra pessoa em tela cheia.
            if (video)
              ValueListenableBuilder<RtcEngine?>(
                valueListenable: _servico.motor,
                builder: (BuildContext context, RtcEngine? motor, Widget? _) {
                  return ValueListenableBuilder<int?>(
                    valueListenable: _servico.remotoUid,
                    builder: (BuildContext context, int? uid, Widget? __) {
                      if (motor == null || uid == null) {
                        return const SizedBox.shrink();
                      }
                      return _videoRemoto(motor, uid);
                    },
                  );
                },
              ),

            // Nome/foto: no vídeo só até a outra pessoa entrar.
            SafeArea(
              child: ValueListenableBuilder<int?>(
                valueListenable: _servico.remotoUid,
                builder: (BuildContext context, int? uid, Widget? _) {
                  if (video && uid != null) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(nome,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20.0,
                                    fontWeight: FontWeight.w600,
                                    shadows: <Shadow>[
                                      Shadow(
                                          blurRadius: 6.0,
                                          color: Colors.black54)
                                    ])),
                            ValueListenableBuilder<int>(
                              valueListenable: _servico.segundos,
                              builder: (BuildContext c, int seg, Widget? __) =>
                                  Text(_tempo(seg),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14.0,
                                          shadows: <Shadow>[
                                            Shadow(
                                                blurRadius: 6.0,
                                                color: Colors.black54)
                                          ])),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Align(
                    alignment: const Alignment(0, -0.45),
                    child: _cabecalho(nome),
                  );
                },
              ),
            ),

            // Minha câmera (miniatura).
            if (video)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12.0, right: 12.0),
                    child: ValueListenableBuilder<RtcEngine?>(
                      valueListenable: _servico.motor,
                      builder: (BuildContext context, RtcEngine? motor,
                          Widget? _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _servico.cameraLigada,
                          builder: (BuildContext c, bool ligada, Widget? __) {
                            if (motor == null || !ligada) {
                              return const SizedBox.shrink();
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: SizedBox(
                                width: 100.0,
                                height: 140.0,
                                child: _videoLocal(motor),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),

            // Botões.
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      ValueListenableBuilder<bool>(
                        valueListenable: _servico.mudo,
                        builder: (BuildContext c, bool mudo, Widget? _) =>
                            _botao(
                          icone: mudo ? Icons.mic_off : Icons.mic,
                          fundo:
                              mudo ? Colors.white : const Color(0x33FFFFFF),
                          cor: mudo ? Colors.black : Colors.white,
                          aoTocar: _servico.alternarMudo,
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _servico.altoFalante,
                        builder: (BuildContext c, bool alto, Widget? _) =>
                            _botao(
                          icone: alto ? Icons.volume_up : Icons.volume_down,
                          fundo:
                              alto ? Colors.white : const Color(0x33FFFFFF),
                          cor: alto ? Colors.black : Colors.white,
                          aoTocar: _servico.alternarAltoFalante,
                        ),
                      ),
                      if (video)
                        ValueListenableBuilder<bool>(
                          valueListenable: _servico.cameraLigada,
                          builder: (BuildContext c, bool ligada, Widget? _) =>
                              _botao(
                            icone: ligada
                                ? Icons.videocam
                                : Icons.videocam_off,
                            fundo: ligada
                                ? const Color(0x33FFFFFF)
                                : Colors.white,
                            cor: ligada ? Colors.white : Colors.black,
                            aoTocar: _servico.alternarCamera,
                          ),
                        ),
                      if (video)
                        _botao(
                          icone: Icons.cameraswitch,
                          aoTocar: _servico.trocarCamera,
                        ),
                      _botao(
                        icone: Icons.call_end,
                        fundo: Colors.red,
                        aoTocar: _servico.encerrar,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
