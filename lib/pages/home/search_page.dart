import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/im/friend_handle.dart';
import 'package:wechat_flutter/im/local_store.dart';
import 'package:wechat_flutter/tools/event/im_event.dart';
import 'package:wechat_flutter/tools/tr_zh.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Usuário encontrado na busca por e-mail.
class _UsuarioEmail {
  final String email;
  final String? nome;
  final String? avatarUrl;

  const _UsuarioEmail({required this.email, this.nome, this.avatarUrl});

  String get nomeExibicao =>
      (nome != null && nome!.trim().isNotEmpty) ? nome!.trim() : email.split('@').first;
}

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int _minimoCaracteres = 3;

  final TextEditingController _searchC = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;

  bool _buscando = false;
  String? _erro;
  String? _meuEmail;
  Set<String> _contatos = <String>{};
  List<_UsuarioEmail> _resultados = <_UsuarioEmail>[];
  final Set<String> _adicionando = <String>{};

  List<String> words = ['朋友圈', '文章', '公众号', '小程序', '音乐', '表情'];

  @override
  void initState() {
    super.initState();
    _carregarContexto();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchC.dispose();
    super.dispose();
  }

  Set<String> _lerContatos() => SignalLocalStore.getContacts()
      .map((c) => (c['phone'] as String? ?? '').toLowerCase())
      .where((p) => p.isNotEmpty)
      .toSet();

  Future<void> _carregarContexto() async {
    final minha = await SharedUtil.instance.getString(Keys.account);
    if (!mounted) return;
    setState(() {
      _meuEmail = minha?.toLowerCase();
      _contatos = _lerContatos();
    });
  }

  String get _consulta => _searchC.text.trim().toLowerCase();

  bool get _consultaValida => _consulta.length >= _minimoCaracteres;

  /// Escapa curingas do ILIKE (\, % e _) pra o texto digitado ser literal.
  String _escaparLike(String texto) => texto
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  void _aoDigitar(String _) {
    _debounce?.cancel();
    if (!_consultaValida) {
      _requestId++;
      setState(() {
        _buscando = false;
        _erro = null;
        _resultados = <_UsuarioEmail>[];
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 400), _buscar);
  }

  Future<void> _buscar() async {
    _debounce?.cancel();
    if (!_consultaValida) return;

    final String consulta = _consulta;
    final int id = ++_requestId;
    setState(() {
      _buscando = true;
      _erro = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final String padrao = '%${_escaparLike(consulta)}%';

      // 1) Quem tem conta ativa no app (signal_bundles.user_id = e-mail).
      final bundles = await supabase
          .from('signal_bundles')
          .select('user_id')
          .ilike('user_id', padrao)
          .like('user_id', '%@%')
          .limit(20);

      final List<String> emails = (bundles as List)
          .map((r) => (r['user_id'] as String?)?.toLowerCase())
          .whereType<String>()
          .toSet()
          .toList();

      // 2) Nome e foto de perfil (signal_accounts). Se falhar, mostra só o e-mail.
      final Map<String, Map<String, dynamic>> perfis =
          <String, Map<String, dynamic>>{};
      if (emails.isNotEmpty) {
        try {
          final contas = await supabase
              .from('signal_accounts')
              .select('phone, display_name, avatar_url')
              .inFilter('phone', emails);
          for (final c in (contas as List)) {
            final String? chave = (c['phone'] as String?)?.toLowerCase();
            if (chave != null) perfis[chave] = Map<String, dynamic>.from(c as Map);
          }
        } catch (_) {
          // sem permissão/perfil: segue só com o e-mail
        }
      }

      if (!mounted || id != _requestId) return; // resposta antiga, descarta

      final lista = emails
          .map((e) => _UsuarioEmail(
                email: e,
                nome: perfis[e]?['display_name'] as String?,
                avatarUrl: perfis[e]?['avatar_url'] as String?,
              ))
          .toList()
        ..sort((a, b) {
          final exatoA = a.email == consulta ? 0 : 1;
          final exatoB = b.email == consulta ? 0 : 1;
          if (exatoA != exatoB) return exatoA.compareTo(exatoB);
          return a.email.compareTo(b.email);
        });

      setState(() {
        _resultados = lista;
        _contatos = _lerContatos();
        _buscando = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _buscando = false;
        _erro = 'Falha na busca: $e';
      });
    }
  }

  Future<void> _adicionar(_UsuarioEmail u) async {
    if (_adicionando.contains(u.email)) return;
    setState(() => _adicionando.add(u.email));

    await addFriend(u.email, context, name: u.nome, suCc: (_) {});

    if (!mounted) return;
    setState(() {
      _adicionando.remove(u.email);
      _contatos = _lerContatos();
    });
    // Faz as abas Contatos/Conversas recarregarem a lista.
    eventBusNewMsg.value = EventBusNewMsg(u.email);
  }

  Widget _avatar(_UsuarioEmail u) {
    final bool temFoto = u.avatarUrl != null && u.avatarUrl!.trim().isNotEmpty;
    return CircleAvatar(
      radius: 22.0,
      backgroundColor: const Color.fromRGBO(8, 191, 98, 1.0),
      foregroundImage: temFoto ? NetworkImage(u.avatarUrl!) : null,
      child: Text(
        u.nomeExibicao.characters.first.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 18.0),
      ),
    );
  }

  Widget _acao(_UsuarioEmail u) {
    if (u.email == _meuEmail) {
      return const Text('Você', style: TextStyle(color: mainTextColor));
    }
    if (_contatos.contains(u.email)) {
      return const Text('Adicionado', style: TextStyle(color: mainTextColor));
    }
    if (_adicionando.contains(u.email)) {
      return const SizedBox(
        width: 20.0,
        height: 20.0,
        child: CircularProgressIndicator(strokeWidth: 2.0),
      );
    }
    return TextButton(
      onPressed: () => _adicionar(u),
      child: const Text('Adicionar',
          style: TextStyle(color: Color.fromRGBO(8, 191, 98, 1.0))),
    );
  }

  Widget _itemResultado(_UsuarioEmail u) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: lineColor.withOpacity(0.3), width: 0.5),
        ),
      ),
      child: ListTile(
        leading: _avatar(u),
        title: Text(u.nomeExibicao, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          u.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: mainTextColor, fontSize: 13.0),
        ),
        trailing: _acao(u),
      ),
    );
  }

  Widget _mensagemCentral(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 40.0, left: 20.0, right: 20.0),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(color: mainTextColor),
      ),
    );
  }

  Widget wordView(String item) {
    return InkWell(
      child: Container(
        width: Get.width / 3,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(vertical: 15.0),
        child: Text(
          trZh(item),
          style: const TextStyle(color: tipColor),
        ),
      ),
      onTap: () => showToast('${trZh(item)}: em breve'),
    );
  }

  Widget _corpoSemBusca() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10.0),
          child: Text(
            'Digite pelo menos 3 letras do e-mail para buscar usuários',
            textAlign: TextAlign.center,
            style: TextStyle(color: mainTextColor),
          ),
        ),
        Wrap(children: words.map(wordView).toList()),
      ],
    );
  }

  Widget body() {
    if (!_consultaValida) return _corpoSemBusca();
    if (_buscando && _resultados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erro != null) return _mensagemCentral(_erro!);
    if (_resultados.isEmpty) {
      return _mensagemCentral('Nenhum usuário encontrado com esse e-mail');
    }
    return ListView(
      children: _resultados.map(_itemResultado).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchView = Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _searchC,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.search,
            style: const TextStyle(textBaseline: TextBaseline.alphabetic),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Buscar usuário por e-mail',
            ),
            onChanged: _aoDigitar,
            onSubmitted: (_) => _buscar(),
          ),
        ),
        strNoEmpty(_searchC.text)
            ? InkWell(
                child: Image.asset('assets/images/ic_delete.webp'),
                onTap: () {
                  _searchC.text = '';
                  _aoDigitar('');
                },
              )
            : Container()
      ],
    );
    return Scaffold(
      backgroundColor: appBarColor,
      appBar: ComMomBar(titleW: searchView),
      body: SizedBox(width: Get.width, child: body()),
    );
  }
}
