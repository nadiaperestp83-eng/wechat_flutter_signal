import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wechat_flutter/ui/bar/commom_bar.dart';

/// Mesma técnica que o Signal/Molly usam: abre o desafio (hCaptcha) do
/// Signal numa WebView embutida no app. Quando o usuário resolve, a página
/// redireciona pra uma URL com esquema "signalcaptcha://<token>" — a gente
/// intercepta essa navegação (ela nunca chega a carregar de verdade) e
/// devolve o token pra quem chamou essa tela.
class SignalCaptchaPage extends StatefulWidget {
  @override
  State<SignalCaptchaPage> createState() => _SignalCaptchaPageState();
}

class _SignalCaptchaPageState extends State<SignalCaptchaPage> {
  late final WebViewController _controller;
  bool _carregando = true;

  static const _urlCaptcha =
      'https://signalcaptchas.org/registration/generate.html';
  static const _esquemaToken = 'signalcaptcha://';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith(_esquemaToken)) {
              final token = request.url.substring(_esquemaToken.length);
              Navigator.of(context).pop(token.isNotEmpty ? token : null);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => _carregando = true),
          onPageFinished: (_) => setState(() => _carregando = false),
        ),
      )
      ..loadRequest(Uri.parse(_urlCaptcha));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ComMomBar(
        title: 'Verificação de segurança',
        leadingImg: 'assets/images/bar_close.png',
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_carregando) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
