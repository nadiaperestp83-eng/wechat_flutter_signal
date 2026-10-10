/// Chave da API do Giphy. Vem do secret GIPHY_API_KEY do GitHub, injetado no
/// build por --dart-define (veja .github/workflows/build.yml). Nada fica no código.
const String kGiphyApiKey = String.fromEnvironment('GIPHY_API_KEY');
