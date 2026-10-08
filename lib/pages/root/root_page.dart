import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:wechat_flutter/core/presence_service.dart';
import 'package:wechat_flutter/core/push_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:wechat_flutter/http/api.dart';
import 'package:wechat_flutter/pages/contacts/contacts_page.dart';
import 'package:wechat_flutter/pages/calls/calls_page.dart';
import 'package:wechat_flutter/pages/wechat_friends/page/wechat_friends_circle.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/pages/home/home_page.dart';
import 'package:wechat_flutter/pages/mine/mine_page.dart';
import 'package:wechat_flutter/pages/root/root_tabbar.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  _RootPageState createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  @override
  void initState() {
    super.initState();
    ifBrokenNetwork();
    updateApi(context);
    // Liga o chat (chaves + Realtime) e o push, inclusive ao reabrir o app.
    PushService.instance.iniciar();
    // Presença (online / visto por último) — não altera nada na tela.
    _iniciarPresenca();
  }

  Future<void> _iniciarPresenca() async {
    final String? meuId = await SharedUtil.instance.getString(Keys.account);
    if (meuId == null || meuId.isEmpty) return;
    await PresenceService.instance.iniciar(meuId);
  }

  Future<void> ifBrokenNetwork() async {
    final ifNetWork = await SharedUtil.instance.getBoolean(Keys.brokenNetwork);
    if (ifNetWork) {
      /// 监测网络变化
      subscription.onConnectivityChanged
          .listen((List<ConnectivityResult> result) async {
        if (result.contains(ConnectivityResult.mobile) ||
            result.contains(ConnectivityResult.wifi)) {
          V2TimValueCallback<String> currentUser =
              await V2TIMManager().getLoginUser();
          log('ConnectivityResult::currentUser::$currentUser');
          // if (currentUser == '' ) {
          // final account = await SharedUtil.instance.getString(Keys.account);
          // im.imAutoLogin(account);
          // }
          await SharedUtil.instance.saveBoolean(Keys.brokenNetwork, false);
        }
      });
    } else {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<TabBarModel> pages = <TabBarModel>[
      TabBarModel(
          // Rótulo da barra inferior: "Chat". No topo aparece "Kakaô".
          title: trApp('Chat', en: 'Chat', zh: '聊天'),
          tituloTopo: _tituloKakao(),
          icon: LoadImage('assets/images/tabbar_chat_c.webp'),
          selectIcon: LoadImage('assets/images/tabbar_chat_s.webp'),
          page: HomePage()),
      TabBarModel(
        title: S.of(context).contacts,
        icon: LoadImage('assets/images/tabbar_contacts_c.webp'),
        selectIcon: LoadImage('assets/images/tabbar_contacts_s.webp'),
        page: const ContactsPage(),
      ),
      // Ligações (histórico: feitas, recebidas e perdidas).
      // Ícone do fork: o telefone verde (cinza quando não selecionado).
      TabBarModel(
        title: trApp('Ligações', en: 'Calls', zh: '通话'),
        icon: const _IconeFork(
            'assets/images/contact/ic_voice.png', 25.0,
            cinza: true),
        selectIcon: const _IconeFork('assets/images/contact/ic_voice.png', 25.0),
        page: const CallsPage(),
      ),
      // Momentos: tocar abre a tela direto (não é uma aba).
      TabBarModel(
        title: trApp('Momentos', en: 'Moments', zh: '朋友圈'),
        icon: const _IconeFork('assets/images/discover/ff_Icon_album.webp', 26.0),
        selectIcon:
            const _IconeFork('assets/images/discover/ff_Icon_album.webp', 26.0),
        page: const SizedBox.shrink(),
        aoTocar: () => Get.to<void>(WeChatFriendsCircle()),
      ),
      TabBarModel(
        title: S.of(context).me,
        icon: LoadImage('assets/images/tabbar_me_c.webp'),
        selectIcon: LoadImage('assets/images/tabbar_me_s.webp'),
        page: MinePage(),
      ),
    ];
    return Scaffold(
      body: RootTabBar(pages: pages, currentIndex: 0),
    );
  }
}

/// Título "Kakaô" no topo: Inter, peso forte e letras levemente juntas
/// (visual de título grande do iOS moderno).
Widget _tituloKakao() {
  return Text(
    'Kakaô',
    maxLines: 1,
    style: GoogleFonts.inter(
      color: Colors.black,
      fontSize: 27.0,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
      height: 1.1,
    ),
  );
}

/// Ícone de aba feito com um asset do fork. [cinza] pinta com a cor dos
/// outros ícones não selecionados; sem isso mantém as cores originais.
class _IconeFork extends StatelessWidget {
  const _IconeFork(this.img, this.largura, {this.cinza = false});

  final String img;
  final double largura;
  final bool cinza;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      child: Image.asset(
        img,
        width: largura,
        color: cinza ? mainTextColor : null,
        gaplessPlayback: true,
      ),
    );
  }
}

class LoadImage extends StatelessWidget {
  const LoadImage(this.img, {super.key});

  final String img;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2.0),
      child: Image.asset(img, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}
