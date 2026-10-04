import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'package:wechat_flutter/tools/date.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/dialog/voice_dialog.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

typedef VoiceFile = void Function(String path);

class ChatVoice extends StatefulWidget {
  final VoiceFile? voiceFile;

  /// Duração da gravação, em segundos (chamado antes de enviar o áudio).
  final ValueChanged<int>? onDuration;

  ChatVoice({this.voiceFile, this.onDuration});

  @override
  _ChatVoiceWidgetState createState() => _ChatVoiceWidgetState();
}

class _ChatVoiceWidgetState extends State<ChatVoice> {
  static const String _textoPadrao = 'Segure para falar';

  double startY = 0.0;
  double offset = 0.0;
  int? index;

  bool isUp = false;
  String textShow = _textoPadrao;
  String toastShow = 'Deslize para cima para cancelar';
  String voiceIco = "images/voice_volume_1.png";

  ///默认隐藏状态
  bool voiceState = true;
  OverlayEntry? overlayEntry;

  // --- Gravação (flutter_sound) ---
  FlutterSoundRecorder? _recorder;
  Future<void>? _inicio;
  String? _arquivo;
  String? _erroGravacao;
  final Stopwatch _cronometro = Stopwatch();
  bool _gravando = false;
  bool _permissaoOk = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting();
    Permission.microphone.status.then((s) => _permissaoOk = s.isGranted);
  }

  @override
  void dispose() {
    overlayEntry?.remove();
    overlayEntry = null;
    _recorder?.closeRecorder();
    super.dispose();
  }

  Future<void> _pedirPermissao() async {
    final status = await Permission.microphone.request();
    _permissaoOk = status.isGranted;
    if (_permissaoOk) {
      showToast('Microfone liberado. Segure o botão de novo para gravar.');
    } else if (status.isPermanentlyDenied) {
      showToast('Permissão do microfone bloqueada. Ative nas configurações do app.');
      openAppSettings();
    } else {
      showToast('Precisamos do microfone para gravar áudio.');
    }
  }

  Future<void> _abrirEIniciar() async {
    try {
      _erroGravacao = null;
      _recorder ??= FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _arquivo =
          '${Directory.systemTemp.path}/voz_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder!.startRecorder(toFile: _arquivo, codec: Codec.aacMP4);
    } catch (e) {
      _erroGravacao = e.toString();
    }
  }

  void start() {
    _cronometro
      ..reset()
      ..start();
    _inicio = _abrirEIniciar();
  }

  /// Para a gravação e devolve o caminho do arquivo (ou null se falhou).
  Future<String?> stop() async {
    try {
      await _inicio;
      _cronometro.stop();
      if (_erroGravacao != null) {
        showToast('Não foi possível gravar: $_erroGravacao');
        return null;
      }
      final rec = _recorder;
      if (rec == null) return null;
      final String? saida = await rec.stopRecorder();
      await rec.closeRecorder();
      _recorder = null;
      return saida ?? _arquivo;
    } catch (e) {
      showToast('Erro ao parar a gravação: $e');
      return null;
    }
  }

  void showVoiceView() {
    if (_gravando) return;
    if (!_permissaoOk) {
      _pedirPermissao();
      return;
    }
    _gravando = true;

    setState(() {
      textShow = 'Solte para enviar';
      voiceState = false;
      DateTime now = DateTime.now();
      int date = now.millisecondsSinceEpoch;
      DateTime current = DateTime.fromMillisecondsSinceEpoch(date);

      String recordingTime =
          DateTimeForMater.formatDateV(current, format: "ss:SS");
      index = int.parse(recordingTime.substring(3, 5));
    });

    start();

    if (overlayEntry == null) {
      overlayEntry = showVoiceDialog(context, index: index!);
    }
  }

  Future<void> hideVoiceView() async {
    if (!_gravando) return;
    _gravando = false;
    final bool cancelar = isUp;

    if (mounted) {
      setState(() {
        textShow = _textoPadrao;
        voiceState = true;
      });
    }
    overlayEntry?.remove();
    overlayEntry = null;

    final String? arquivo = await stop();
    final int milissegundos = _cronometro.elapsedMilliseconds;
    isUp = false;

    if (arquivo == null) return;

    Future<void> descartar() async {
      try {
        await File(arquivo).delete();
      } catch (_) {}
    }

    if (cancelar) {
      showToast('Envio cancelado');
      await descartar();
      return;
    }
    if (milissegundos < 1000) {
      showToast('Segure o botão para gravar');
      await descartar();
      return;
    }

    widget.voiceFile?.call(arquivo);
    widget.onDuration?.call((milissegundos / 1000).round());
    Notice.send(WeChatActions.voiceImg(), true);
  }

  void moveVoiceView() {
    setState(() {
      isUp = startY - offset > 100;
      if (isUp) {
        textShow = 'Solte para cancelar';
        toastShow = textShow;
      } else {
        textShow = 'Solte para enviar';
        toastShow = 'Deslize para cima para cancelar';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (details) {
        startY = details.globalPosition.dy;
        showVoiceView();
      },
      onVerticalDragDown: (details) {
        startY = details.globalPosition.dy;
        showVoiceView();
      },
      onVerticalDragCancel: hideVoiceView,
      onVerticalDragEnd: (details) => hideVoiceView(),
      onVerticalDragUpdate: (details) {
        offset = details.globalPosition.dy;
        moveVoiceView();
      },
      child: Container(
        height: 50.0,
        alignment: Alignment.center,
        width: Get.width,
        color: Colors.white,
        child: Text(textShow),
      ),
    );
  }
}
