import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_flutter/core/profile_service.dart';
import 'package:wechat_flutter/core/signal_core.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

/// Ações da foto de perfil (escolher, tirar, remover), compartilhadas entre
/// a tela de Perfil e a tela de Informações pessoais.
/// A foto é cifrada no aparelho (Profile Key) antes de subir ao servidor.
class FotoPerfilAcoes {
  FotoPerfilAcoes._();

  static String _meuId(GlobalModel model) {
    if (model.account.isNotEmpty) return model.account;
    return SignalCore().meuUserId;
  }

  /// Menu com as opções. [aoMudarEnvio] avisa quando começa/termina o envio
  /// (para mostrar um indicador de progresso).
  static Future<void> abrirOpcoes(
    BuildContext context,
    GlobalModel model, {
    required ValueChanged<bool> aoMudarEnvio,
  }) async {
    final bool temFoto = strNoEmpty(model.avatar);

    final String? escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(trApp('Escolher da galeria',
                    en: 'Choose from gallery', zh: '从相册选择')),
                onTap: () => Navigator.pop(ctx, 'galeria'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(trApp('Tirar foto', en: 'Take photo', zh: '拍照')),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              if (temFoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                      trApp('Remover foto', en: 'Remove photo', zh: '删除头像'),
                      style: const TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(ctx, 'remover'),
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(trApp('Cancelar', en: 'Cancel', zh: '取消')),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || escolha == null) return;
    switch (escolha) {
      case 'galeria':
        await definir(model, ImageSource.gallery, aoMudarEnvio: aoMudarEnvio);
        break;
      case 'camera':
        await definir(model, ImageSource.camera, aoMudarEnvio: aoMudarEnvio);
        break;
      case 'remover':
        await remover(model, aoMudarEnvio: aoMudarEnvio);
        break;
    }
  }

  /// Escolhe a imagem, cifra com a Profile Key e envia só o blob cifrado.
  static Future<void> definir(
    GlobalModel model,
    ImageSource origem, {
    required ValueChanged<bool> aoMudarEnvio,
  }) async {
    final String meuId = _meuId(model);
    if (meuId.isEmpty) {
      showToast('Sessão inválida — faça login de novo');
      return;
    }

    try {
      final XFile? arquivo = await ImagePicker().pickImage(
        source: origem,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 80,
      );
      if (arquivo == null) return;

      aoMudarEnvio(true);
      final Uint8List bytes = await arquivo.readAsBytes();

      await ProfileService.instance.definirMinhaFoto(meuId, bytes);

      model.avatar = 'perfil:$meuId';
      await SharedUtil.instance.saveString(Keys.faceUrl, model.avatar);
      model.refresh();

      // Garante que quem já conversa comigo tem a Profile Key.
      unawaited(SignalCore().compartilharChaveDePerfil());

      showToast('Foto de perfil atualizada');
    } catch (e) {
      showToast('Não foi possível atualizar a foto: $e');
    } finally {
      aoMudarEnvio(false);
    }
  }

  static Future<void> remover(
    GlobalModel model, {
    required ValueChanged<bool> aoMudarEnvio,
  }) async {
    final String meuId = _meuId(model);
    if (meuId.isEmpty) return;

    try {
      aoMudarEnvio(true);
      await ProfileService.instance.removerMinhaFoto(meuId);

      model.avatar = '';
      await SharedUtil.instance.saveString(Keys.faceUrl, '');
      model.refresh();

      showToast('Foto de perfil removida');
    } catch (e) {
      showToast('Não foi possível remover a foto: $e');
    } finally {
      aoMudarEnvio(false);
    }
  }
}
