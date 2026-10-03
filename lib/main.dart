import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wechat_flutter/config/const.dart';
import 'package:wechat_flutter/config/provider_config.dart';
import 'package:wechat_flutter/app.dart';
import 'package:wechat_flutter/tools/data/data.dart';
import 'package:wechat_flutter/im/local_store.dart';

import 'config/storage_manager.dart';

void main() async {
  /// 确保初始化
  WidgetsFlutterBinding.ensureInitialized();

  /// Supabase (auth, perfis, bundles/chaves) — precisa estar pronto antes
  /// de qualquer tela de login, não é mais inicializado sob demanda.
  if (signalSupabaseUrl.isEmpty || signalSupabaseAnonKey.isEmpty) {
    throw StateError(
      'SIGNAL_SUPABASE_URL/SIGNAL_SUPABASE_ANON_KEY vazios — confirme as '
      'secrets no GitHub e os --dart-define no build.yml.',
    );
  }
  await Supabase.initialize(
    url: signalSupabaseUrl,
    anonKey: signalSupabaseAnonKey,
  );

  /// 数据初始化
  await Data.initData();

  /// 配置初始化
  await StorageManager.init();

  /// Armazenamento local (Hive) — mensagens/conversas/contatos
  await SignalLocalStore.init();

  /// APP入口并配置Provider
  runApp(ProviderConfig.getInstance().getGlobal(MyApp()));

  /// 自定义报错页面
  ErrorWidget.builder = (FlutterErrorDetails flutterErrorDetails) {
    debugPrint(flutterErrorDetails.toString());
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16.0),
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: SelectableText(
          'ERRO (toque e segure pra copiar):\n\n${flutterErrorDetails.exceptionAsString()}\n\n${flutterErrorDetails.stack}',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 11.0,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  };

  /// Android状态栏透明
  if (Platform.isAndroid) {
    SystemUiOverlayStyle systemUiOverlayStyle =
        SystemUiOverlayStyle(statusBarColor: Colors.transparent);
    SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
  }
}
