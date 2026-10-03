import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Aviso amigável pro usuário (permissão negada, GPS desligado etc.).
class _Aviso implements Exception {
  final String mensagem;
  final bool abrirConfiguracoes;
  const _Aviso(this.mensagem, {this.abrirConfiguracoes = false});
}

class _Lugar {
  final String nome;
  final String tipo; // restaurant, bar, pub, cafe, fast_food
  final double distancia; // metros
  final double lat;
  final double lon;
  final String? endereco;
  final String? cozinha;

  const _Lugar({
    required this.nome,
    required this.tipo,
    required this.distancia,
    required this.lat,
    required this.lon,
    this.endereco,
    this.cozinha,
  });
}

/// "Restaurantes por perto": usa o GPS do celular e consulta o OpenStreetMap
/// (Overpass API, gratuito e sem chave) por restaurantes, bares, cafés e
/// lanchonetes. Cada lugar abre no Google Maps.
class NearbyPlacesPage extends StatefulWidget {
  const NearbyPlacesPage({super.key});

  @override
  State<NearbyPlacesPage> createState() => _NearbyPlacesPageState();
}

class _NearbyPlacesPageState extends State<NearbyPlacesPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);
  static const List<int> _raios = <int>[500, 1000, 2000, 5000];
  static const List<String> _servidores = <String>[
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  bool _carregando = true;
  String? _erro;
  bool _erroPermanente = false;
  int _raioMetros = 1000;
  double? _lat;
  double? _lon;
  List<_Lugar> _lugares = <_Lugar>[];
  int _requisicao = 0;

  @override
  void initState() {
    super.initState();
    _carregar(novaPosicao: true);
  }

  // ---------------------------------------------------------------- dados

  Future<geo.Position> _obterPosicao() async {
    final bool ativo = await geo.Geolocator.isLocationServiceEnabled();
    if (!ativo) {
      throw const _Aviso('Ative a localização (GPS) do celular para ver os lugares por perto.');
    }
    geo.LocationPermission permissao = await geo.Geolocator.checkPermission();
    if (permissao == geo.LocationPermission.denied) {
      permissao = await geo.Geolocator.requestPermission();
    }
    if (permissao == geo.LocationPermission.denied) {
      throw const _Aviso('Precisamos da sua localização para mostrar o que há por perto.');
    }
    if (permissao == geo.LocationPermission.deniedForever) {
      throw const _Aviso(
        'A permissão de localização foi bloqueada. Ative nas configurações do app.',
        abrirConfiguracoes: true,
      );
    }
    return geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _carregar({required bool novaPosicao}) async {
    final int id = ++_requisicao;
    setState(() {
      _carregando = true;
      _erro = null;
      _erroPermanente = false;
    });

    try {
      if (novaPosicao || _lat == null || _lon == null) {
        final geo.Position p = await _obterPosicao();
        _lat = p.latitude;
        _lon = p.longitude;
      }
      final List<_Lugar> lugares =
          await _buscarLugares(_lat!, _lon!, _raioMetros);
      if (!mounted || id != _requisicao) return;
      setState(() {
        _lugares = lugares;
        _carregando = false;
      });
    } on _Aviso catch (e) {
      if (!mounted || id != _requisicao) return;
      setState(() {
        _erro = e.mensagem;
        _erroPermanente = e.abrirConfiguracoes;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted || id != _requisicao) return;
      setState(() {
        _erro = 'Não foi possível buscar os lugares agora. '
            'Verifique sua conexão e tente de novo.';
        _carregando = false;
      });
    }
  }

  Future<List<_Lugar>> _buscarLugares(
      double lat, double lon, int raio) async {
    final String filtro = '["amenity"~"^(restaurant|bar|pub|cafe|fast_food)\$"]';
    final String consulta = '[out:json][timeout:25];('
        'node$filtro(around:$raio,$lat,$lon);'
        'way$filtro(around:$raio,$lat,$lon);'
        ');out center 150;';

    Object? ultimoErro;
    for (final String url in _servidores) {
      try {
        final http.Response resp = await http.post(
          Uri.parse(url),
          headers: <String, String>{'User-Agent': 'wechat_flutter_signal/1.0'},
          body: <String, String>{'data': consulta},
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          ultimoErro = 'HTTP ${resp.statusCode}';
          continue;
        }
        final Map<String, dynamic> json =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        return _converter(json, lat, lon);
      } catch (e) {
        ultimoErro = e;
      }
    }
    throw Exception('Falha nos servidores do OpenStreetMap: $ultimoErro');
  }

  List<_Lugar> _converter(Map<String, dynamic> json, double lat, double lon) {
    final List<dynamic> elementos = (json['elements'] as List<dynamic>?) ?? <dynamic>[];
    final List<_Lugar> lista = <_Lugar>[];

    for (final dynamic e in elementos) {
      if (e is! Map) continue;
      final Map<String, dynamic> tags =
          (e['tags'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final String? nome = (tags['name'] as String?)?.trim();
      if (nome == null || nome.isEmpty) continue;

      final dynamic centro = e['center'];
      final num? elat = (e['lat'] as num?) ?? (centro is Map ? centro['lat'] as num? : null);
      final num? elon = (e['lon'] as num?) ?? (centro is Map ? centro['lon'] as num? : null);
      if (elat == null || elon == null) continue;

      final String rua = (tags['addr:street'] as String? ?? '').trim();
      final String numero = (tags['addr:housenumber'] as String? ?? '').trim();
      final String bairro = (tags['addr:suburb'] as String? ?? '').trim();
      final List<String> partes = <String>[
        if (rua.isNotEmpty) numero.isNotEmpty ? '$rua, $numero' : rua,
        if (bairro.isNotEmpty) bairro,
      ];

      lista.add(_Lugar(
        nome: nome,
        tipo: (tags['amenity'] as String?) ?? 'restaurant',
        distancia: geo.Geolocator.distanceBetween(
            lat, lon, elat.toDouble(), elon.toDouble()),
        lat: elat.toDouble(),
        lon: elon.toDouble(),
        endereco: partes.isEmpty ? null : partes.join(' - '),
        cozinha: _traduzirCozinha(tags['cuisine'] as String?),
      ));
    }

    lista.sort((a, b) => a.distancia.compareTo(b.distancia));
    return lista.take(60).toList();
  }

  // ------------------------------------------------------------- formatação

  static const Map<String, String> _cozinhas = <String, String>{
    'pizza': 'Pizza',
    'burger': 'Hambúrguer',
    'italian': 'Italiana',
    'brazilian': 'Brasileira',
    'japanese': 'Japonesa',
    'chinese': 'Chinesa',
    'regional': 'Regional',
    'steak_house': 'Churrasco',
    'barbecue': 'Churrasco',
    'sushi': 'Sushi',
    'seafood': 'Frutos do mar',
    'coffee_shop': 'Cafeteria',
    'ice_cream': 'Sorvete',
    'mexican': 'Mexicana',
    'arab': 'Árabe',
    'lebanese': 'Libanesa',
    'vegetarian': 'Vegetariana',
    'vegan': 'Vegana',
    'sandwich': 'Sanduíche',
    'chicken': 'Frango',
    'french': 'Francesa',
    'german': 'Alemã',
    'portuguese': 'Portuguesa',
    'spanish': 'Espanhola',
    'thai': 'Tailandesa',
    'indian': 'Indiana',
    'korean': 'Coreana',
    'international': 'Internacional',
    'salad': 'Saladas',
    'bakery': 'Padaria',
  };

  String? _traduzirCozinha(String? bruto) {
    if (bruto == null || bruto.trim().isEmpty) return null;
    final List<String> itens = bruto
        .split(';')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) {
      final String? t = _cozinhas[s];
      if (t != null) return t;
      final String limpo = s.replaceAll('_', ' ');
      return limpo[0].toUpperCase() + limpo.substring(1);
    }).toList();
    return itens.isEmpty ? null : itens.join(', ');
  }

  String _rotuloTipo(String tipo) {
    switch (tipo) {
      case 'bar':
      case 'pub':
        return 'Bar';
      case 'cafe':
        return 'Café';
      case 'fast_food':
        return 'Lanchonete';
      default:
        return 'Restaurante';
    }
  }

  IconData _iconeTipo(String tipo) {
    switch (tipo) {
      case 'bar':
      case 'pub':
        return Icons.local_bar;
      case 'cafe':
        return Icons.local_cafe;
      case 'fast_food':
        return Icons.fastfood;
      default:
        return Icons.restaurant;
    }
  }

  String _formatarDistancia(double metros) {
    if (metros < 1000) return '${metros.round()} m';
    return '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String _rotuloRaio(int metros) =>
      metros < 1000 ? '$metros m' : '${metros ~/ 1000} km';

  Future<void> _abrirNoMaps(_Lugar l) async {
    final Uri uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${l.lat}%2C${l.lon}');
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) showToast('Não foi possível abrir o Google Maps');
    } catch (_) {
      showToast('Não foi possível abrir o Google Maps');
    }
  }

  // ----------------------------------------------------------------- widgets

  Widget _filtroRaio() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 6.0),
      child: Wrap(
        spacing: 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          const Text('Raio:', style: TextStyle(color: Colors.black54)),
          ..._raios.map((int r) {
            final bool selecionado = r == _raioMetros;
            return ChoiceChip(
              label: Text(_rotuloRaio(r)),
              selected: selecionado,
              selectedColor: _verde.withOpacity(0.2),
              onSelected: (_) {
                if (r == _raioMetros) return;
                setState(() => _raioMetros = r);
                _carregar(novaPosicao: false);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _cartao(_Lugar l) {
    final String detalhe = <String>[
      _rotuloTipo(l.tipo),
      if (l.cozinha != null) l.cozinha!,
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 22.0,
                backgroundColor: _verde.withOpacity(0.15),
                child: Icon(_iconeTipo(l.tipo), color: _verde),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16.0, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2.0),
                    Text(detalhe,
                        style: const TextStyle(
                            fontSize: 13.0, color: Colors.black54)),
                    if (l.endereco != null) ...<Widget>[
                      const SizedBox(height: 2.0),
                      Text(l.endereco!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.0, color: Colors.black45)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              Text(_formatarDistancia(l.distancia),
                  style: const TextStyle(
                      color: _verde, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10.0),
          OutlinedButton.icon(
            onPressed: () => _abrirNoMaps(l),
            icon: const Icon(Icons.map_outlined, size: 18.0),
            label: const Text('Abrir no Google Maps'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _verde,
              side: const BorderSide(color: _verde),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mensagem(String texto, {List<Widget> acoes = const <Widget>[]}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32.0),
      children: <Widget>[
        const SizedBox(height: 60.0),
        const Icon(Icons.location_off_outlined, size: 56.0, color: Colors.black26),
        const SizedBox(height: 16.0),
        Text(texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15.0, color: Colors.black54)),
        const SizedBox(height: 20.0),
        ...acoes,
      ],
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return _mensagem(
        _erro!,
        acoes: <Widget>[
          if (_erroPermanente)
            Center(
              child: ElevatedButton(
                onPressed: () => geo.Geolocator.openAppSettings(),
                child: const Text('Abrir configurações'),
              ),
            ),
          Center(
            child: TextButton(
              onPressed: () => _carregar(novaPosicao: true),
              child: const Text('Tentar de novo'),
            ),
          ),
        ],
      );
    }
    if (_lugares.isEmpty) {
      return _mensagem(
        'Nenhum restaurante ou bar encontrado em ${_rotuloRaio(_raioMetros)}. '
        'Tente aumentar o raio.',
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6.0, bottom: 20.0),
      children: <Widget>[
        ..._lugares.map(_cartao),
        const Padding(
          padding: EdgeInsets.only(top: 12.0),
          child: Text(
            'Dados © colaboradores do OpenStreetMap',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.0, color: Colors.black38),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(title: 'Restaurantes por perto'),
      body: Column(
        children: <Widget>[
          _filtroRaio(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _carregar(novaPosicao: true),
              child: _corpo(),
            ),
          ),
        ],
      ),
    );
  }
}
