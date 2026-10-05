import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/core/moments_service.dart';
import 'package:wechat_flutter/pages/wechat_friends/chat_style.dart';
import 'package:wechat_flutter/pages/wechat_friends/page/publish_dynamic.dart';
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
  static const double headerHeight = 250.0;
  static const double avatarCapa = 70.0;

  int maxImages = MomentsService.maxImagens;

  @override
  void initState() {
    super.initState();
    // Tudo que passou de 24 h some ao abrir a tela.
    MomentsService.instance.purgarExpirados();
  }

  String _meuNome(GlobalModel model) {
    final String n = model.nickName;
    if (strNoEmpty(n) && n != 'nickName') return n;
    return model.account;
  }

  /// Capa com nome e foto no canto (se a imagem da capa não carregar,
  /// fica um fundo escuro no lugar, como no WeChat).
  Widget _capa(GlobalModel model) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          height: headerHeight,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Container(color: const Color(0xff555555)),
              Image.network(
                backgroundImage,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12.0,
          bottom: -(avatarCapa / 2) + 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 10.0, right: 10.0),
                child: Text(
                  _meuNome(model),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17.0,
                      fontWeight: FontWeight.w600,
                      shadows: <Shadow>[
                        Shadow(blurRadius: 4.0, color: Colors.black54)
                      ]),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(1.5),
                color: Colors.white,
                child: ImageView(
                  img: strNoEmpty(model.avatar) ? model.avatar : defIcon,
                  width: avatarCapa,
                  height: avatarCapa,
                  fit: BoxFit.cover,
                  isRadius: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final GlobalModel model = Provider.of<GlobalModel>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: ComMomBar(
        title: 'Momentos',
        rightDMActions: <Widget>[
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Colors.black),
            onPressed: () => _showDialog(context),
          )
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: <Widget>[
          _capa(model),
          const SizedBox(height: avatarCapa / 2 + 6),
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
                  itemBuilder: (context, index) => ItemDynamic(posts[index],
                      key: ValueKey(posts[index].id)),
                  itemCount: posts.length,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  primary: false);
            },
          ),
          const SizedBox(height: 30),
        ]),
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
