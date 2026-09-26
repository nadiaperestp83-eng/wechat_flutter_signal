class API {
  // URL base do seu servidor no Render
  static const String baseUrl = 'https://signal-bridge-dockerfile.onrender.com';

  // Endpoints do Signal Bridge
  static const String status = '$baseUrl/status';
  static const String register = '$baseUrl/register';
  static const String verify = '$baseUrl/verify';
  static const String send = '$baseUrl/send';
  static const String receive = '$baseUrl/receive';
  static const String updateProfile = '$baseUrl/updateProfile';
  static const String uploadStory = '$baseUrl/uploadStory';
  static const String addContact = '$baseUrl/addContact';
  static const String getUserStatus = '$baseUrl/getUserStatus';
  static const String getUsersStatus = '$baseUrl/getUsersStatus';

  // (Outras URLs antigas que você já tinha, se ainda usar)
  static const nameUrl = 'https://www.apiopen.top/femaleNameApi';
  static const avatarUrl = 'http://www.lorempixel.com/200/200/';
  static const cat = 'https://api.thecatapi.com/v1/images/search';
  static const upImg = "http://111.230.251.115/oldchen/fUser/oneDaySuggestion";
  static const update = 'http://www.flutterj.com/api/update.json';
  static const uploadImg = 'http://www.flutterj.com/upload/avatar';
}
