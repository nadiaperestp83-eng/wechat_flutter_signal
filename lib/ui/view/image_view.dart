import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/view/perfil_foto.dart';

class ImageView extends StatelessWidget {
  final String img;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isRadius;

  ImageView({
    required this.img,
    this.height,
    this.width,
    this.fit,
    this.isRadius = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (img.startsWith(kPrefixoPerfil)) {
      // Foto de perfil cifrada (Profile Key): decifra no aparelho.
      image = PerfilFoto(
        userId: img.substring(kPrefixoPerfil.length),
        width: width,
        height: height,
        fit: fit ?? BoxFit.cover,
      );
    } else if (GetUtils.isURL(img)) {
      image = CachedNetworkImage(
        imageUrl: img,
        width: width,
        height: height,
        fit: fit,
        cacheManager: cacheManager,
      );
    } else if (File(img).existsSync()) {
      image = Image.file(
        File(img),
        width: width,
        height: height,
        fit: fit,
      );
    } else if (img.startsWith('assets/')) {
      image = Image.asset(
        img,
        width: width,
        height: height,
        fit: width != null && height != null ? BoxFit.fill : fit,
      );
    } else {
      image = Container(
        decoration: BoxDecoration(
          color: Colors.black26.withOpacity(0.1),
          border: Border.all(color: Colors.black.withOpacity(0.2), width: 0.3),
        ),
        child: Image.asset(
          defIcon,
          width: width != null ? width! - 1 : null,
          height: height != null ? height! - 1 : null,
          fit: width != null && height != null ? BoxFit.fill : fit,
        ),
      );
    }
    if (isRadius) {
      return ClipRRect(
        borderRadius: BorderRadius.all(
          Radius.circular(4.0),
        ),
        child: image,
      );
    }
    return image;
  }
}
