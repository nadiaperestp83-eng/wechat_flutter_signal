import 'package:flutter/material.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

class SelectLocationPage extends StatefulWidget {
  @override
  _SelectLocationPageState createState() => _SelectLocationPageState();
}

class _SelectLocationPageState extends State<SelectLocationPage> {
  // Lista expandida — os 8 originais (localizados via S.of(context)) mais
  // um conjunto grande de países comuns (nomes fixos em português, já que
  // não fazem parte do sistema de localização original do template).
  late List<Map<String, String>> state = <Map<String, String>>[
    <String, String>{'name': 'Brasil', 'code': '+55'},
    <String, String>{'name': S.of(context).australia, 'code': '+61'},
    <String, String>{'name': S.of(context).macao, 'code': '+853'},
    <String, String>{'name': S.of(context).canada, 'code': '+001'},
    <String, String>{'name': S.of(context).uS, 'code': '+001'},
    <String, String>{'name': S.of(context).taiwan, 'code': '+886'},
    <String, String>{'name': S.of(context).hongKong, 'code': '+852'},
    <String, String>{'name': S.of(context).singapore, 'code': '+65'},
    <String, String>{'name': S.of(context).chinaMainland, 'code': '+86'},
    <String, String>{'name': 'Argentina', 'code': '+54'},
    <String, String>{'name': 'Bolívia', 'code': '+591'},
    <String, String>{'name': 'Chile', 'code': '+56'},
    <String, String>{'name': 'Colômbia', 'code': '+57'},
    <String, String>{'name': 'Equador', 'code': '+593'},
    <String, String>{'name': 'Paraguai', 'code': '+595'},
    <String, String>{'name': 'Peru', 'code': '+51'},
    <String, String>{'name': 'Uruguai', 'code': '+598'},
    <String, String>{'name': 'Venezuela', 'code': '+58'},
    <String, String>{'name': 'México', 'code': '+52'},
    <String, String>{'name': 'Portugal', 'code': '+351'},
    <String, String>{'name': 'Espanha', 'code': '+34'},
    <String, String>{'name': 'França', 'code': '+33'},
    <String, String>{'name': 'Alemanha', 'code': '+49'},
    <String, String>{'name': 'Itália', 'code': '+39'},
    <String, String>{'name': 'Reino Unido', 'code': '+44'},
    <String, String>{'name': 'Irlanda', 'code': '+353'},
    <String, String>{'name': 'Países Baixos', 'code': '+31'},
    <String, String>{'name': 'Suíça', 'code': '+41'},
    <String, String>{'name': 'Japão', 'code': '+81'},
    <String, String>{'name': 'Coreia do Sul', 'code': '+82'},
    <String, String>{'name': 'Índia', 'code': '+91'},
    <String, String>{'name': 'África do Sul', 'code': '+27'},
    <String, String>{'name': 'Nigéria', 'code': '+234'},
    <String, String>{'name': 'Angola', 'code': '+244'},
    <String, String>{'name': 'Moçambique', 'code': '+258'},
  ];

  Widget buildState(BuildContext context, int index) {
    final Map<String, String> item = state[index];

    final Container content = new Container(
      margin: EdgeInsets.symmetric(horizontal: 20.0),
      padding: EdgeInsets.symmetric(vertical: 20.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey, width: 0.2),
        ),
      ),
      child: new Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          new Text(
            '${item['name']}',
            style: TextStyle(fontSize: 15.0),
          ),
          new Text(
            '${item['code']}',
            style: TextStyle(fontSize: 15.0, color: Colors.green),
          ),
        ],
      ),
    );

    return new InkWell(
      child: content,
      onTap: () =>
          Navigator.pop(context, item['name']! + '  ' + '(${item['code']})'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new ComMomBar(title: S.of(context).selectCountry),
      body: new ListView.builder(
          itemBuilder: buildState, itemCount: state.length),
    );
  }
}
