/// 앱 전역 상수 정의
class AppConstants {
  AppConstants._();

  static const String appName = '쓸만한 민턴총무';
  static const String appSubtitle = '쓸만한 민턴총무 - 배드민턴 클럽 통합 관리';

  // 코트 관련 설정
  static const int minCourtCount = 1;
  static const int maxCourtCount = 15;
  static const int defaultCourtCount = 4;

  // 경기 규격
  static const int playersPerMatch = 4; // 복식 기준 4인 (2인 1팀)
  static const int defaultWinningScore = 21;

  // 세션 라운드 설정
  static const int defaultRounds = 5;

  // Firestore 컬렉션 경로
  static const String clubsCollection = 'clubs';
  static const String membersSubCollection = 'members';
  static const String sessionsCollection = 'game_sessions';
  static const String matchesSubCollection = 'matches';
}
