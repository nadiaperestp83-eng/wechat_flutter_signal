import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wechat_flutter/core/backup_service.dart';
import 'package:wechat_flutter/provider/global_model.dart';
import 'package:wechat_flutter/tools/tr_app.dart';
import 'package:wechat_flutter/tools/wechat_flutter.dart';

TextStyle _inter(double tam, FontWeight peso, {Color? cor, double? altura, double? espaco}) {
  return GoogleFonts.inter(
    fontSize: tam,
    fontWeight: peso,
    color: cor ?? Colors.black87,
    height: altura,
    letterSpacing: espaco,
  );
}

/// Configurações > Backups: backup local cifrado por frase de recuperação.
/// (Une as duas telas do Signal: "Backups" e "Backups no dispositivo".)
class BackupPage extends StatefulWidget {
  const BackupPage({Key? key}) : super(key: key);

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  static const Color _verde = Color.fromRGBO(8, 191, 98, 1.0);

  bool _ativo = false;
  DateTime? _ultimo;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final bool ativo = await BackupService.instance.estaAtivo();
    final DateTime? ultimo = await BackupService.instance.ultimoBackup();
    if (!mounted) return;
    setState(() {
      _ativo = ativo;
      _ultimo = ultimo;
    });
  }

  String _dois(int n) => n.toString().padLeft(2, '0');

  String _quando(DateTime d) =>
      '${_dois(d.day)}/${_dois(d.month)}/${d.year} às ${_dois(d.hour)}:${_dois(d.minute)}';

  // -------------------------------------------------------------- ações

  Future<void> _ativar() async {
    if (_ocupado) return;
    final String frase = await BackupService.instance.ativar();
    await _carregar();
    if (!mounted) return;
    await _mostrarFrase(frase, primeira: true);
  }

  Future<void> _verFrase() async {
    final String? frase = await BackupService.instance.frase();
    if (frase == null || !mounted) return;
    await _mostrarFrase(frase, primeira: false);
  }

  Future<void> _mostrarFrase(String frase, {required bool primeira}) async {
    bool anotei = !primeira;
    await showDialog<void>(
      context: context,
      barrierDismissible: !primeira,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setLocal) {
            return PopScope(
              canPop: anotei,
              child: AlertDialog(
                title: Text(trApp('Sua frase de recuperação',
                    en: 'Your recovery phrase')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      trApp(
                          'Guarde esta frase num lugar seguro. Sem ela não é possível restaurar o backup, e ninguém, nem o Kakaô, consegue recuperá-la.',
                          en: 'Keep this phrase safe. Without it the backup cannot be restored.'),
                      style: _inter(14.0, FontWeight.w400, altura: 1.4),
                    ),
                    const SizedBox(height: 14.0),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: SelectableText(
                        frase,
                        textAlign: TextAlign.center,
                        style: _inter(20.0, FontWeight.w600, espaco: 1.5, altura: 1.5),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: frase));
                        showToast(trApp('Frase copiada', en: 'Phrase copied'));
                      },
                      icon: const Icon(Icons.copy, size: 18.0),
                      label: Text(trApp('Copiar', en: 'Copy')),
                    ),
                    if (primeira)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: _verde,
                        value: anotei,
                        onChanged: (bool? v) => setLocal(() => anotei = v ?? false),
                        title: Text(
                            trApp('Anotei minha frase de recuperação',
                                en: 'I saved my recovery phrase'),
                            style: _inter(14.0, FontWeight.w500)),
                      ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: anotei ? () => Navigator.pop(ctx) : null,
                    child: Text(primeira
                        ? trApp('Continuar', en: 'Continue')
                        : trApp('Fechar', en: 'Close')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _criarBackup() async {
    if (_ocupado) return;
    final GlobalModel model = Provider.of<GlobalModel>(context, listen: false);
    setState(() => _ocupado = true);
    try {
      final bytes = await BackupService.instance.gerarArquivo(model.account);
      final DateTime a = DateTime.now();
      final String nome =
          'kakao-backup-${a.year}${_dois(a.month)}${_dois(a.day)}-${_dois(a.hour)}${_dois(a.minute)}.kkbk';
      // Abre o seletor do Android para escolher a pasta e salvar o arquivo.
      final String? caminho = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar backup',
        fileName: nome,
        bytes: bytes,
      );
      if (caminho == null) {
        showToast('Backup não salvo');
      } else {
        await BackupService.instance.registrarBackupSalvo();
        showToast('Backup salvo');
      }
      await _carregar();
    } on BackupInvalido catch (e) {
      showToast('$e');
    } catch (e) {
      showToast('Não foi possível criar o backup: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _desativar() async {
    final bool? sim = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(trApp('Desativar backups?', en: 'Turn off backups?')),
        content: Text(trApp(
            'A frase de recuperação será apagada deste aparelho. Os arquivos de backup que você já salvou continuam existindo, mas só abrem com a frase antiga.',
            en: 'The recovery phrase will be erased from this device.')),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(trApp('Cancelar', en: 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(trApp('Desativar', en: 'Turn off'),
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (sim != true) return;
    await BackupService.instance.desativar();
    await _carregar();
  }

  // ------------------------------------------------------------- pedaços

  Widget _botaoPilula(String texto, VoidCallback? aoTocar) {
    return ElevatedButton(
      onPressed: aoTocar,
      style: ElevatedButton.styleFrom(
        backgroundColor: _verde,
        disabledBackgroundColor: Colors.grey.shade300,
        elevation: 0.0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 15.0),
      ),
      child: _ocupado
          ? const SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Text(texto, style: _inter(16.0, FontWeight.w600, cor: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: chatBg,
      appBar: ComMomBar(title: trApp('Backups', en: 'Backups')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24.0),
        children: <Widget>[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 26.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  trApp(
                      'Faça backup do seu histórico de mensagens para nunca perder dados ao comprar um novo celular ou reinstalar o Kakaô.',
                      en: 'Back up your message history so you never lose data when you get a new phone or reinstall Kakaô.'),
                  style: _inter(15.5, FontWeight.w400, altura: 1.45),
                ),
                const SizedBox(height: 24.0),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.smartphone_outlined,
                        size: 28.0, color: Colors.black87),
                    const SizedBox(width: 18.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(trApp('Backups no dispositivo',
                                  en: 'Backups on this device'),
                              style: _inter(17.0, FontWeight.w500)),
                          const SizedBox(height: 4.0),
                          Text(
                              trApp('Salve seus backups em uma pasta neste dispositivo',
                                  en: 'Save your backups to a folder on this device'),
                              style: _inter(14.0, FontWeight.w400,
                                  cor: Colors.black45, altura: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22.0),
                Text(
                  trApp(
                      'Os backups são criptografados com uma frase de recuperação e armazenados no seu dispositivo.',
                      en: 'Backups are encrypted with a recovery phrase and stored on your device.'),
                  style: _inter(15.5, FontWeight.w400, altura: 1.45),
                ),
                const SizedBox(height: 22.0),
                if (!_ativo)
                  _botaoPilula(trApp('Ativar backups', en: 'Turn on backups'), _ativar)
                else ...<Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.check_circle, color: _verde, size: 20.0),
                      const SizedBox(width: 8.0),
                      Text(trApp('Backups ativados', en: 'Backups on'),
                          style: _inter(15.5, FontWeight.w600, cor: _verde)),
                    ],
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    _ultimo == null
                        ? trApp('Nenhum backup criado ainda.', en: 'No backup yet.')
                        : '${trApp('Último backup', en: 'Last backup')}: ${_quando(_ultimo!)}',
                    style: _inter(14.0, FontWeight.w400, cor: Colors.black45),
                  ),
                  const SizedBox(height: 16.0),
                  _botaoPilula(
                      trApp('Criar backup agora', en: 'Back up now'),
                      _ocupado ? null : _criarBackup),
                  const SizedBox(height: 6.0),
                  TextButton(
                    onPressed: _verFrase,
                    child: Text(
                        trApp('Ver frase de recuperação', en: 'View recovery phrase'),
                        style: _inter(15.0, FontWeight.w600, cor: _verde)),
                  ),
                  TextButton(
                    onPressed: _desativar,
                    child: Text(trApp('Desativar backups', en: 'Turn off backups'),
                        style: _inter(15.0, FontWeight.w500, cor: Colors.red)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10.0),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20.0, 22.0, 20.0, 26.0),
            child: Text(
              trApp(
                  'Para restaurar um backup, faça uma nova instalação do Kakaô. Abra o app e toque em "Restaurar backup" na tela de entrada. Em seguida, escolha o arquivo do backup e digite a frase de recuperação.',
                  en: 'To restore a backup, do a fresh install of Kakaô. Open the app and tap "Restore backup" on the sign-in screen. Then choose the backup file and enter the recovery phrase.'),
              style: _inter(15.5, FontWeight.w400, altura: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
