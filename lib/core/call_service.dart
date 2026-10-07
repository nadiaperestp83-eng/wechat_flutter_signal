import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/config/agora_config.dart';
import 'package:wechat_flutter/core/media_crypto.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/im/nome_contato.dart';
import 'package:wechat_flutter/pages/call/call_page.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

enum EstadoChamada { chamando, conectando, conectada, encerrada }

class _Convite {
  final String from;
  final String id;
  final bool video;
  final String canal;
  final String chave;
  final Uint8List sal;

  const _Convite(
      this.from, this.id, this.video, this.canal, this.chave, this.sal);
}

class _Sessao {
  final String id;
  final String peer;
  final bool video;
  final bool saindo;
  final String canal;
  final String chave;
  final Uint8List sal;
  int uid = 0;
  bool conectou = false;

  _Sessao({
    required this.id,
    required this.peer,
    required this.video,
    required this.saindo,
    required this.canal,
    required this.chave,
    required this.sal,
  });
}

/// Chamadas de voz e vídeo (Agora) com mídia cifrada ponta a ponta.
///
///  - O convite (canal + chave de mídia) viaja cifrado na sessão Signal, pela
///    mesma caixa de mensagens do chat (já apagada do servidor após a leitura).
///  - Os avisos durante a chamada (atendeu, recusou, desligou) vão por
///    Supabase Realtime Broadcast em `calls:<email>` (volátil).
///  - A mídia usa a criptografia do Agora (AES-256-GCM) com a chave do convite.
///  - Nada de chamada é gravado: nem áudio, nem vídeo, nem histórico.
///  - Sem Edge Function e sem token: o projeto do Agora usa só o App ID.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  static const MethodChannel _nativo = MethodChannel('wechat/chamada');
  static const Duration _tempoParaAtender = Duration(seconds: 45);

  /// Gancho para o futuro controle de minutos: recebe a duração (em
  /// segundos) quando uma chamada conectada termina.
  Future<void> Function(int segundos)? aoContabilizar;

  // ---- estado que a tela de chamada observa
  final ValueNotifier<EstadoChamada> estado =
      ValueNotifier<EstadoChamada>(EstadoChamada.encerrada);
  final ValueNotifier<String> mensagem = ValueNotifier<String>('');
  final ValueNotifier<int?> remotoUid = ValueNotifier<int?>(null);
  final ValueNotifier<int> segundos = ValueNotifier<int>(0);
  final ValueNotifier<bool> mudo = ValueNotifier<bool>(false);
  final ValueNotifier<bool> altoFalante = ValueNotifier<bool>(false);
  final ValueNotifier<bool> cameraLigada = ValueNotifier<bool>(true);
  final ValueNotifier<RtcEngine?> motor = ValueNotifier<RtcEngine?>(null);

  String peerAtual = '';
  bool videoAtual = false;
  String canalAtual = '';

  String _meuId = '';
  bool _ativo = false;
  RealtimeChannel? _entrada;
  StreamSubscription<CallEvent?>? _eventosCallkit;
  _Sessao? _sessao;
  Timer? _tempoToque;
  Timer? _relogio;
  bool _telaAberta = false;
  final Random _aleatorio = Random.secure();
  final Set<String> _vistas = <String>{};
  final Set<String> _tratadas = <String>{};
  final Map<String, _Convite> _pendentes = <String, _Convite>{};
  final Map<String, RealtimeChannel> _saida = <String, RealtimeChannel>{};

  SupabaseClient get _supabase => Supabase.instance.client;
  bool get emChamada => _sessao != null;

  // ------------------------------------------------------------------ ciclo

  Future<void> iniciar(String meuId) async {
    final String id = meuId.trim().toLowerCase();
    if (id.isEmpty) return;
    if (_ativo && _meuId == id) return;
    if (_ativo) await parar();

    _meuId = id;
    _ativo = true;

    _escutar();
    _eventosCallkit?.cancel();
    _eventosCallkit = FlutterCallkitIncoming.onEvent.listen(_aoEventoCallkit);

    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }

  Future<void> parar() async {
    if (_sessao != null) {
      await _terminar(aviso: null, enviar: 'end');
    }
    _ativo = false;
    _meuId = '';
    await _eventosCallkit?.cancel();
    _eventosCallkit = null;
    final RealtimeChannel? entrada = _entrada;
    _entrada = null;
    if (entrada != null) {
      try {
        await _supabase.removeChannel(entrada);
      } catch (_) {}
    }
    await _limparSaida();
    _pendentes.clear();
    _vistas.clear();
    _tratadas.clear();
  }

  void _escutar() {
    final RealtimeChannel? antigo = _entrada;
    if (antigo != null) {
      try {
        _supabase.removeChannel(antigo);
      } catch (_) {}
    }
    try {
      _entrada = _supabase
          .channel('calls:$_meuId')
          .onBroadcast(
              event: 'invite',
              callback: (dynamic p) {
                final Map<String, dynamic> m = _corpo(p);
                _aoReceberConvite(
                  from: m['from'] as String?,
                  id: m['id'] as String?,
                  video: m['v'] == true,
                  tipo: (m['t'] as num?)?.toInt(),
                  cifrado: m['c'] as String?,
                );
              })
          .onBroadcast(
              event: 'ctrl',
              callback: (dynamic p) => _aoReceberControle(_corpo(p)))
          .subscribe();
    } catch (e) {
      debugPrint('[Chamadas] não consegui escutar o canal: $e');
    }
  }

  Map<String, dynamic> _corpo(dynamic bruto) {
    final Map<String, dynamic> m = Map<String, dynamic>.from(bruto as Map);
    final dynamic interno = m['payload'];
    if (interno is Map && m.containsKey('event')) {
      return Map<String, dynamic>.from(interno);
    }
    return m;
  }

  // --------------------------------------------------------------- ligar

  Future<void> ligar(String peer, {required bool video}) async {
    if (!_ativo) {
      showToast('Chamadas indisponíveis agora. Tente novamente.');
      return;
    }
    if (_sessao != null) {
      showToast('Você já está em uma chamada');
      return;
    }
    if (kAgoraAppId.isEmpty || kAgoraAppId.startsWith('COLE')) {
      showToast('Configure o App ID do Agora em lib/config/agora_config.dart');
      return;
    }
    if (!await _permissoes(video)) {
      showToast('Permita o microfone${video ? ' e a câmera' : ''} para ligar');
      return;
    }

    final String id = _novoUuid();
    final _Sessao s = _Sessao(
      id: id,
      peer: peer,
      video: video,
      saindo: true,
      canal: 'c${_hex(12)}',
      chave: base64Encode(MediaCrypto.gerarChave()),
      sal: MediaCrypto.bytesAleatorios(32),
    );
    _iniciarSessao(s);
    mensagem.value = 'Chamando…';
    unawaited(_abrirTela());

    try {
      final String envelope = jsonEncode(<String, dynamic>{
        't': 'call',
        'id': id,
        'v': video,
        'ch': s.canal,
        'k': s.chave,
        's': base64Encode(s.sal),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      // O convite vai cifrado pela caixa de mensagens do chat: se o app da
      // outra pessoa estiver fechado, o aviso de "Nova mensagem" dela acorda.
      await SignalCore().enviarConviteChamada(peer, envelope);

      _tempoToque = Timer(_tempoParaAtender, () {
        _terminar(aviso: 'Sem resposta', enviar: 'cancel');
      });

      await _entrarNoCanal(s);
    } catch (e) {
      debugPrint('[Chamadas] falha ao ligar: $e');
      showToast('Não foi possível ligar: $e');
      await _terminar(aviso: null, enviar: 'cancel');
    }
  }

  // ------------------------------------------------------------- receber

  /// Convite que chegou pela caixa de mensagens (o SignalCore já decifrou).
  Future<void> aoReceberConvite(String from, Map<String, dynamic> env) async {
    if (!_ativo || from == _meuId) return;
    final String? id = env['id'] as String?;
    if (id == null || !_vistas.add(id)) return;

    // Convite velho (a pessoa já desistiu ou o app ficou fechado): ignora.
    final int ts = (env['ts'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - ts > 60000) return;

    if (_sessao != null || _pendentes.isNotEmpty) {
      await _ctrl(from, id, 'busy');
      return;
    }

    final _Convite? convite = _lerConvite(from, id, env);
    if (convite == null) return;
    _pendentes[id] = convite;

    try {
      await NomeContato.buscar(<String>[from])
          .timeout(const Duration(seconds: 1));
    } catch (_) {}
    await _mostrarToque(
      id: id,
      nome: NomeContato.nome(from),
      video: convite.video,
      extra: <String, dynamic>{'from': from},
    );
  }

  _Convite? _lerConvite(String from, String id, Map<String, dynamic> env) {
    try {
      return _Convite(
        from,
        id,
        env['v'] == true,
        env['ch'] as String,
        env['k'] as String,
        Uint8List.fromList(base64Decode(env['s'] as String)),
      );
    } catch (e) {
      debugPrint('[Chamadas] convite inválido: $e');
      return null;
    }
  }

  Future<void> _aoReceberControle(Map<String, dynamic> m) async {
    final String? from = m['from'] as String?;
    final String? id = m['id'] as String?;
    final String? tipo = m['k'] as String?;
    if (from == null || id == null || tipo == null) return;

    final _Sessao? s = _sessao;
    if (s != null && s.id == id && s.peer == from) {
      switch (tipo) {
        case 'accept':
          if (estado.value == EstadoChamada.chamando) {
            estado.value = EstadoChamada.conectando;
            mensagem.value = 'Conectando…';
          }
          break;
        case 'reject':
          await _terminar(aviso: 'Chamada recusada', enviar: null);
          break;
        case 'busy':
          await _terminar(aviso: 'Ocupado', enviar: null);
          break;
        case 'end':
        case 'cancel':
          await _terminar(aviso: 'Chamada encerrada', enviar: null);
          break;
      }
      return;
    }

    if (tipo == 'cancel') _cancelouAntesDeAtender(id);
  }

  void _cancelouAntesDeAtender(String? id) {
    if (id == null) return;
    _pendentes.remove(id);
    try {
      FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
  }

  // ------------------------------------------------- botões da tela cheia

  void _aoEventoCallkit(CallEvent? evento) {
    if (evento == null) return;
    final Map<String, dynamic> corpo = _mapa(evento.body);
    final String? id = corpo['id'] as String?;
    if (id == null) return;
    final Map<String, dynamic> extra = _mapa(corpo['extra']);

    switch (evento.event) {
      case Event.actionCallAccept:
        _aoAceitar(id, extra);
        break;
      case Event.actionCallDecline:
        _aoRecusar(id, extra);
        break;
      case Event.actionCallTimeout:
        _pendentes.remove(id);
        break;
      case Event.actionCallEnded:
        final _Sessao? s = _sessao;
        if (s != null && s.id == id) {
          _terminar(aviso: null, enviar: s.conectou ? 'end' : 'cancel');
        }
        break;
      default:
        break;
    }
  }

  Map<String, dynamic> _mapa(dynamic bruto) {
    if (bruto is Map) {
      return bruto.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Future<void> _aoAceitar(String id, Map<String, dynamic> extra) async {
    if (!_tratadas.add('aceitar:$id')) return;
    if (_sessao != null) return;

    try {
      final _Convite? cv = _pendentes.remove(id);
      if (cv == null) throw StateError('convite não encontrado');

      if (!await _permissoes(cv.video)) {
        showToast('Permita o microfone${cv.video ? ' e a câmera' : ''}');
        await _ctrl(cv.from, id, 'reject');
        await FlutterCallkitIncoming.endCall(id);
        return;
      }

      final _Sessao s = _Sessao(
        id: id,
        peer: cv.from,
        video: cv.video,
        saindo: false,
        canal: cv.canal,
        chave: cv.chave,
        sal: cv.sal,
      );
      _iniciarSessao(s);
      estado.value = EstadoChamada.conectando;
      mensagem.value = 'Conectando…';
      unawaited(_abrirTela());

      await _ctrl(cv.from, id, 'accept');
      await _entrarNoCanal(s);
    } catch (e) {
      debugPrint('[Chamadas] falha ao atender: $e');
      showToast('Não foi possível atender a chamada');
      try {
        await FlutterCallkitIncoming.endCall(id);
      } catch (_) {}
      if (_sessao != null) await _terminar(aviso: null, enviar: 'end');
    }
  }

  Future<void> _aoRecusar(String id, Map<String, dynamic> extra) async {
    if (!_tratadas.add('recusar:$id')) return;
    final _Convite? cv = _pendentes.remove(id);
    final String? from = cv?.from ?? (extra['from'] as String?);
    if (from != null && from.isNotEmpty) {
      await _ctrl(from, id, 'reject');
    }
  }

  // ------------------------------------------------------------- Agora

  Future<void> _entrarNoCanal(_Sessao s) async {
    s.uid = 1 + _aleatorio.nextInt(2000000000);
    const String appId = kAgoraAppId;

    final RtcEngine rtc = createAgoraRtcEngine();
    await rtc.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    rtc.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection conexao, int ms) {
        debugPrint('[Chamadas] entrou no canal ${conexao.channelId}');
      },
      onUserJoined: (RtcConnection conexao, int uid, int ms) {
        _remotoEntrou(s, uid);
      },
      onUserOffline:
          (RtcConnection conexao, int uid, UserOfflineReasonType motivo) {
        if (_sessao == s && s.conectou) {
          _terminar(aviso: 'Chamada encerrada', enviar: null);
        }
      },
      onError: (ErrorCodeType erro, String texto) {
        debugPrint('[Chamadas] erro Agora: $erro $texto');
      },
    ));

    await rtc.enableAudio();
    if (s.video) {
      await rtc.enableVideo();
      await rtc.startPreview();
    }

    // Mídia cifrada ponta a ponta: a chave só existe nos dois aparelhos
    // (veio dentro do convite Signal). Tem de ser ligada ANTES de entrar.
    await rtc.enableEncryption(
      enabled: true,
      config: EncryptionConfig(
        encryptionMode: EncryptionMode.aes256Gcm2,
        encryptionKey: s.chave,
        encryptionKdfSalt: s.sal,
      ),
    );

    await rtc.setEnableSpeakerphone(s.video);
    altoFalante.value = s.video;

    motor.value = rtc;
    await rtc.joinChannel(
      token: '',
      channelId: s.canal,
      uid: s.uid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        publishCameraTrack: s.video,
        autoSubscribeAudio: true,
        autoSubscribeVideo: s.video,
      ),
    );
  }

  void _remotoEntrou(_Sessao s, int uid) {
    if (_sessao != s) return;
    s.conectou = true;
    _tempoToque?.cancel();
    remotoUid.value = uid;
    estado.value = EstadoChamada.conectada;
    mensagem.value = '';
    segundos.value = 0;
    _relogio?.cancel();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      segundos.value = segundos.value + 1;
    });
    try {
      FlutterCallkitIncoming.endCall(s.id); // some a notificação de toque
    } catch (_) {}
  }

  // ------------------------------------------------------- controles da UI

  Future<void> alternarMudo() async {
    mudo.value = !mudo.value;
    await motor.value?.muteLocalAudioStream(mudo.value);
  }

  Future<void> alternarAltoFalante() async {
    altoFalante.value = !altoFalante.value;
    await motor.value?.setEnableSpeakerphone(altoFalante.value);
  }

  Future<void> alternarCamera() async {
    cameraLigada.value = !cameraLigada.value;
    await motor.value?.muteLocalVideoStream(!cameraLigada.value);
  }

  Future<void> trocarCamera() async {
    await motor.value?.switchCamera();
  }

  Future<void> encerrar() async {
    final _Sessao? s = _sessao;
    if (s == null) return;
    await _terminar(aviso: null, enviar: s.conectou ? 'end' : 'cancel');
  }

  // --------------------------------------------------------------- fim

  void _iniciarSessao(_Sessao s) {
    _sessao = s;
    peerAtual = s.peer;
    videoAtual = s.video;
    canalAtual = s.canal;
    estado.value = EstadoChamada.chamando;
    remotoUid.value = null;
    segundos.value = 0;
    mudo.value = false;
    cameraLigada.value = true;
    altoFalante.value = s.video;
    unawaited(_servico(true, video: s.video));
  }

  Future<void> _terminar({
    required String? aviso,
    required String? enviar,
  }) async {
    final _Sessao? s = _sessao;
    if (s == null) return;
    _sessao = null;

    _tempoToque?.cancel();
    _relogio?.cancel();
    final int duracao = segundos.value;

    if (enviar != null) {
      await _ctrl(s.peer, s.id, enviar);
    }

    final RtcEngine? rtc = motor.value;
    motor.value = null;
    if (rtc != null) {
      try {
        await rtc.leaveChannel();
        await rtc.release();
      } catch (_) {}
    }

    await _servico(false);
    try {
      await FlutterCallkitIncoming.endCall(s.id);
    } catch (_) {}
    await _limparSaida();

    remotoUid.value = null;
    mensagem.value = aviso ?? '';
    estado.value = EstadoChamada.encerrada;

    if (s.conectou && aoContabilizar != null) {
      try {
        await aoContabilizar!(duracao);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ apoio

  Future<void> _abrirTela() async {
    for (int i = 0; i < 80 && Get.key.currentState == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (_telaAberta || Get.key.currentState == null) return;
    _telaAberta = true;
    await Get.to<void>(const CallPage());
    _telaAberta = false;
  }

  Future<void> _esperarSignal() async {
    for (int i = 0; i < 80 && !SignalCore().estaInicializado; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!SignalCore().estaInicializado) {
      throw StateError('Signal não inicializou a tempo');
    }
  }

  Future<bool> _permissoes(bool video) async {
    final Map<Permission, PermissionStatus> r = await <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ].request();
    return r.values.every((PermissionStatus s) => s.isGranted);
  }

  Future<void> _servico(bool ligar, {bool video = false}) async {
    try {
      if (ligar) {
        await _nativo.invokeMethod<bool>('iniciar', <String, dynamic>{
          'titulo': video ? 'Chamada de vídeo em andamento' : 'Chamada em andamento',
          'video': video,
        });
      } else {
        await _nativo.invokeMethod<bool>('parar');
      }
    } catch (e) {
      debugPrint('[Chamadas] serviço em primeiro plano: $e');
    }
  }

  // ---- sinalização

  Future<RealtimeChannel> _canalSaida(String destino) async {
    final RealtimeChannel? existente = _saida[destino];
    if (existente != null) return existente;

    final RealtimeChannel canal = _supabase.channel('calls:$destino');
    final Completer<void> pronto = Completer<void>();
    canal.subscribe((RealtimeSubscribeStatus status, Object? erro) {
      if (pronto.isCompleted) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        pronto.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        pronto.completeError(erro ?? StateError('canal: $status'));
      }
    });
    try {
      await pronto.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        await _supabase.removeChannel(canal);
      } catch (_) {}
      rethrow;
    }
    _saida[destino] = canal;
    return canal;
  }

  Future<void> _enviar(
      String destino, String evento, Map<String, dynamic> payload) async {
    for (int tentativa = 0; tentativa < 2; tentativa++) {
      try {
        final RealtimeChannel canal = await _canalSaida(destino);
        await canal.sendBroadcastMessage(event: evento, payload: payload);
        return;
      } catch (e) {
        final RealtimeChannel? ruim = _saida.remove(destino);
        if (ruim != null) {
          try {
            await _supabase.removeChannel(ruim);
          } catch (_) {}
        }
        if (tentativa == 1) rethrow;
      }
    }
  }

  Future<void> _limparSaida() async {
    final List<RealtimeChannel> canais = _saida.values.toList();
    _saida.clear();
    for (final RealtimeChannel c in canais) {
      try {
        await _supabase.removeChannel(c);
      } catch (_) {}
    }
  }

  Future<void> _ctrl(String destino, String id, String tipo) async {
    try {
      await _enviar(destino, 'ctrl', <String, dynamic>{
        'from': _meuId,
        'id': id,
        'k': tipo,
      });
    } catch (e) {
      debugPrint('[Chamadas] não consegui avisar $destino ($tipo): $e');
    }
  }

  // ---- tela cheia de chamada recebida

  Future<bool> _jaToca(String id) => _jaTocaEstatico(id);

  static Future<bool> _jaTocaEstatico(String id) async {
    try {
      final dynamic ativos = await FlutterCallkitIncoming.activeCalls();
      if (ativos is List) {
        for (final dynamic c in ativos) {
          if (c is Map && c['id'] == id) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _mostrarToque({
    required String id,
    required String nome,
    required bool video,
    required Map<String, dynamic> extra,
  }) =>
      _mostrarToqueEstatico(id: id, nome: nome, video: video, extra: extra);

  static Future<void> _mostrarToqueEstatico({
    required String id,
    required String nome,
    required bool video,
    required Map<String, dynamic> extra,
  }) async {
    final CallKitParams params = CallKitParams(
      id: id,
      nameCaller: nome,
      appName: 'WeChat',
      handle: video ? 'Chamada de vídeo' : 'Chamada de voz',
      type: video ? 1 : 0,
      duration: 45000,
      textAccept: 'Atender',
      textDecline: 'Recusar',
      extra: extra,
      missedCallNotification: NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Chamada perdida',
      ),
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1c1c1e',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Chamada recebida',
        missedCallNotificationChannelName: 'Chamada perdida',
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  // ---- ids

  String _hex(int bytes) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      sb.write(_aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// UUID v4 (o CallKit pede esse formato).
  String _novoUuid() {
    final List<int> b =
        List<int>.generate(16, (_) => _aleatorio.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
