import 'package:wechat_flutter/generated/i18n.dart';

/// Texto curto por idioma para as telas novas (perfil, configurações, presença).
/// Português é o padrão; inglês e chinês são opcionais.
String trApp(String pt, {String? en, String? zh}) {
  final S atual = S.current;
  if (atual is $en) return en ?? pt;
  if (atual is $zh_CN) return zh ?? pt;
  return pt;
}
