import '../core/constants/enums.dart';

/// 대진표 개별 경기(Match) 모델
/// Firestore 경로: game_sessions/{sessionId}/matches/{matchId}
/// Note: Dart SDK의 dart:core Match 클래스와의 충돌을 방지하기 위해 기본 클래스명은 GameMatch로 정의하며,
/// 필요시 MatchModel 또는 Match 별칭으로도 사용할 수 있도록 지원합니다.
class GameMatch {
  final String id;
  final String sessionId;
  final int round;
  final int courtNumber;
  final List<String> teamA; // [memberId1, memberId2] (2인)
  final List<String> teamB; // [memberId3, memberId4] (2인)
  final int scoreA;
  final int scoreB;
  final MatchStatus status; // pending, playing, finished
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const GameMatch({
    required this.id,
    required this.sessionId,
    required this.round,
    required this.courtNumber,
    required this.teamA,
    required this.teamB,
    this.scoreA = 0,
    this.scoreB = 0,
    this.status = MatchStatus.pending,
    this.startedAt,
    this.finishedAt,
  });

  /// 경기 참가자 4명의 ID 전체 목록
  List<String> get allPlayerIds => [...teamA, ...teamB];

  /// 특정 회원이 이 경기에 출전하는지 확인
  bool containsPlayer(String memberId) {
    return teamA.contains(memberId) || teamB.contains(memberId);
  }

  /// 특정 회원이 속한 팀 반환 ('A', 'B', 미출전 시 null)
  String? getTeamForPlayer(String memberId) {
    if (teamA.contains(memberId)) return 'A';
    if (teamB.contains(memberId)) return 'B';
    return null;
  }

  /// 경기 종료 여부
  bool get isFinished => status == MatchStatus.finished;

  /// 경기 진행 중 여부
  bool get isPlaying => status == MatchStatus.playing;

  /// 경기 대기 중 여부
  bool get isPending => status == MatchStatus.pending;

  /// Team A 승리 여부
  bool get isTeamAWon => isFinished && scoreA > scoreB;

  /// Team B 승리 여부
  bool get isTeamBWon => isFinished && scoreB > scoreA;

  /// 무승부 여부
  bool get isDraw => isFinished && scoreA == scoreB;

  /// 점수 차이
  int get scoreDiff => (scoreA - scoreB).abs();

  /// Firestore 저장용 Map 변환
  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'round': round,
      'courtNumber': courtNumber,
      'teamA': teamA,
      'teamB': teamB,
      'scoreA': scoreA,
      'scoreB': scoreB,
      'status': status.code,
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    };
  }

  /// Firestore 데이터로부터 인스턴스 복원
  factory GameMatch.fromMap(Map<String, dynamic> map, {required String id}) {
    return GameMatch(
      id: id,
      sessionId: (map['sessionId'] as String?) ?? '',
      round: (map['round'] as num?)?.toInt() ?? 1,
      courtNumber: (map['courtNumber'] as num?)?.toInt() ?? 1,
      teamA: (map['teamA'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      teamB: (map['teamB'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      scoreA: (map['scoreA'] as num?)?.toInt() ?? 0,
      scoreB: (map['scoreB'] as num?)?.toInt() ?? 0,
      status: MatchStatus.fromCode(map['status'] as String?),
      startedAt: map['startedAt'] != null
          ? DateTime.tryParse(map['startedAt'] as String)
          : null,
      finishedAt: map['finishedAt'] != null
          ? DateTime.tryParse(map['finishedAt'] as String)
          : null,
    );
  }

  GameMatch copyWith({
    String? id,
    String? sessionId,
    int? round,
    int? courtNumber,
    List<String>? teamA,
    List<String>? teamB,
    int? scoreA,
    int? scoreB,
    MatchStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    return GameMatch(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      round: round ?? this.round,
      courtNumber: courtNumber ?? this.courtNumber,
      teamA: teamA ?? this.teamA,
      teamB: teamB ?? this.teamB,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameMatch && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'GameMatch(id: $id, round: $round, court: $courtNumber, status: ${status.label}, score: $scoreA:$scoreB)';
  }
}

/// 편의를 위한 별칭 정의
typedef MatchModel = GameMatch;
