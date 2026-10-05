import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/pages/wechat_friends/chat_style.dart';
import 'package:wechat_flutter/pages/wechat_friends/page/publish_dynamic.dart';
import 'package:wechat_flutter/pages/wechat_friends/ui/load_view.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

import '../ui/item_dynamic.dart';

/// Momentos: posts efêmeros (24 h), guardados só neste aparelho.
class WeChatFriendsCircle extends StatefulWidget {
  WeChatFriendsCircle({Key? key}) : super(key: key);

  @override
  createState() => _WeChatFriendsCircleState();
}

class _WeChatFriendsCircleState extends State<WeChatFriendsCircle> {
  double navAlpha = 0;
  late double headerHeight;
  ScrollController scrollController = ScrollController();

  Color c = Colors.grey;
  String title = '';

  int maxImages = MomentsService.maxImagens;

  @override
  void initState() {
    super.initState();

    // Tudo que passou de 24 h some ao abrir a tela.
    MomentsService.instance.purgarExpirados();

    headerHeight = 250;

    scrollController.addListener(() {
      var offset = scrollController.offset;
      if (offset < 0) {
        if (navAlpha != 0) {
          setState(() => navAlpha = 0);
        }
      } else if (offset < headerHeight) {
        if (headerHeight - offset <= navigationBarHeight(context)) {
          setState(() {
            c = Colors.black;
            title = '朋友圈';
          });
        } else {
          c = Colors.white;
          title = '';
        }
        setState(() => navAlpha = 1 - (headerHeight - offset) / headerHeight);
      } else if (navAlpha != 1) {
        setState(() => navAlpha = 1);
      }
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  String _meuNome(GlobalModel model) {
    final String n = model.nickName;
    if (strNoEmpty(n) && n != 'nickName') return n;
    return model.account;
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: <Widget>[
          SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            controller: scrollController,
            child: Column(children: <Widget>[
              Stack(
                alignment: Alignment.bottomRight,
                children: <Widget>[
                  Container(
                      child: ImageLoadView(backgroundImage,
                          fit: BoxFit.cover,
                          height: headerHeight,
                          width: Get.width),
                      margin: EdgeInsets.only(bottom: 30.0)),
                  Container(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Padding(
                            padding: EdgeInsets.only(top: 10, right: 10),
                            child: Text(_meuNome(model),
                                style: TextStyle(
                                    color: Colors.white, fontSize: 17)),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5.0),
                            child: ImageView(
                              img: strNoEmpty(model.avatar)
                                  ? model.avatar
                                  : defIcon,
                              height: 70,
                              width: 70,
                              fit: BoxFit.cover,
                              isRadius: false,
                            ),
                          )
                        ]),
                    margin: EdgeInsets.only(right: 10),
                  )
                ],
              ),
              SizedBox(height: 10),
              ValueListenableBuilder<int>(
                valueListenable: MomentsService.instance.versao,
                builder: (BuildContext context, int _, Widget? __) {
                  final List<MomentPost> posts = MomentsService.instance.listar();
                  if (posts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 60.0, horizontal: 30.0),
                      child: Text(
                        'Nenhum momento por aqui.\nOs momentos somem depois de 24 horas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: mainTextColor),
                      ),
                    );
                  }
                  return ListView.builder(
                      itemBuilder: (context, index) =>
                          ItemDynamic(posts[index], key: ValueKey(posts[index].id)),
                      itemCount: posts.length,
                      physics: NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      primary: false);
                },
              ),
              SizedBox(height: 30),
            ]),
          ),
          Container(
            height: navigationBarHeight(context) + 10,
            child: new ComMomBar(
              title: title,
              rightDMActions: <Widget>[
                IconButton(
                  icon: Icon(Icons.add_a_photo, color: mainTextColor),
                  onPressed: () => _showDialog(context),
                )
              ],
              backgroundColor:
                  Color.fromARGB((navAlpha * 255).toInt(), 237, 237, 237),
            ),
          )
        ],
      ),
    );
  }

  void _showDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(actions: <Widget>[
              CupertinoDialogAction(
                child: Text('Tirar foto', style: TextStyles.textBlue16),
                onPressed: () {
                  Navigator.pop(context);
                  _tirarFoto();
                },
              ),
              CupertinoDialogAction(
                child: Text('Escolher da galeria', style: TextStyles.textBlue16),
                onPressed: () {
                  Navigator.pop(context);
                  loadAssets();
                },
              ),
              CupertinoDialogAction(
                child: Text('Só texto', style: TextStyles.textBlue16),
                onPressed: () {
                  Navigator.pop(context);
                  Get.to<void>(PublishDynamicPage(maxImages: maxImages));
                },
              ),
              CupertinoDialogAction(
                child: Text('Cancelar', style: TextStyles.textRed16),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            ]));
  }

  Future<void> _tirarFoto() async {
    try {
      final XFile? foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 50,
      );
      if (foto == null || !mounted) return;
      final Uint8List bytes = await foto.readAsBytes();
      Get.to<void>(
          PublishDynamicPage(images: <Uint8List>[bytes], maxImages: maxImages));
    } catch (e) {
      showToast('Não foi possível abrir a câmera: $e');
    }
  }

  Future<void> loadAssets() async {
    try {
      final List<XFile>? fotos = await ImagePicker().pickMultiImage(
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 50,
      );
      if (fotos == null || fotos.isEmpty || !mounted) return;
      final List<Uint8List> bytes = <Uint8List>[];
      for (final XFile f in fotos.take(maxImages)) {
        bytes.add(await f.readAsBytes());
      }
      Get.to<void>(PublishDynamicPage(images: bytes, maxImages: maxImages));
    } catch (e) {
      showToast('Não foi possível abrir a galeria: $e');
    }
  }
}
