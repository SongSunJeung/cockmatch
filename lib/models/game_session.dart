import '../core/constants/enums.dart';
import 'member.dart';

/// 당일 모임 세션 정보 모델
/// Firestore 경로: game_sessions/{sessionId}
class GameSession {
  final String id;
  final String clubId;
  final String? title; // 모임 타이틀 (미입력 시 "YYYY.MM.DD 정기 모임")
  final String sessionDate; // 예: "2026-09-25"
  final int courtCount; // 다중 코트 설정 지원 (1 ~ 15)
  final int startCourtNumber; // 시작 코트 번호 (기본 1, 예: 5번 코트부터 시작)
  final int memberFee; // 정회원 참가비/콕비 (기본 0원)
  final int guestFee; // 게스트 참가비 (기본 0원)
  final MatchFormat matchFormat; // regular(일반), league(리그), tournament(토너먼트)
  final MatchType matchType; // normal(전체혼합), separate(남복/여복분리), mixedOnly(혼복), genderPriority(남복/여복우선)
  final MatchMode matchMode; // tiered(급수별 분리), all(통합 밸런스), random(급수 무관 랜덤)
  final PartnerMode partnerMode; // rotation(개인별 로테이션), fixedAll(전원 고정 페어)
  final List<List<String>> fixedPairs; // 고정 파트너 2인 페어 목록 (예: [['m1', 'm2'], ['m3', 'm4']])
  final List<String> attendees; // 당일 출석 체크 전체 명단 (memberId 목록)
  final Map<String, AttendanceStatus> attendeeStatusMap; // 각 참석자의 출전 상태 (active/resting/withdrawn)
  final Map<String, FeeStatus> attendeeFeeStatusMap; // 모임별 회비 납부 상태 스냅샷 (아카이빙 보존용)
  final List<String>? _activeAttendees; // 하위 호환용 전달 리스트
  final int currentRound; // 현재 진행 중인 라운드
  final bool isCompleted; // 모임 종료(완료/아카이빙) 여부 (true = 지난 모임, false = 진행 모임)
  final DateTime? completedAt; // 모임 종료 시각
  final bool isGameEnded; // 당일 경기 종료 여부 (true = 경기 종료됨/결과 확정, false = 경기 진행 중)
  final DateTime? gameEndedAt; // 경기 종료 시각
  final DateTime? createdAt;

  const GameSession({
    required this.id,
    required this.clubId,
    this.title,
    required this.sessionDate,
    this.courtCount = 4,
    this.startCourtNumber = 1,
    this.memberFee = 0,
    this.guestFee = 0,
    this.matchFormat = MatchFormat.regular,
    this.matchType = MatchType.normal,
    this.matchMode = MatchMode.tiered,
    this.partnerMode = PartnerMode.rotation,
    this.fixedPairs = const [],
    this.attendees = const [],
    this.attendeeStatusMap = const {},
    this.attendeeFeeStatusMap = const {},
    List<String>? activeAttendees,
    this.currentRound = 1,
    this.isCompleted = false,
    this.completedAt,
    this.isGameEnded = false,
    this.gameEndedAt,
    this.createdAt,
    // ignore: prefer_initializing_formals
  }) : _activeAttendees = activeAttendees;

  /// 화면 표시용 모임 타이틀
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title!.trim();
    }
    final formattedDate = sessionDate.replaceAll('-', '.');
    return '$formattedDate 정기 모임';
  }

  /// 경기 종료 후 회비 수납 및 모임 정산 진행 중인지 여부 (정산 대기)
  bool get isSettling => isGameEnded && !isCompleted;

  /// 모임 진행/정산/종료 라이프사이클 라벨
  String get lifecycleStatusText {
    if (isCompleted) return '지난 모임';
    if (isGameEnded) return '정산 대기';
    return '진행 모임';
  }

  /// 당일 전체 출석 인원 수
  int get attendeeCount => effectiveAttendees.length;

  /// attendees가 비어있고 _activeAttendees만 전달된 경우를 포괄하는 유효 참석자 명단
  List<String> get effectiveAttendees {
    if (attendees.isNotEmpty) return attendees;
    final active = _activeAttendees;
    if (active != null) return active;
    return const [];
  }

  /// 각 참석자의 출전 상태 (기본값: 출전 대기 - active)
  AttendanceStatus getAttendeeStatus(String memberId) {
    if (attendeeStatusMap.containsKey(memberId)) {
      return attendeeStatusMap[memberId]!;
    }
    final active = _activeAttendees;
    if (attendeeStatusMap.isEmpty && active != null) {
      return active.contains(memberId)
          ? AttendanceStatus.active
          : AttendanceStatus.resting;
    }
    return AttendanceStatus.active;
  }

  /// 실시간 출전 가능 명단 (지각/조퇴/휴식 및 신규 게스트 실시간 반영)
  List<String> get activeAttendees {
    return effectiveAttendees
        .where((id) => getAttendeeStatus(id) == AttendanceStatus.active)
        .toList();
  }

  /// 일시 휴식 중인 인원 명단
  List<String> get restingAttendees {
    return effectiveAttendees
        .where((id) => getAttendeeStatus(id) == AttendanceStatus.resting)
        .toList();
  }

  /// 조퇴한 인원 명단
  List<String> get withdrawnAttendees {
    return effectiveAttendees
        .where((id) => getAttendeeStatus(id) == AttendanceStatus.withdrawn)
        .toList();
  }

  /// 실시간 출전 가능 인원 수
  int get activeAttendeeCount => activeAttendees.length;

  /// 코트 동시 수용 가능 최대 인원 수 (코트당 4명)
  int get maxSimultaneousPlayers => courtCount * 4;

  /// 특정 회원의 출석 여부
  bool hasAttendee(String memberId) => effectiveAttendees.contains(memberId);

  /// 특정 회원의 실시간 출전 가능 여부
  bool isAttendeeActive(String memberId) =>
      hasAttendee(memberId) && getAttendeeStatus(memberId) == AttendanceStatus.active;

  /// 특정 회원의 해당 모임 회비 상태 조회 (세션 스냅샷이 있으면 우선 사용, 없으면 회원 현재 상태 및 면제/휴회 정책 반영)
  FeeStatus getAttendeeFeeStatus(Member member) {
    if (attendeeFeeStatusMap.containsKey(member.id)) {
      return attendeeFeeStatusMap[member.id]!;
    }
    if (member.status == MemberStatus.resting ||
        member.feePolicy == FeePolicyType.exempt) {
      return FeeStatus.exempt;
    }
    return member.feeStatus;
  }

  /// 출석자 목록 기반 예상/집계 총 참가비 계산 (면제자는 수납 대상 금액에서 제외)
  int calculateTotalFee(List<Member> allMembers) {
    int total = 0;
    for (final member in allMembers) {
      if (hasAttendee(member.id) && getAttendeeFeeStatus(member) != FeeStatus.exempt) {
        total += member.isGuest ? guestFee : memberFee;
      }
    }
    return total;
  }

  /// 수납 완료된 총 금액 계산 (완납자만 합산)
  int calculatePaidFee(List<Member> allMembers) {
    int total = 0;
    for (final member in allMembers) {
      if (hasAttendee(member.id) && getAttendeeFeeStatus(member) == FeeStatus.paid) {
        total += member.isGuest ? guestFee : memberFee;
      }
    }
    return total;
  }

  /// 완납 인원 수 계산
  int calculatePaidCount(List<Member> allMembers) {
    return allMembers
        .where((m) => hasAttendee(m.id) && getAttendeeFeeStatus(m) == FeeStatus.paid)
        .length;
  }

  /// 미납 인원 수 계산 (면제자는 미납자에서 제외)
  int calculateUnpaidCount(List<Member> allMembers) {
    return allMembers
        .where((m) => hasAttendee(m.id) && getAttendeeFeeStatus(m) == FeeStatus.unpaid)
        .length;
  }

  /// 면제 인원 수 계산
  int calculateExemptCount(List<Member> allMembers) {
    return allMembers
        .where((m) => hasAttendee(m.id) && getAttendeeFeeStatus(m) == FeeStatus.exempt)
        .length;
  }

  /// 특정 회원의 고정 파트너 ID 조회 (고정 페어가 없으면 null 반환)
  String? getFixedPartnerId(String memberId) {
    for (final pair in fixedPairs) {
      if (pair.length == 2) {
        if (pair[0] == memberId) return pair[1];
        if (pair[1] == memberId) return pair[0];
      }
    }
    return null;
  }

  /// Firestore 저장용 Map 변환
  Map<String, dynamic> toMap() {
    return {
      'clubId': clubId,
      if (title != null) 'title': title,
      'sessionDate': sessionDate,
      'courtCount': courtCount,
      'startCourtNumber': startCourtNumber,
      'memberFee': memberFee,
      'guestFee': guestFee,
      'matchFormat': matchFormat.code,
      'matchType': matchType.code,
      'matchMode': matchMode.code,
      'partnerMode': partnerMode.code,
      'fixedPairs': fixedPairs
          .where((p) => p.length == 2)
          .map((p) => '${p[0]}:${p[1]}')
          .toList(),
      'attendees': effectiveAttendees,
      'attendeeStatusMap': attendeeStatusMap.map((k, v) => MapEntry(k, v.code)),
      'attendeeFeeStatusMap': attendeeFeeStatusMap.map((k, v) => MapEntry(k, v.code)),
      'activeAttendees': activeAttendees,
      'currentRound': currentRound,
      'isCompleted': isCompleted,
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      'isGameEnded': isGameEnded,
      if (gameEndedAt != null) 'gameEndedAt': gameEndedAt!.toIso8601String(),
      'createdAt': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Firestore 데이터로부터 인스턴스 복원
  factory GameSession.fromMap(Map<String, dynamic> map, {required String id}) {
    final attendeesList = (map['attendees'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final activeList = (map['activeAttendees'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();

    final rawStatusMap = map['attendeeStatusMap'] as Map<String, dynamic>?;
    final Map<String, AttendanceStatus> statusMap = {};
    if (rawStatusMap != null) {
      rawStatusMap.forEach((k, v) {
        statusMap[k] = AttendanceStatus.fromCode(v as String?);
      });
    } else if (activeList != null) {
      for (final attendee in attendeesList) {
        statusMap[attendee] = activeList.contains(attendee)
            ? AttendanceStatus.active
            : AttendanceStatus.resting;
      }
    }

    final rawFeeMap = map['attendeeFeeStatusMap'] as Map<String, dynamic>?;
    final Map<String, FeeStatus> feeStatusMap = {};
    if (rawFeeMap != null) {
      rawFeeMap.forEach((k, v) {
        feeStatusMap[k] = FeeStatus.fromCode(v as String?);
      });
    }

    final rawFixedPairs = map['fixedPairs'] as List<dynamic>?;
    final List<List<String>> parsedFixedPairs = [];
    if (rawFixedPairs != null) {
      for (final item in rawFixedPairs) {
        if (item is String && item.contains(':')) {
          final parts = item.split(':');
          if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
            parsedFixedPairs.add([parts[0], parts[1]]);
          }
        } else if (item is List && item.length == 2) {
          parsedFixedPairs.add([item[0].toString(), item[1].toString()]);
        }
      }
    }

    return GameSession(
      id: id,
      clubId: (map['clubId'] as String?) ?? '',
      title: map['title'] as String?,
      sessionDate: (map['sessionDate'] as String?) ?? '',
      courtCount: (map['courtCount'] as num?)?.toInt() ?? 4,
      startCourtNumber: (map['startCourtNumber'] as num?)?.toInt() ?? 1,
      memberFee: (map['memberFee'] as num?)?.toInt() ?? 0,
      guestFee: (map['guestFee'] as num?)?.toInt() ?? 0,
      matchFormat: MatchFormat.fromCode(map['matchFormat'] as String?),
      matchType: MatchType.fromCode(map['matchType'] as String?),
      matchMode: MatchMode.fromCode(map['matchMode'] as String?),
      partnerMode: PartnerMode.fromCode(map['partnerMode'] as String?),
      fixedPairs: parsedFixedPairs,
      attendees: attendeesList,
      attendeeStatusMap: statusMap,
      attendeeFeeStatusMap: feeStatusMap,
      activeAttendees: activeList,
      currentRound: (map['currentRound'] as num?)?.toInt() ?? 1,
      isCompleted: (map['isCompleted'] as bool?) ?? false,
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'] as String)
          : null,
      isGameEnded: (map['isGameEnded'] as bool?) ?? false,
      gameEndedAt: map['gameEndedAt'] != null
          ? DateTime.tryParse(map['gameEndedAt'] as String)
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }

  GameSession copyWith({
    String? id,
    String? clubId,
    String? title,
    String? sessionDate,
    int? courtCount,
    int? startCourtNumber,
    int? memberFee,
    int? guestFee,
    MatchFormat? matchFormat,
    MatchType? matchType,
    MatchMode? matchMode,
    PartnerMode? partnerMode,
    List<List<String>>? fixedPairs,
    List<String>? attendees,
    Map<String, AttendanceStatus>? attendeeStatusMap,
    Map<String, FeeStatus>? attendeeFeeStatusMap,
    List<String>? activeAttendees,
    int? currentRound,
    bool? isCompleted,
    DateTime? completedAt,
    bool? isGameEnded,
    DateTime? gameEndedAt,
    DateTime? createdAt,
  }) {
    return GameSession(
      id: id ?? this.id,
      clubId: clubId ?? this.clubId,
      title: title ?? this.title,
      sessionDate: sessionDate ?? this.sessionDate,
      courtCount: courtCount ?? this.courtCount,
      startCourtNumber: startCourtNumber ?? this.startCourtNumber,
      memberFee: memberFee ?? this.memberFee,
      guestFee: guestFee ?? this.guestFee,
      matchFormat: matchFormat ?? this.matchFormat,
      matchType: matchType ?? this.matchType,
      matchMode: matchMode ?? this.matchMode,
      partnerMode: partnerMode ?? this.partnerMode,
      fixedPairs: fixedPairs ?? this.fixedPairs,
      attendees: attendees ?? this.attendees,
      attendeeStatusMap: attendeeStatusMap ?? this.attendeeStatusMap,
      attendeeFeeStatusMap: attendeeFeeStatusMap ?? this.attendeeFeeStatusMap,
      activeAttendees: activeAttendees ?? _activeAttendees,
      currentRound: currentRound ?? this.currentRound,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      isGameEnded: isGameEnded ?? this.isGameEnded,
      gameEndedAt: gameEndedAt ?? this.gameEndedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameSession && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'GameSession(id: $id, title: $displayTitle, date: $sessionDate, courts: $courtCount, attendees: ${attendees.length}, active: $activeAttendeeCount)';
  }
}
