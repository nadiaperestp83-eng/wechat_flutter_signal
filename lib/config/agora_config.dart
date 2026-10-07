/// App ID do Agora. Vem do secret AGORA_APP_ID do GitHub, injetado no build
/// por --dart-define (veja .github/workflows/build.yml). Nada fica no código.
///
/// O projeto do Agora precisa estar em "Testing mode: App ID" (sem
/// App Certificate), pois as chamadas não usam servidor para gerar token.
const String kAgoraAppId = String.fromEnvironment('AGORA_APP_ID');
