import 'package:flutter/foundation.dart';

/// Lightweight UI localization. Default = Vietnamese. Each surface stays in a
/// single language (no mixing). Add new locales by extending [_strings].
class UiLang extends ChangeNotifier {
  String code = 'vi'; // Vietnamese is the default UI language.

  /// Locales offered in the UI switcher (each must be complete).
  static const offered = [
    ['vi', '🇻🇳', 'Tiếng Việt'],
    ['en', '🇺🇸', 'English'],
  ];

  void setCode(String c) {
    if (c == code) return;
    code = c;
    notifyListeners();
  }

  String s(String key) => _strings[key]?[code] ?? _strings[key]?['en'] ?? key;

  /// String with a single `{x}` placeholder substituted.
  String f(String key, String x) => s(key).replaceAll('{x}', x);
}

const Map<String, Map<String, String>> _strings = {
  'offline': {'vi': 'Ngoại tuyến', 'en': 'Offline'},
  'nav_lens': {'vi': 'Ống kính', 'en': 'Lens'},
  'nav_learn': {'vi': 'Học', 'en': 'Learn'},
  'nav_glossary': {'vi': 'Thuật ngữ', 'en': 'Glossary'},
  'tap_speak': {'vi': 'Chạm để nói', 'en': 'Tap to speak'},
  'tap_stop': {'vi': 'Chạm để dừng', 'en': 'Tap to stop'},
  'listening': {'vi': 'Đang nghe…', 'en': 'Listening…'},
  'speak_hint': {'vi': 'Chạm micrô và nói {x}', 'en': 'Tap the mic and speak {x}'},
  'safety_locked': {'vi': 'Đã khóa thuật ngữ an toàn', 'en': 'Safety term locked'},
  'swap': {'vi': 'Đổi chiều', 'en': 'Swap'},
  'choose_lang': {'vi': 'Chọn ngôn ngữ', 'en': 'Choose language'},
  'ui_language': {'vi': 'Ngôn ngữ ứng dụng', 'en': 'App language'},
  'models': {'vi': 'mô hình…', 'en': 'models…'},
  'downloading': {'vi': 'Đang tải', 'en': 'Downloading'},
  'continuous': {'vi': 'Liên tục (rảnh tay)', 'en': 'Continuous (hands-free)'},
  // Glossary
  'glossary_title': {'vi': 'Thuật ngữ', 'en': 'Glossary'},
  'glossary_sub': {
    'vi': 'Thuật ngữ đã khóa luôn được dịch đúng — thiết yếu cho từ vựng an toàn.',
    'en': 'Locked terms are always surfaced correctly — critical for safety vocabulary.'
  },
  'add_term': {'vi': 'Thêm thuật ngữ', 'en': 'Add term'},
  'safety': {'vi': 'An toàn', 'en': 'Safety'},
  'add_locked': {'vi': 'Thêm thuật ngữ khóa', 'en': 'Add locked term'},
  'source_term': {'vi': 'Thuật ngữ nguồn', 'en': 'Source term'},
  'locked_translation': {'vi': 'Bản dịch khóa', 'en': 'Locked translation'},
  'safety_term': {'vi': 'Thuật ngữ an toàn', 'en': 'Safety term'},
  'cancel': {'vi': 'Hủy', 'en': 'Cancel'},
  'domain': {'vi': 'Lĩnh vực', 'en': 'Domain'},
  'dom_factory': {'vi': 'Nhà máy', 'en': 'Factory'},
  'dom_medical': {'vi': 'Y tế', 'en': 'Medical'},
  'dom_construction': {'vi': 'Xây dựng', 'en': 'Construction'},
  'dom_general': {'vi': 'Chung', 'en': 'General'},
  'session': {'vi': 'Cuộc trò chuyện', 'en': 'Session'},
  'pron_dict_title': {'vi': 'Từ điển phát âm', 'en': 'Pronunciation dictionary'},
  'pron_dict_sub': {'vi': 'Sửa cách đọc tên riêng, viết tắt, từ chuyên ngành', 'en': 'Respell names, acronyms, jargon for TTS'},
  'downloader_hdr': {'vi': 'Tải mô hình', 'en': 'Model downloader'},
  'downloader_demo': {'vi': 'Thử tải (kiểm tra %/tốc độ/ETA)', 'en': 'Test download (real %/speed/ETA)'},
  'start': {'vi': 'Bắt đầu', 'en': 'Start'},
  'add': {'vi': 'Thêm', 'en': 'Add'},
  // Pronunciation
  'pron_title': {'vi': 'Phát âm', 'en': 'Pronunciation'},
  'pron_sub': {
    'vi': 'Dạy giọng đọc cách phát âm tên riêng, thương hiệu và từ viết tắt.',
    'en': 'Teach the voice how to say names, brands, and acronyms correctly.'
  },
  'add_pron': {'vi': 'Thêm phát âm', 'en': 'Add pronunciation'},
  'word_name': {'vi': 'Từ / tên riêng', 'en': 'Word / name'},
  'say_like': {'vi': 'Đọc giống như…', 'en': 'Say it like…'},
  'voice_suffix': {'vi': 'giọng', 'en': 'voice'},
  // Learn
  'learn_title': {'vi': 'Học', 'en': 'Learn'},
  'terms_to_review': {'vi': 'thuật ngữ cần ôn', 'en': 'terms to review'},
  'day': {'vi': 'Ngày', 'en': 'Day'},
  'review_deck': {'vi': 'Bộ thẻ ôn tập', 'en': 'Review deck'},
  'tap_reveal': {'vi': 'chạm để xem', 'en': 'tap to reveal'},
  'tap_flip': {'vi': 'chạm để lật lại', 'en': 'tap to flip back'},
  'from_conversations': {'vi': 'Từ cuộc trò chuyện của bạn', 'en': 'From your conversations'},
  'saved_glossary': {'vi': 'Thuật ngữ đã lưu', 'en': 'Saved glossary terms'},
  'learn_empty': {
    'vi': 'Hãy trò chuyện — từ mới sẽ xuất hiện ở đây để ôn tập.',
    'en': 'Have a conversation — new words will appear here to review.'
  },
  // Lens
  'lens_title': {'vi': 'Ống kính', 'en': 'Lens'},
  'point_at': {'vi': 'Hướng vào biển báo, nhãn hoặc tài liệu', 'en': 'Point at a sign, label, or document'},
  'translating': {'vi': 'Đang dịch', 'en': 'Translating'},
  'on_device': {'vi': 'trên thiết bị', 'en': 'on-device'},
  'scanning': {'vi': 'Đang quét…', 'en': 'Scanning…'},
  'scan_again': {'vi': 'Quét lại', 'en': 'Scan again'},
  'no_text': {'vi': 'Không thấy chữ — thử lại với khung hình rõ hơn', 'en': 'No text — try a sharper frame'},
  'export_docx': {'vi': 'Xuất DOCX', 'en': 'Export DOCX'},
  'live': {'vi': 'TRỰC TIẾP', 'en': 'LIVE'},
  'capture': {'vi': 'Chụp', 'en': 'Capture'},
  'resume_live': {'vi': 'Tiếp tục', 'en': 'Resume live'},
  'gallery': {'vi': 'Thư viện', 'en': 'Gallery'},
  'docx_saved': {'vi': 'Đã lưu DOCX', 'en': 'DOCX saved'},
  'cam_init': {'vi': 'Đang mở camera…', 'en': 'Starting camera…'},
  'settings': {'vi': 'Cài đặt', 'en': 'Settings'},
  'tier_hdr': {'vi': 'Mức chất lượng (đổi mô hình mọi bước)', 'en': 'Quality tier (sets model for every stage)'},
  'tier_accuracy': {'vi': 'Độ chính xác cao nhất', 'en': 'Top accuracy'},
  'tier_balanced': {'vi': 'Cân bằng', 'en': 'Balanced'},
  'tier_light': {'vi': 'Nhẹ', 'en': 'Lightweight'},
  'voice_prefs': {'vi': 'Giọng nói & micrô', 'en': 'Voice & mic'},
  'tts_rate': {'vi': 'Tốc độ đọc', 'en': 'Speech rate'},
  'vad_sens': {'vi': 'Độ trễ dừng tiếng', 'en': 'Silence hangover'},
  'mic_sens': {'vi': 'Độ nhạy micrô', 'en': 'Mic sensitivity'},
  'ondevice_stt': {'vi': 'Nhận diện giọng nói trên máy', 'en': 'On-device speech (Whisper)'},
  'use_ondevice_stt': {'vi': 'Dùng Whisper cho KO·ZH·EN', 'en': 'Use Whisper for KO·ZH·EN'},
  'whisper_ready': {'vi': 'Đã sẵn sàng · ngoại tuyến', 'en': 'Ready · offline'},
  'whisper_offline_note': {'vi': 'Tải một lần, sau đó chạy offline', 'en': 'one-time download, then offline'},
  'download': {'vi': 'Tải về', 'en': 'Download'},
  'defaults_hdr': {'vi': 'Mặc định', 'en': 'Defaults'},
  'live_ocr_default': {'vi': 'Ống kính trực tiếp', 'en': 'Live camera OCR'},
  'auto_glossary': {'vi': 'Tự động khóa thuật ngữ', 'en': 'Auto-apply glossary'},
  'history': {'vi': 'Lịch sử', 'en': 'History'},
  'no_history': {'vi': 'Chưa có cuộc trò chuyện', 'en': 'No conversations yet'},
  'no_history_hint': {'vi': 'Bắt đầu dịch để lưu lại lịch sử ở đây', 'en': 'Translate something — it will appear here.'},
  'export': {'vi': 'Xuất', 'en': 'Export'},
  'clear': {'vi': 'Xóa', 'en': 'Clear'},
  'clear_q': {'vi': 'Xóa toàn bộ lịch sử?', 'en': 'Clear all history?'},
};
