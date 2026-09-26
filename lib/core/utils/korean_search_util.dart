/// 한글 초성 검색 및 텍스트 매칭 유틸리티
class KoreanSearchUtil {
  KoreanSearchUtil._();

  static const int _hangulBase = 0xAC00;
  static const int _hangulEnd = 0xD7A3;
  static const int _choSungBase = 588; // 21 * 28

  static const List<String> _choSungList = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ',
    'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
  ];

  /// 한글 음절에서 초성을 추출합니다. 한글이 아닐 경우 원본 문자를 반환합니다.
  static String extractChoseong(String text) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= _hangulBase && code <= _hangulEnd) {
        final choIndex = (code - _hangulBase) ~/ _choSungBase;
        buffer.write(_choSungList[choIndex]);
      } else {
        buffer.write(text[i]);
      }
    }
    return buffer.toString();
  }

  /// 쿼리가 대상 문자열의 이름 또는 초성과 일치(포함)하는지 검사합니다.
  /// 예: matches("홍길동", "ㅎㄱㄷ") -> true
  /// 예: matches("홍길동", "길동") -> true
  /// 예: matches("김철수", "ㅊㅅ") -> true
  static bool matches(String target, String query) {
    final cleanTarget = target.trim().toLowerCase();
    final cleanQuery = query.trim().toLowerCase();

    if (cleanQuery.isEmpty) return true;
    if (cleanTarget.contains(cleanQuery)) return true;

    final targetChoseong = extractChoseong(cleanTarget);
    final queryChoseong = extractChoseong(cleanQuery);

    return targetChoseong.contains(queryChoseong);
  }
}
