import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// A supported language with the locale codes each subsystem needs.
class Lang {
  final String code; // internal short code
  final String name; // English display name
  final String nativeName; // endonym
  final String flag; // emoji
  final String sttLocale; // speech_to_text localeId
  final String ttsLocale; // flutter_tts language
  final TranslateLanguage mlkit; // ML Kit on-device translate

  const Lang(this.code, this.name, this.nativeName, this.flag, this.sttLocale,
      this.ttsLocale, this.mlkit);
}

/// The supported set: Vietnamese-centric pairs with EN/KO/ZH.
const List<Lang> kLangs = [
  Lang('vi', 'Vietnamese', 'Tiếng Việt', '🇻🇳', 'vi-VN', 'vi-VN',
      TranslateLanguage.vietnamese),
  Lang('en', 'English', 'English', '🇺🇸', 'en-US', 'en-US',
      TranslateLanguage.english),
  Lang('ko', 'Korean', '한국어', '🇰🇷', 'ko-KR', 'ko-KR',
      TranslateLanguage.korean),
  Lang('zh', 'Chinese', '中文', '🇨🇳', 'zh-CN', 'zh-CN',
      TranslateLanguage.chinese),
];

Lang langByCode(String code) =>
    kLangs.firstWhere((l) => l.code == code, orElse: () => kLangs[1]);
