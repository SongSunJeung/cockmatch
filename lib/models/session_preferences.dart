import 'dart:convert';
import '../core/constants/enums.dart';

/// '오늘 모임 세션 & 대진 설정' 및 '[+ 새 모임 시작하기]' 직전 설정값 자동 기억(Persistence) 모델
class SessionPreferences {
  /// 경기 방식 (기본 권장값: 정기 모임 로테이션)
  final MatchFormat matchFormat;

  /// 운영 코트 수 (null이면 참석 인원 기반 자동 추천 코트 수 적용, 값이 있으면 직전 설정 코트 수 유지)
  final int? courtCount;

  /// 시작 코트 번호 (기본 권장값: 1번 코트)
  final int startCourtNumber;

  /// 선수 매칭 모드 - 급수 기준 (기본 권장값: 급수별 분리 매칭)
  final MatchMode matchMode;

  /// 성별 매칭 옵션 (기본 권장값: 전체 혼합)
  final MatchType matchType;

  /// 파트너 편성 방식 (기본 권장값: 개인별 로테이션)
  final PartnerMode partnerMode;

  /// 고정 파트너(복식팀) 페어 목록 (예: [['m01', 'm02']])
  final List<List<String>> fixedPairs;

  /// [+ 새 모임 시작하기] 모임 타이틀 프리셋 (기본값: '정기 모임')
  final String titlePreset;

  /// [+ 새 모임 시작하기] 정회원 참가비 (기본값: 5000원)
  final int memberFee;

  /// [+ 새 모임 시작하기] 게스트 참가비 (기본값: 10000원)
  final int guestFee;

  /// 정회원 참가비 직접 입력 여부
  final bool isCustomMemberFee;

  /// 게스트 참가비 직접 입력 여부
  final bool isCustomGuestFee;

  /// 사용자가 최소 1회 이상 설정을 저장했는지 여부
  final bool hasSavedPreferences;

  const SessionPreferences({
    this.matchFormat = MatchFormat.regular,
    this.courtCount,
    this.startCourtNumber = 1,
    this.matchMode = MatchMode.tiered,
    this.matchType = MatchType.normal,
    this.partnerMode = PartnerMode.rotation,
    this.fixedPairs = const [],
    this.titlePreset = '정기 모임',
    this.memberFee = 5000,
    this.guestFee = 10000,
    this.isCustomMemberFee = false,
    this.isCustomGuestFee = false,
    this.hasSavedPreferences = false,
  });

  /// 앱 최초 기본 권장 설정 생성자
  factory SessionPreferences.defaults() => const SessionPreferences();

  /// 현재 설정이 앱 최초 기본 권장 설정과 동일한지 여부 확인
  bool isDefaultRecommended({int? recommendedCourts}) {
    final effectiveCourtMatch =
        courtCount == null || (recommendedCourts != null && courtCount == recommendedCourts);
    return matchFormat == MatchFormat.regular &&
        effectiveCourtMatch &&
        startCourtNumber == 1 &&
        matchMode == MatchMode.tiered &&
        matchType == MatchType.normal &&
        partnerMode == PartnerMode.rotation &&
        fixedPairs.isEmpty;
  }

  Map<String, dynamic> toMap() {
    return {
      'matchFormat': matchFormat.code,
      'courtCount': courtCount,
      'startCourtNumber': startCourtNumber,
      'matchMode': matchMode.code,
      'matchType': matchType.code,
      'partnerMode': partnerMode.code,
      'fixedPairs': fixedPairs,
      'titlePreset': titlePreset,
      'memberFee': memberFee,
      'guestFee': guestFee,
      'isCustomMemberFee': isCustomMemberFee,
      'isCustomGuestFee': isCustomGuestFee,
      'hasSavedPreferences': hasSavedPreferences,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory SessionPreferences.fromMap(Map<String, dynamic> map) {
    final rawPairs = map['fixedPairs'];
    final List<List<String>> parsedPairs = [];
    if (rawPairs is List) {
      for (final item in rawPairs) {
        if (item is List && item.length >= 2) {
          parsedPairs.add([item[0].toString(), item[1].toString()]);
        }
      }
    }

    return SessionPreferences(
      matchFormat: MatchFormat.fromCode(map['matchFormat'] as String? ?? 'REGULAR'),
      courtCount: map['courtCount'] as int?,
      startCourtNumber: (map['startCourtNumber'] as int? ?? 1).clamp(1, 50),
      matchMode: MatchMode.fromCode(map['matchMode'] as String? ?? 'TIERED'),
      matchType: MatchType.fromCode(map['matchType'] as String? ?? 'NORMAL'),
      partnerMode: PartnerMode.fromCode(map['partnerMode'] as String? ?? 'ROTATION'),
      fixedPairs: parsedPairs,
      titlePreset: map['titlePreset'] as String? ?? '정기 모임',
      memberFee: map['memberFee'] as int? ?? 5000,
      guestFee: map['guestFee'] as int? ?? 10000,
      isCustomMemberFee: map['isCustomMemberFee'] as bool? ?? false,
      isCustomGuestFee: map['isCustomGuestFee'] as bool? ?? false,
      hasSavedPreferences: map['hasSavedPreferences'] as bool? ?? true,
    );
  }

  factory SessionPreferences.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return SessionPreferences.fromMap(decoded);
    }
    return SessionPreferences.defaults();
  }

  SessionPreferences copyWith({
    MatchFormat? matchFormat,
    int? courtCount,
    bool clearCourtCount = false,
    int? startCourtNumber,
    MatchMode? matchMode,
    MatchType? matchType,
    PartnerMode? partnerMode,
    List<List<String>>? fixedPairs,
    String? titlePreset,
    int? memberFee,
    int? guestFee,
    bool? isCustomMemberFee,
    bool? isCustomGuestFee,
    bool? hasSavedPreferences,
  }) {
    return SessionPreferences(
      matchFormat: matchFormat ?? this.matchFormat,
      courtCount: clearCourtCount ? null : (courtCount ?? this.courtCount),
      startCourtNumber: startCourtNumber ?? this.startCourtNumber,
      matchMode: matchMode ?? this.matchMode,
      matchType: matchType ?? this.matchType,
      partnerMode: partnerMode ?? this.partnerMode,
      fixedPairs: fixedPairs ?? this.fixedPairs,
      titlePreset: titlePreset ?? this.titlePreset,
      memberFee: memberFee ?? this.memberFee,
      guestFee: guestFee ?? this.guestFee,
      isCustomMemberFee: isCustomMemberFee ?? this.isCustomMemberFee,
      isCustomGuestFee: isCustomGuestFee ?? this.isCustomGuestFee,
      hasSavedPreferences: hasSavedPreferences ?? this.hasSavedPreferences,
    );
  }
}
