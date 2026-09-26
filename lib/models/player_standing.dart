import '../core/constants/enums.dart';
import 'match.dart';

/// 대회/리그/모임 순위 산출용 플레이어 성적 모델 (개인 기준)
class PlayerStanding {
  final String memberId;
  final String memberName;
  final Tier? tier;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int pointsFor; // 총 득점
  final int pointsAgainst; // 총 실점
  int rank; // 순위 (1위, 2위 ...)

  PlayerStanding({
    required this.memberId,
    required this.memberName,
    this.tier,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.pointsFor = 0,
    this.pointsAgainst = 0,
    this.rank = 1,
  });

  /// 득실차 (득점 - 실점)
  int get pointDifference => pointsFor - pointsAgainst;

  /// 승률 (퍼센트: 0.0 ~ 100.0)
  double get winRate =>
      matchesPlayed > 0 ? (wins / matchesPlayed) * 100 : 0.0;

  PlayerStanding copyWith({
    String? memberId,
    String? memberName,
    Tier? tier,
    int? matchesPlayed,
    int? wins,
    int? losses,
    int? draws,
    int? pointsFor,
    int? pointsAgainst,
    int? rank,
  }) {
    return PlayerStanding(
      memberId: memberId ?? this.memberId,
      memberName: memberName ?? this.memberName,
      tier: tier ?? this.tier,
      matchesPlayed: matchesPlayed ?? this.matchesPlayed,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      draws: draws ?? this.draws,
      pointsFor: pointsFor ?? this.pointsFor,
      pointsAgainst: pointsAgainst ?? this.pointsAgainst,
      rank: rank ?? this.rank,
    );
  }

  @override
  String toString() {
    return '$rank위: $memberName ($wins승 $losses패, 승률 ${winRate.toStringAsFixed(1)}%, 득실차 $pointDifference, 총득점 $pointsFor)';
  }
}

/// 풀리그전 (팀 기준) 순위 산출용 2인 페어 팀 성적 모델
class TeamStanding {
  final String teamKey; // 정렬된 선수 ID 조합 키 (예: "m01_m02")
  final List<String> playerIds;
  final List<String> playerNames;
  final List<Tier> playerTiers;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int pointsFor; // 총 득점
  final int pointsAgainst; // 총 실점
  int rank; // 순위 (1위, 2위 ...)

  TeamStanding({
    required this.teamKey,
    required this.playerIds,
    required this.playerNames,
    this.playerTiers = const [],
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.pointsFor = 0,
    this.pointsAgainst = 0,
    this.rank = 1,
  });

  /// 팀 표시 이름 (예: "안세영 & 서승재")
  String get teamName => playerNames.join(' & ');

  /// 득실차 (득점 - 실점)
  int get pointDifference => pointsFor - pointsAgainst;

  /// 승률 (퍼센트: 0.0 ~ 100.0)
  double get winRate =>
      matchesPlayed > 0 ? (wins / matchesPlayed) * 100 : 0.0;

  TeamStanding copyWith({
    String? teamKey,
    List<String>? playerIds,
    List<String>? playerNames,
    List<Tier>? playerTiers,
    int? matchesPlayed,
    int? wins,
    int? losses,
    int? draws,
    int? pointsFor,
    int? pointsAgainst,
    int? rank,
  }) {
    return TeamStanding(
      teamKey: teamKey ?? this.teamKey,
      playerIds: playerIds ?? this.playerIds,
      playerNames: playerNames ?? this.playerNames,
      playerTiers: playerTiers ?? this.playerTiers,
      matchesPlayed: matchesPlayed ?? this.matchesPlayed,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      draws: draws ?? this.draws,
      pointsFor: pointsFor ?? this.pointsFor,
      pointsAgainst: pointsAgainst ?? this.pointsAgainst,
      rank: rank ?? this.rank,
    );
  }

  @override
  String toString() {
    return '$rank위: $teamName ($wins승 $losses패, 득실차 $pointDifference, 총득점 $pointsFor)';
  }
}

/// 토너먼트 참가/입상 페어 정보
class TournamentTeamNode {
  final String teamKey;
  final List<String> playerIds;
  final List<String> playerNames;
  final List<Tier> playerTiers;
  final int wins;
  final int losses;
  final int pointsFor;
  final int pointsAgainst;

  const TournamentTeamNode({
    required this.teamKey,
    required this.playerIds,
    required this.playerNames,
    this.playerTiers = const [],
    this.wins = 0,
    this.losses = 0,
    this.pointsFor = 0,
    this.pointsAgainst = 0,
  });

  String get teamName => playerNames.join(' & ');
  int get pointDifference => pointsFor - pointsAgainst;
}

/// 토너먼트 진출 단계별 그룹 (우승, 준우승, 4강, 8강 등)
class TournamentStagePlacement {
  final String stageTitle; // 예: "우승", "준우승", "4강", "8강"
  final String badgeEmoji; // 예: "🏆", "🥈", "🥉", "🎖️"
  final int roundNumber; // 해당 단계가 결정된 라운드 번호
  final List<TournamentTeamNode> teams;

  const TournamentStagePlacement({
    required this.stageTitle,
    required this.badgeEmoji,
    required this.roundNumber,
    required this.teams,
  });
}

/// 토너먼트 최종 트리 및 진출 단계 요약 모델
class TournamentResultTree {
  final TournamentTeamNode? champion; // 우승 페어
  final TournamentTeamNode? runnerUp; // 준우승 페어
  final List<TournamentTeamNode> semiFinalists; // 4강 진출 페어들
  final List<TournamentStagePlacement> stagePlacements; // 전체 진출 단계 목록 (우승 -> 준우승 -> 4강 -> 8강...)
  final Map<int, List<GameMatch>> matchesByRound; // 라운드별 대진 트리 매치 목록

  const TournamentResultTree({
    this.champion,
    this.runnerUp,
    this.semiFinalists = const [],
    this.stagePlacements = const [],
    this.matchesByRound = const {},
  });
}

