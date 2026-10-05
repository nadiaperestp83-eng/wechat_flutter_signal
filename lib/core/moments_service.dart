import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/core/media_crypto.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/im/local_store.dart';

/// Um comentário num Momento.
class MomentComment {
  final String id;
  final String from;
  final String name;
  final String text;
  final int ts;

  const MomentComment({
    required this.id,
    required this.from,
    required this.name,
    required this.text,
    required this.ts,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'from': from,
        'name': name,
        'text': text,
        'ts': ts,
      };

  static MomentComment fromMap(Map<dynamic, dynamic> m) => MomentComment(
        id: m['id'] as String,
        from: m['from'] as String,
        name: (m['name'] as String?) ?? (m['from'] as String),
        text: (m['text'] as String?) ?? '',
        ts: (m['ts'] as num?)?.toInt() ?? 0,
      );
}

/// Um Momento guardado SOMENTE neste aparelho (Hive) e apagado após 24 h.
class MomentPost {
  final String id;
  final String author;
  final String authorName;
  final String text;
  final int ts; // criação (ms)
  final int exp; // expiração (ms)
  final bool mine;
  final List<Uint8List> images;
  final List<Map<String, String>> likes; // {id, name}
  final List<MomentComment> comments;

  const MomentPost({
    required this.id,
    required this.author,
    required this.authorName,
    required this.text,
    required this.ts,
    required this.exp,
    required this.mine,
    required this.images,
    required this.likes,
    required this.comments,
  });

  Duration get restante =>
      Duration(milliseconds: exp - DateTime.now().millisecondsSinceEpoch);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'author': author,
        'name': authorName,
        'text': text,
        'ts': ts,
        'exp': exp,
        'mine': mine,
        'images': images,
        'likes': likes,
        'comments': comments.map((MomentComment c) => c.toMap()).toList(),
      };

  static MomentPost fromMap(Map<dynamic, dynamic> m) {
    return MomentPost(
      id: m['id'] as String,
      author: m['author'] as String,
      authorName: (m['name'] as String?) ?? (m['author'] as String),
      text: (m['text'] as String?) ?? '',
      ts: (m['ts'] as num).toInt(),
      exp: (m['exp'] as num).toInt(),
      mine: m['mine'] == true,
      images: ((m['images'] as List?) ?? const <dynamic>[])
          .map((dynamic e) => Uint8List.fromList(List<int>.from(e as List)))
          .toList(),
      likes: ((m['likes'] as List?) ?? const <dynamic>[])
          .map((dynamic e) => Map<String, String>.from(e as Map))
          .toList(),
      comments: ((m['comments'] as List?) ?? const <dynamic>[])
          .map((dynamic e) => MomentComment.fromMap(e as Map))
          .toList(),
    );
  }
}

class _Parcial {
  final String from;
  final String id;
  final Map<int, Uint8List> partes = <int, Uint8List>{};
  int? n;
  Uint8List? chave;
  int ts = 0;
  int exp = 0;
  String nome = '';
  Timer? limite;

  _Parcial(this.from, this.id);
}

/// Momentos efêmeros, sem servidor de armazenamento.
///
///  - O Supabase só serve de "barramento": Realtime Broadcast no canal
///    `moments:<email do destinatário>`. Nada é gravado em tabela nem Storage.
///  - Cada post é cifrado no aparelho com uma chave aleatória (AES-256-GCM).
///    Essa chave vai para cada amigo dentro de uma mensagem Signal (sessão E2E).
///  - Quem estava offline perde o post (é o comportamento desejado).
///  - Posts, curtidas e comentários ficam só no Hive local e somem em 24 h.
class MomentsService {
  MomentsService._();
  static final MomentsService instance = MomentsService._();

  static const String _nomeBox = 'signal_moments';
  static const Duration validade = Duration(hours: 24);
  static const int maxImagens = 9;

  /// Cada mensagem do Broadcast fica abaixo do limite do plano gratuito
  /// (250 KB). 120 KB em binário = ~160 KB em base64.
  static const int tamanhoParte = 120 * 1024;
  static const int maxBytesTotal = 2 * 1024 * 1024;

  /// Sobe a cada mudança; as telas escutam isto.
  final ValueNotifier<int> versao = ValueNotifier<int>(0);

  Box<dynamic>? _box;
  String _meuId = '';
  bool _ativo = false;
  RealtimeChannel? _canal;
  Timer? _faxina;
  final Map<String, _Parcial> _parciais = <String, _Parcial>{};
  final Random _aleatorio = Random.secure();

  SupabaseClient get _supabase => Supabase.instance.client;

  // ------------------------------------------------------------------ ciclo

  Future<void> iniciar(String meuId) async {
    final String id = meuId.trim().toLowerCase();
    if (id.isEmpty) return;
    if (_ativo && _meuId == id) return;
    if (_ativo) await parar();

    _meuId = id;
    _box ??= await Hive.openBox<dynamic>(_nomeBox);
    _ativo = true;

    await purgarExpirados();
    _escutar();
    _faxina?.cancel();
    _faxina = Timer.periodic(const Duration(minutes: 1), (_) {
      purgarExpirados();
    });
  }

  Future<void> reconectar() async {
    if (!_ativo) return;
    await purgarExpirados();
    _escutar();
  }

  Future<void> parar() async {
    _ativo = false;
    _faxina?.cancel();
    _faxina = null;
    for (final _Parcial p in _parciais.values) {
      p.limite?.cancel();
    }
    _parciais.clear();
    final RealtimeChannel? canal = _canal;
    _canal = null;
    if (canal != null) {
      try {
        await _supabase.removeChannel(canal);
      } catch (_) {}
    }
    _meuId = '';
  }

  void _escutar() {
    final RealtimeChannel? antigo = _canal;
    if (antigo != null) {
      try {
        _supabase.removeChannel(antigo);
      } catch (_) {}
    }
    try {
      _canal = _supabase
          .channel('moments:$_meuId')
          .onBroadcast(
              event: 'post',
              callback: (dynamic p) => _aoReceberPost(_corpo(p)))
          .onBroadcast(
              event: 'chunk',
              callback: (dynamic p) => _aoReceberParte(_corpo(p)))
          .onBroadcast(
              event: 'ctrl',
              callback: (dynamic p) => _aoReceberControle(_corpo(p)))
          .subscribe();
    } catch (e) {
      debugPrint('[Moments] não consegui escutar o canal: $e');
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

  // --------------------------------------------------------------- leitura

  /// Posts ainda válidos, do mais novo para o mais antigo.
  List<MomentPost> listar() {
    final Box<dynamic>? box = _box;
    if (box == null) return <MomentPost>[];
    final int agora = DateTime.now().millisecondsSinceEpoch;
    final List<MomentPost> lista = <MomentPost>[];
    for (final dynamic v in box.values) {
      if (v is! Map) continue;
      try {
        final MomentPost p = MomentPost.fromMap(v);
        if (p.exp > agora) lista.add(p);
      } catch (_) {}
    }
    lista.sort((MomentPost a, MomentPost b) => b.ts.compareTo(a.ts));
    return lista;
  }

  bool jaCurti(MomentPost post) =>
      post.likes.any((Map<String, String> l) => l['id'] == _meuId);

  /// Nome a mostrar: o apelido que eu dei ao contato, senão o nome que ele usa.
  String nomeDe(MomentPost post) {
    if (post.mine) return _meuNome();
    for (final Map<String, dynamic> c in SignalLocalStore.getContacts()) {
      if (c['phone'] == post.author) {
        final dynamic nome = c['name'];
        if (nome is String && nome.trim().isNotEmpty) return nome;
      }
    }
    return post.authorName;
  }

  String _meuNome() {
    final dynamic nome = SignalLocalStore.getSelfProfile(_meuId)?['name'];
    if (nome is String && nome.trim().isNotEmpty) return nome;
    return _meuId.contains('@') ? _meuId.split('@').first : _meuId;
  }

  List<String> _amigos() {
    final Set<String> ids = <String>{};
    for (final Map<String, dynamic> c in SignalLocalStore.getContacts()) {
      final dynamic phone = c['phone'];
      if (phone is String && phone.isNotEmpty && phone != _meuId) {
        ids.add(phone);
      }
    }
    return ids.toList();
  }

  bool _ehAmigo(String id) => _amigos().contains(id);

  // ----------------------------------------------------------- publicar

  /// Cifra e transmite o Momento para os amigos conectados agora.
  /// Lança exceção se não houver o que publicar ou se passar do limite.
  Future<void> publicar({
    required String texto,
    required List<Uint8List> imagens,
  }) async {
    if (!_ativo) throw StateError('Moments não iniciado.');
    final String limpo = texto.trim();
    if (limpo.isEmpty && imagens.isEmpty) {
      throw ArgumentError('Escreva algo ou escolha uma foto.');
    }
    if (imagens.length > maxImagens) {
      throw ArgumentError('No máximo $maxImagens fotos.');
    }
    final int total = imagens.fold<int>(0, (int s, Uint8List b) => s + b.length);
    if (total > maxBytesTotal) {
      throw ArgumentError('As fotos estão pesadas demais. Escolha menos fotos.');
    }

    final String id = _novoId();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final int exp = ts + validade.inMilliseconds;

    // 1) Guarda no meu aparelho.
    await _salvar(MomentPost(
      id: id,
      author: _meuId,
      authorName: _meuNome(),
      text: limpo,
      ts: ts,
      exp: exp,
      mine: true,
      images: imagens,
      likes: <Map<String, String>>[],
      comments: <MomentComment>[],
    ));

    // 2) Cifra uma vez com a chave do post.
    final Uint8List chave = MediaCrypto.gerarChave();
    final Uint8List blob =
        MediaCrypto.cifrar(chave, _empacotar(limpo, imagens));
    final List<Uint8List> partes = <Uint8List>[];
    for (int i = 0; i < blob.length; i += tamanhoParte) {
      partes.add(Uint8List.sublistView(
          blob, i, min(i + tamanhoParte, blob.length)));
    }

    final String envelope = jsonEncode(<String, dynamic>{
      't': 'mpost',
      'id': id,
      'k': base64Encode(chave),
      'n': partes.length,
      'ts': ts,
      'exp': exp,
      'name': _meuNome(),
    });

    // 3) Entrega para cada amigo (a chave vai dentro da sessão Signal).
    for (final String amigo in _amigos()) {
      try {
        final CanalCifrado cifrado =
            await SignalCore().cifrarParaCanal(amigo, envelope);
        await _comCanal(amigo, (RealtimeChannel canal) async {
          await canal.sendBroadcastMessage(
            event: 'post',
            payload: <String, dynamic>{
              'from': _meuId,
              'id': id,
              't': cifrado.tipo,
              'c': cifrado.payload,
            },
          );
          for (int i = 0; i < partes.length; i++) {
            await canal.sendBroadcastMessage(
              event: 'chunk',
              payload: <String, dynamic>{
                'from': _meuId,
                'id': id,
                'i': i,
                'd': base64Encode(partes[i]),
              },
            );
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        });
      } catch (e) {
        debugPrint('[Moments] não consegui entregar para $amigo: $e');
      }
    }
  }

  /// Apaga no meu aparelho e avisa os amigos para apagarem também.
  Future<void> excluir(MomentPost post) async {
    await _box?.delete(post.id);
    _avisar();
    if (!post.mine) return;
    final String envelope =
        jsonEncode(<String, dynamic>{'t': 'mdel', 'id': post.id});
    for (final String amigo in _amigos()) {
      unawaited(_enviarControle(amigo, envelope));
    }
  }

  // --------------------------------------------------- curtir / comentar

  Future<void> curtir(MomentPost post) async {
    final bool curtindo = !jaCurti(post);
    final MomentPost? atual = _ler(post.id);
    if (atual == null) return;

    final List<Map<String, String>> likes =
        List<Map<String, String>>.from(atual.likes)
          ..removeWhere((Map<String, String> l) => l['id'] == _meuId);
    if (curtindo) likes.add(<String, String>{'id': _meuId, 'name': _meuNome()});
    await _salvar(_copiar(atual, likes: likes));

    if (!post.mine) {
      await _enviarControle(
        post.author,
        jsonEncode(<String, dynamic>{
          't': 'mreact',
          'k': curtindo ? 'like' : 'unlike',
          'id': post.id,
          'name': _meuNome(),
        }),
      );
    }
  }

  Future<void> comentar(MomentPost post, String texto) async {
    final String limpo = texto.trim();
    if (limpo.isEmpty) return;
    final MomentPost? atual = _ler(post.id);
    if (atual == null) return;

    final MomentComment comentario = MomentComment(
      id: _novoId(),
      from: _meuId,
      name: _meuNome(),
      text: limpo,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    await _salvar(_copiar(atual,
        comments: <MomentComment>[...atual.comments, comentario]));

    if (!post.mine) {
      await _enviarControle(
        post.author,
        jsonEncode(<String, dynamic>{
          't': 'mreact',
          'k': 'comment',
          'id': post.id,
          'cid': comentario.id,
          'name': comentario.name,
          'text': limpo,
        }),
      );
    }
  }

  /// Mensagem efêmera P2P (cifrada na sessão Signal) direto para [destino].
  Future<void> _enviarControle(String destino, String envelope) async {
    try {
      final CanalCifrado cifrado =
          await SignalCore().cifrarParaCanal(destino, envelope);
      await _comCanal(destino, (RealtimeChannel canal) async {
        await canal.sendBroadcastMessage(
          event: 'ctrl',
          payload: <String, dynamic>{
            'from': _meuId,
            't': cifrado.tipo,
            'c': cifrado.payload,
          },
        );
      });
    } catch (e) {
      debugPrint('[Moments] não consegui enviar para $destino: $e');
    }
  }

  // ------------------------------------------------------------ receber

  Future<void> _aoReceberParte(Map<String, dynamic> m) async {
    try {
      final String? from = m['from'] as String?;
      final String? id = m['id'] as String?;
      final int? i = (m['i'] as num?)?.toInt();
      final String? d = m['d'] as String?;
      if (from == null || id == null || i == null || d == null) return;
      if (from == _meuId || !_ehAmigo(from)) return;
      if (i < 0 || i > 64) return;

      final _Parcial p = _parcial(from, id);
      p.partes[i] = base64Decode(d);
      await _tentarMontar(p);
    } catch (e) {
      debugPrint('[Moments] parte inválida: $e');
    }
  }

  Future<void> _aoReceberPost(Map<String, dynamic> m) async {
    try {
      final String? from = m['from'] as String?;
      final String? id = m['id'] as String?;
      final String? c = m['c'] as String?;
      final int? t = (m['t'] as num?)?.toInt();
      if (from == null || id == null || c == null || t == null) return;
      if (from == _meuId || !_ehAmigo(from)) return;

      // Só quem tem sessão Signal comigo consegue abrir: isso prova o remetente.
      final String claro = await SignalCore().decifrarDeCanal(from, c, t);
      final Map<String, dynamic> env =
          Map<String, dynamic>.from(jsonDecode(claro) as Map);
      if (env['t'] != 'mpost' || env['id'] != id) return;

      final int agora = DateTime.now().millisecondsSinceEpoch;
      final int ts =
          ((env['ts'] as num?)?.toInt() ?? agora).clamp(0, agora).toInt();
      // Nunca confia num prazo maior que 24 h.
      final int exp = min((env['exp'] as num?)?.toInt() ?? 0,
          agora + validade.inMilliseconds);
      if (exp <= agora) return;

      final _Parcial p = _parcial(from, id);
      p.chave = Uint8List.fromList(base64Decode(env['k'] as String));
      p.n = (env['n'] as num).toInt();
      p.ts = ts;
      p.exp = exp;
      p.nome = (env['name'] as String?) ?? from;
      await _tentarMontar(p);
    } catch (e) {
      debugPrint('[Moments] post inválido: $e');
    }
  }

  _Parcial _parcial(String from, String id) {
    final String chave = '$from|$id';
    return _parciais.putIfAbsent(chave, () {
      final _Parcial p = _Parcial(from, id);
      // Parte que não completa em 3 minutos é descartada.
      p.limite = Timer(const Duration(minutes: 3), () {
        _parciais.remove(chave);
      });
      return p;
    });
  }

  Future<void> _tentarMontar(_Parcial p) async {
    final int? n = p.n;
    final Uint8List? chave = p.chave;
    if (n == null || chave == null || p.partes.length < n) return;

    _parciais.remove('${p.from}|${p.id}');
    p.limite?.cancel();

    final BytesBuilder junto = BytesBuilder(copy: false);
    for (int i = 0; i < n; i++) {
      final Uint8List? parte = p.partes[i];
      if (parte == null) return;
      junto.add(parte);
    }

    try {
      final Uint8List claro =
          MediaCrypto.decifrar(chave, junto.toBytes());
      final Map<String, dynamic> conteudo = _desempacotar(claro);
      await _salvar(MomentPost(
        id: p.id,
        author: p.from,
        authorName: p.nome,
        text: conteudo['text'] as String,
        ts: p.ts,
        exp: p.exp,
        mine: false,
        images: conteudo['images'] as List<Uint8List>,
        likes: <Map<String, String>>[],
        comments: <MomentComment>[],
      ));
    } catch (e) {
      debugPrint('[Moments] não consegui abrir o post: $e');
    }
  }

  Future<void> _aoReceberControle(Map<String, dynamic> m) async {
    try {
      final String? from = m['from'] as String?;
      final String? c = m['c'] as String?;
      final int? t = (m['t'] as num?)?.toInt();
      if (from == null || c == null || t == null) return;
      if (from == _meuId) return;

      final String claro = await SignalCore().decifrarDeCanal(from, c, t);
      final Map<String, dynamic> env =
          Map<String, dynamic>.from(jsonDecode(claro) as Map);
      final String? id = env['id'] as String?;
      if (id == null) return;
      final MomentPost? post = _ler(id);
      if (post == null) return;

      switch (env['t']) {
        case 'mdel':
          // Só o autor pode apagar o próprio post.
          if (!post.mine && post.author == from) {
            await _box?.delete(id);
            _avisar();
          }
          break;
        case 'mreact':
          // Curtidas e comentários só valem no MEU post.
          if (!post.mine) return;
          final String nome = (env['name'] as String?) ?? from;
          final String tipo = env['k'] as String? ?? '';
          if (tipo == 'like' || tipo == 'unlike') {
            final List<Map<String, String>> likes =
                List<Map<String, String>>.from(post.likes)
                  ..removeWhere((Map<String, String> l) => l['id'] == from);
            if (tipo == 'like') {
              likes.add(<String, String>{'id': from, 'name': nome});
            }
            await _salvar(_copiar(post, likes: likes));
          } else if (tipo == 'comment') {
            final String texto = (env['text'] as String? ?? '').trim();
            if (texto.isEmpty) return;
            final String cid = env['cid'] as String? ?? _novoId();
            if (post.comments.any((MomentComment x) => x.id == cid)) return;
            await _salvar(_copiar(post, comments: <MomentComment>[
              ...post.comments,
              MomentComment(
                id: cid,
                from: from,
                name: nome,
                text: texto,
                ts: DateTime.now().millisecondsSinceEpoch,
              ),
            ]));
          }
          break;
      }
    } catch (e) {
      debugPrint('[Moments] controle inválido: $e');
    }
  }

  // --------------------------------------------------------- expiração

  /// Apaga do aparelho tudo que passou de 24 h (post, fotos, curtidas e
  /// comentários). Roda ao abrir o app, ao reconectar e a cada minuto.
  Future<int> purgarExpirados() async {
    final Box<dynamic>? box = _box;
    if (box == null) return 0;
    final int agora = DateTime.now().millisecondsSinceEpoch;

    final List<dynamic> vencidos = <dynamic>[];
    for (final dynamic chave in box.keys) {
      final dynamic v = box.get(chave);
      final int exp = (v is Map ? (v['exp'] as num?)?.toInt() : null) ?? 0;
      if (exp <= agora) vencidos.add(chave);
    }
    if (vencidos.isNotEmpty) {
      await box.deleteAll(vencidos);
      _avisar();
    }
    return vencidos.length;
  }

  // ----------------------------------------------------------- utilitários

  MomentPost? _ler(String id) {
    final dynamic v = _box?.get(id);
    if (v is! Map) return null;
    try {
      final MomentPost p = MomentPost.fromMap(v);
      return p.exp > DateTime.now().millisecondsSinceEpoch ? p : null;
    } catch (_) {
      return null;
    }
  }

  MomentPost _copiar(
    MomentPost p, {
    List<Map<String, String>>? likes,
    List<MomentComment>? comments,
  }) {
    return MomentPost(
      id: p.id,
      author: p.author,
      authorName: p.authorName,
      text: p.text,
      ts: p.ts,
      exp: p.exp,
      mine: p.mine,
      images: p.images,
      likes: likes ?? p.likes,
      comments: comments ?? p.comments,
    );
  }

  Future<void> _salvar(MomentPost p) async {
    await _box?.put(p.id, p.toMap());
    _avisar();
  }

  void _avisar() => versao.value = versao.value + 1;

  String _novoId() {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 16; i++) {
      sb.write(_aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// [4 bytes: tamanho do JSON][JSON {text, sizes}][foto 1][foto 2]...
  Uint8List _empacotar(String texto, List<Uint8List> imagens) {
    final Uint8List cabecalho = Uint8List.fromList(utf8.encode(jsonEncode(
        <String, dynamic>{
      'text': texto,
      'sizes': imagens.map((Uint8List b) => b.length).toList(),
    })));
    final BytesBuilder b = BytesBuilder(copy: false);
    final ByteData tam = ByteData(4)..setUint32(0, cabecalho.length);
    b.add(tam.buffer.asUint8List());
    b.add(cabecalho);
    for (final Uint8List img in imagens) {
      b.add(img);
    }
    return b.toBytes();
  }

  Map<String, dynamic> _desempacotar(Uint8List dados) {
    final int tam = ByteData.sublistView(dados, 0, 4).getUint32(0);
    final Map<String, dynamic> cab = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(dados.sublist(4, 4 + tam))) as Map);
    int pos = 4 + tam;
    final List<Uint8List> imagens = <Uint8List>[];
    for (final dynamic s in (cab['sizes'] as List)) {
      final int n = (s as num).toInt();
      imagens.add(Uint8List.fromList(dados.sublist(pos, pos + n)));
      pos += n;
    }
    return <String, dynamic>{
      'text': (cab['text'] as String?) ?? '',
      'images': imagens,
    };
  }

  /// Entra no canal do destinatário só pelo tempo de enviar e sai.
  Future<void> _comCanal(
    String destino,
    Future<void> Function(RealtimeChannel canal) tarefa,
  ) async {
    final RealtimeChannel canal = _supabase.channel('moments:$destino');
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
      await tarefa(canal);
    } finally {
      try {
        await _supabase.removeChannel(canal);
      } catch (_) {}
    }
  }
}
