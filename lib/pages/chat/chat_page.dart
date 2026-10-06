import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:wechat_flutter/im/model/chat_data.dart';
import 'package:wechat_flutter/core/call_service.dart';
import 'package:wechat_flutter/im/nome_contato.dart';
import 'package:wechat_flutter/im/send_handle.dart';
import 'package:wechat_flutter/pages/chat/chat_more_page.dart';
import 'package:wechat_flutter/pages/group/group_details_page.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';
import 'package:wechat_flutter/ui/chat/chat_details_body.dart';
import 'package:wechat_flutter/ui/chat/chat_details_row.dart';
import 'package:wechat_flutter/ui/chat/emoji_panel.dart';
import 'package:wechat_flutter/ui/edit/text_span_builder.dart';
import 'package:wechat_flutter/ui/item/chat_more_icon.dart';
import 'package:wechat_flutter/ui/view/indicator_page_view.dart';
import 'package:wechat_flutter/ui/view/presence_text.dart';

import '../../tools/event/im_event.dart';
import 'chat_info_page.dart';

enum ButtonType { voice, more }

class ChatPage extends StatefulWidget {
  final String title;
  final int type;
  final String id;

  ChatPage({required this.id, required this.title, required this.type});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<V2TimMessage> chatData = <V2TimMessage>[];
  StreamSubscription<dynamic>? _msgStreamSubs;
  bool _isVoice = false;
  bool _isMore = false;
  double keyboardHeight = 270.0;
  bool _emojiState = false;
  String newGroupName = '';

  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _sC = ScrollController();
  PageController pageC = PageController();

  @override
  void initState() {
    super.initState();
    getChatMsgData();

    _sC.addListener(() => FocusScope.of(context).requestFocus(FocusNode()));
    initPlatformState();
    Notice.addListener(WeChatActions.msg(), (v) => getChatMsgData());
    if (widget.type == 2) {
      Notice.addListener(WeChatActions.groupName(), (v) {
        setState(() => newGroupName = v as String);
      });
    }
    // Conversa direta: se ainda não sei o nome da pessoa, busco no perfil dela.
    if (widget.type != 2) {
      NomeContato.buscar(<String>[widget.id]).then((bool novo) {
        if (novo && mounted) setState(() {});
      });
    }
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && mounted) {
        // Teclado abriu: fecha emoji/mais para não empilhar painéis.
        setState(() {
          _emojiState = false;
          _isMore = false;
        });
      }
    });
  }

  Future<void> getChatMsgData() async {
    final List<V2TimMessage> listChat =
        await ChatDataRep().repData(widget.id, widget.type);
    chatData.clear();
    chatData.addAll(listChat.reversed);
    if (mounted) {
      setState(() {});
    }
  }

  void insertText(String text) {
    final TextEditingValue value = _textController.value;
    final int start = value.selection.baseOffset;
    int end = value.selection.extentOffset;
    if (value.selection.isValid) {
      String newText = '';
      if (value.selection.isCollapsed) {
        if (end > 0) {
          newText += value.text.substring(0, end);
        }
        newText += text;
        if (value.text.length > end) {
          newText += value.text.substring(end, value.text.length);
        }
      } else {
        newText = value.text.replaceRange(start, end, text);
        end = start;
      }

      _textController.value = value.copyWith(
          text: newText,
          selection: value.selection.copyWith(
              baseOffset: end + text.length, extentOffset: end + text.length));
    } else {
      _textController.value = TextEditingValue(
          text: text,
          selection:
              TextSelection.fromPosition(TextPosition(offset: text.length)));
    }
  }

  void canCelListener() {
    if (_msgStreamSubs != null) {
      _msgStreamSubs!.cancel();
    }
  }

  Future<void> initPlatformState() async {
    if (!mounted) {
      return;
    }

    _msgStreamSubs ??= eventBusNewMsg.listen((EventBusNewMsg onData) {
      if (onData.covId == widget.id) {
        getChatMsgData();
      }
    });
  }

  Future<void> _handleSubmittedData(String text) async {
    _textController.clear();
    await sendTextMsg(widget.id, widget.type, text);
  }

  void onTapHandle(ButtonType type) {
    setState(() {
      if (type == ButtonType.voice) {
        _focusNode.unfocus();
        _isMore = false;
        _isVoice = !_isVoice;
      } else {
        _isVoice = false;
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          _isMore = true;
        } else {
          _isMore = !_isMore;
        }
      }
      _emojiState = false;
    });
  }

  Widget edit(BuildContext context, BoxConstraints size) {
    // 计算当前的文本需要占用的行数
    final TextSpan text =
        TextSpan(text: _textController.text, style: AppStyles.ChatBoxTextStyle);

    final TextPainter tp = TextPainter(
        text: text,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left);
    tp.layout(maxWidth: size.maxWidth);

    return ExtendedTextField(
      specialTextSpanBuilder: TextSpanBuilder(showAtBackground: true),
      onTap: () => setState(() {
        if (_focusNode.hasFocus) {
          _emojiState = false;
        }
      }),
      onChanged: (String v) => setState(() {}),
      decoration: const InputDecoration(
          border: InputBorder.none, contentPadding: EdgeInsets.all(5.0)),
      controller: _textController,
      focusNode: _focusNode,
      maxLines: 99,
      cursorColor: const Color(AppColors.ChatBoxCursorColor),
      style: AppStyles.ChatBoxTextStyle,
    );
  }

  /// Nome mostrado no topo: grupo = nome do grupo; conversa direta = apelido
  /// do contato, ou o nome do perfil dele, ou (por último) o e-mail.
  String get _nomeDoChat {
    if (widget.type == 2) {
      return newGroupName.isNotEmpty ? newGroupName : widget.title;
    }
    final String nome = NomeContato.nome(widget.id);
    if (nome != widget.id) return nome;
    if (widget.title.isNotEmpty && widget.title != widget.id) {
      return widget.title;
    }
    return nome;
  }

  /// Topo do chat, como no WhatsApp: foto, nome e (nas conversas diretas)
  /// "online" ou "visto por último hoje às 14:05" logo abaixo.
  Widget _tituloDoChat() {
    final Text nome = Text(
      _nomeDoChat,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 17.0,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
    );

    final Widget foto = ClipOval(
      child: widget.type == 2
          ? Container(
              width: 38.0,
              height: 38.0,
              color: Colors.black12,
              child: const Icon(Icons.group, color: Colors.black45),
            )
          : ImageView(
              img: 'perfil:${widget.id}',
              width: 38.0,
              height: 38.0,
              fit: BoxFit.cover,
              isRadius: false,
            ),
    );

    final Widget textos = widget.type == 2
        ? nome
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              nome,
              // Uma linha só; se o texto for longo, termina com "…".
              DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: PresenceText(
                  userId: widget.id,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 12.0,
                    height: 1.15,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          );

    return Row(
      children: <Widget>[
        foto,
        const SizedBox(width: 10.0),
        Expanded(child: textos),
      ],
    );
  }

  /// Chamada de voz/vídeo (Agora). Só em conversas diretas.
  void _ligar({required bool video}) {
    if (widget.type == 2) {
      showToast('Chamadas em grupo ainda não estão disponíveis');
      return;
    }
    CallService.instance.ligar(widget.id, video: video);
  }

  /// Ícone de ação da barra superior (PNG dos assets, tingido de preto).
  Widget _acaoBarra({
    required String asset,
    required VoidCallback onTap,
    required String dica,
    double tamanho = 24.0,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20.0),
      onTap: onTap,
      child: Tooltip(
        message: dica,
        child: Container(
          width: 40.0,
          alignment: Alignment.center,
          child: Image.asset(
            asset,
            width: tamanho,
            height: tamanho,
            color: Colors.black87,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    // Padding inferior do dispositivo (barra de gestos / botões de navegação).
    final double bottomSafe = mq.padding.bottom;
    // Memoriza a altura real do teclado para o painel ter exatamente o mesmo
    // tamanho (como no WhatsApp), evitando "pulos" na troca teclado <-> painel.
    if (mq.viewInsets.bottom > 100.0) {
      keyboardHeight = mq.viewInsets.bottom;
    }
    final bool tecladoAberto = mq.viewInsets.bottom > 0;
    final bool painelAberto = _emojiState || (_isMore && !_focusNode.hasFocus);
    final List<Widget> body = <Widget>[
      if (chatData != null)
        ChatDetailsBody(sC: _sC, chatData: chatData)
      else
        const Spacer(),
      ChatDetailsRow(
        voiceOnTap: () => onTapHandle(ButtonType.voice),
        onEmojio: () {
          if (_isMore) {
            _emojiState = true;
          } else {
            _emojiState = !_emojiState;
          }
          if (_emojiState) {
            FocusScope.of(context).requestFocus(FocusNode());
            _isMore = false;
          }
          setState(() {});
        },
        isVoice: _isVoice,
        edit: edit,
        more: ChatMoreIcon(
          value: _textController.text,
          onTap: () => _handleSubmittedData(_textController.text),
          moreTap: () => onTapHandle(ButtonType.more),
        ),
        id: widget.id,
        type: widget.type,
      ),
      // Painel de emojis: ancorado logo abaixo da barra de entrada.
      emojiWidget(bottomSafe),
      // Painel "mais" (+): mesma altura do teclado + padding inferior.
      Container(
        height: _isMore && !_focusNode.hasFocus
            ? keyboardHeight + bottomSafe
            : 0.0,
        width: Get.width,
        color: const Color(AppColors.ChatBoxBg),
        padding: EdgeInsets.only(bottom: bottomSafe),
        child: IndicatorPageView(
          pageC: pageC,
          pages: List.generate(2, (int index) {
            return ChatMorePage(
              index: index,
              id: widget.id,
              type: widget.type,
              keyboardHeight: keyboardHeight,
            );
          }),
        ),
      ),
      // Nenhum painel nem teclado aberto: reserva a área segura inferior para
      // a barra de entrada não ficar atrás da barra de gestos.
      Container(
        height: (!painelAberto && !tecladoAberto) ? bottomSafe : 0.0,
        width: Get.width,
        color: const Color(AppColors.ChatBoxBg),
      ),
    ];

    // Igual ao WhatsApp: vídeo, chamada de voz e menu (⋮).
    final List<Widget> rWidget = <Widget>[
      _acaoBarra(
        asset: 'assets/images/contact/ic_video.png',
        dica: 'Chamada de vídeo',
        onTap: () => _ligar(video: true),
      ),
      _acaoBarra(
        asset: 'assets/images/contact/ic_voice.png',
        dica: 'Chamada de voz',
        onTap: () => _ligar(video: false),
      ),
      _acaoBarra(
        asset: 'assets/images/right_more.png',
        dica: 'Mais',
        tamanho: 22.0,
        onTap: () => Get.to<void>(widget.type == 2
            ? GroupDetailsPage(
                widget?.id ?? widget.title,
                callBack: (v) {},
              )
            : ChatInfoPage(widget.id)),
      ),
      const SizedBox(width: 4.0),
    ];

    return Scaffold(
      // O corpo encolhe com o teclado: a caixa de texto e a barra inferior
      // sobem juntas e ficam coladas no teclado / no painel de emojis.
      resizeToAvoidBottomInset: true,
      appBar: ComMomBar(titleW: _tituloDoChat(), rightDMActions: rWidget),
      body: MainInputBody(
        onTap: () => setState(
          () {
            _isMore = false;
            _emojiState = false;
          },
        ),
        decoration: const BoxDecoration(color: chatBg),
        child: Column(children: body),
      ),
    );
  }

  Widget emojiWidget(double bottomSafe) {
    return GestureDetector(
      child: EmojiPanel(
        height: _emojiState ? keyboardHeight : 0,
        bottomInset: bottomSafe,
        onEmojiSelected: insertText,
      ),
      onTap: () {},
    );
  }

  @override
  void dispose() {
    super.dispose();
    canCelListener();
    Notice.removeListenerByEvent(WeChatActions.msg());
    Notice.removeListenerByEvent(WeChatActions.groupName());
    _sC.dispose();
    _focusNode.dispose();
    _textController.dispose();
    pageC.dispose();
  }
}
