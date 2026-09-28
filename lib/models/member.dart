import '../core/constants/enums.dart';
import '../core/utils/korean_search_util.dart';

/// 클럽 회원 정보 모델
/// Firestore 경로: clubs/{clubId}/members/{memberId}
class Member {
  final String id;
  final String? clubId;
  final String name; // 필수: 이름 하나만 있어도 등록 및 대진 매칭 가능
  final Gender gender; // 성별 미입력 시 Gender.male 또는 Gender.undefined
  final Tier tier; // 급수 미입력 시 기본값 Tier.novice(초심)
  final MemberRole role; // 직책: member, president, vicePresident, manager, matchDirector, associate
  final String? customRoleTitle; // 커스텀 직책/등급 명칭 (예: 자문위원, 고문, 학생회원 등)
  final MemberStatus status; // 회원 상태: active(활동 회원), resting(휴면/휴회 회원), withdrawn(탈퇴)
  final String? restingStartDate; // 휴면 시작일 (예: "2026.09.26")
  final String? restingReturnDate; // 휴면 복귀 예정일 (예: "2026.11.30")
  final String? restingReason; // 휴면 사유 (예: "엘보 부상", "장기 출장")
  final FeePolicyType feePolicy; // 회비 부과 기준: standard(기본), discounted(차등/할인), exempt(면제)
  final int? customFeeAmount; // 차등/할인 부과 금액 (예: 20000)
  final String? customFeeLabel; // 차등/할인 명칭 (예: "가족할인")
  final bool isPermanentExempt; // 회비 면제 시 영구 면제 여부 (false일 경우 기간 지정 면제)
  final String? exemptStartDate; // 기간 지정 면제 시작일 (예: "2026.09.01")
  final String? exemptUntilDate; // 기간 지정 면제 종료일 (예: "2026.12.31")
  final bool isGuest; // 게스트 여부
  final FeeStatus feeStatus; // 당일 참가비/콕비 납부 상태 (완납/미납/면제)
  final String? homeClub; // 타 클럽 교류전/게스트 출신 클럽 기록용
  final String? phoneNumber; // 연락처 (선택)
  final String? memo; // 회원 비고/메모 (CSV 연동 및 관리용)
  final DateTime? joinedAt; // 가입 일자 (기본값 등록 시점)
  final DateTime? leftAt; // 탈퇴 일자 (선택)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Member({
    required this.id,
    this.clubId,
    required this.name,
    this.gender = Gender.male,
    this.tier = Tier.novice,
    this.role = MemberRole.member,
    this.customRoleTitle,
    this.status = MemberStatus.active,
    this.restingStartDate,
    this.restingReturnDate,
    this.restingReason,
    this.feePolicy = FeePolicyType.standard,
    this.customFeeAmount,
    this.customFeeLabel,
    this.isPermanentExempt = true,
    this.exemptStartDate,
    this.exemptUntilDate,
    this.isGuest = false,
    bool feePaid = false,
    FeeStatus? feeStatus,
    this.homeClub,
    this.phoneNumber,
    this.memo,
    DateTime? joinedAt,
    this.leftAt,
    this.createdAt,
    this.updatedAt,
  })  : feeStatus = feeStatus ??
            (feePaid
                ? FeeStatus.paid
                : (status == MemberStatus.resting || feePolicy == FeePolicyType.exempt
                    ? FeeStatus.exempt
                    : FeeStatus.unpaid)),
        joinedAt = joinedAt ?? DateTime.now();

  /// 날짜 문자열("2026-11-30" 또는 "2026.11.30")을 "26.11.30" 축약 형식으로 변환
  static String formatShortDate(String rawDate) {
    final trimmed = rawDate.trim().replaceAll('-', '.').replaceAll('/', '.');
    final parts = trimmed.split('.');
    if (parts.length == 3) {
      final year = parts[0].length == 4 ? parts[0].substring(2) : parts[0];
      final month = parts[1].padLeft(2, '0');
      final day = parts[2].padLeft(2, '0');
      return '$year.$month.$day';
    }
    return trimmed;
  }

  /// 천단위 콤마 금액 포맷 (예: 20000 -> "20,000")
  static String formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  /// 당일 참가비 완납 여부 (하위 호환성 유지)
  bool get feePaid => feeStatus == FeeStatus.paid;

  /// 당일 참가비 면제 여부 (휴면 회원이거나 회비 면제 정책 적용 시 자동 면제 연동)
  bool get isFeeExempt =>
      feeStatus == FeeStatus.exempt ||
      status == MemberStatus.resting ||
      feePolicy == FeePolicyType.exempt;

  /// 당일 참가비 미납 여부 (면제자는 미납으로 분류하지 않음)
  bool get isFeeUnpaid => !isFeeExempt && feeStatus == FeeStatus.unpaid;

  /// 정회원/활동 회원 여부
  bool get isActive => status == MemberStatus.active;

  /// 휴면(휴회) 회원 여부
  bool get isResting => status == MemberStatus.resting;

  /// 휴면(휴회) 회원의 자동 회비 면제('휴회 면제') 대상 여부
  bool get isRestingExempt => status == MemberStatus.resting;

  /// 운영진 직책 보유 여부 (회장, 부회장, 총무, 경기이사)
  bool get isExecutive => role.isExecutive;

  /// 화면 표시용 직책/등급 명칭 (커스텀 직책이 지정된 경우 우선 표시)
  String get displayRoleLabel {
    if (customRoleTitle != null && customRoleTitle!.trim().isNotEmpty) {
      return customRoleTitle!.trim();
    }
    return role.label;
  }

  /// 회원 명부 카드 표시용 [휴면] 상태 뱃지 텍스트
  /// - 예: "휴면 (복귀 예정 26.11.30)" 또는 "휴면"
  String? get restingBadgeText {
    if (status != MemberStatus.resting) return null;
    if (restingReturnDate != null && restingReturnDate!.trim().isNotEmpty) {
      return '휴면 (복귀 예정 ${formatShortDate(restingReturnDate!)})';
    }
    return '휴면';
  }

  /// 회원 명부 카드 표시용 [회비 혜택/면제] 뱃지 텍스트
  /// - 휴면 회원: "휴회 면제"
  /// - 회비 면제: "면제 (~26.12.31)" 또는 "면제 (영구)"
  /// - 차등/할인(가족할인 등) 지정: "가족회원"
  String? get feePolicyBadgeText {
    if (status == MemberStatus.resting) {
      return '휴회 면제';
    }
    if (feePolicy == FeePolicyType.exempt) {
      if (!isPermanentExempt) {
        final hasStart = exemptStartDate != null && exemptStartDate!.trim().isNotEmpty;
        final hasUntil = exemptUntilDate != null && exemptUntilDate!.trim().isNotEmpty;
        if (hasStart && hasUntil) {
          return '면제 (${formatShortDate(exemptStartDate!)}~${formatShortDate(exemptUntilDate!)})';
        }
        if (hasUntil) {
          return '면제 (~${formatShortDate(exemptUntilDate!)})';
        }
      }
      return '면제 (영구)';
    }
    if (feePolicy == FeePolicyType.discounted) {
      return '가족회원';
    }
    return null;
  }

  /// 회원 등급(자격) 분류: 운영진 / 정회원 / 준회원
  MemberGrade get grade {
    if (role.isExecutive) return MemberGrade.executive;
    if (role == MemberRole.associate) return MemberGrade.associate;
    return MemberGrade.regular;
  }

  /// 회원의 급수 가중치 점수 (A: 5, B: 4, C: 3, D: 2, 초심: 1)
  int get tierWeight => tier.weight;

  /// 상위부(A, B) 여부
  bool get isHighTier => tier.isHighTier;

  /// 하위부(C, D, 초심) 여부
  bool get isLowTier => tier.isLowTier;

  /// 이름의 한글 초성 (검색 최적화용)
  String get choseong => KoreanSearchUtil.extractChoseong(name);

  /// 검색어(이름 또는 초성)와 일치하는지 여부
  bool matchesSearch(String query) {
    return KoreanSearchUtil.matches(name, query);
  }

  /// Firestore 저장용 Map 변환
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'gender': gender.code,
      'tier': tier.code,
      'role': role.code,
      if (customRoleTitle != null && customRoleTitle!.trim().isNotEmpty)
        'customRoleTitle': customRoleTitle!.trim(),
      'status': status.code,
      if (restingStartDate != null && restingStartDate!.trim().isNotEmpty)
        'restingStartDate': restingStartDate!.trim(),
      if (restingReturnDate != null && restingReturnDate!.trim().isNotEmpty)
        'restingReturnDate': restingReturnDate!.trim(),
      if (restingReason != null && restingReason!.trim().isNotEmpty)
        'restingReason': restingReason!.trim(),
      'feePolicy': feePolicy.code,
      if (customFeeAmount != null) 'customFeeAmount': customFeeAmount,
      if (customFeeLabel != null && customFeeLabel!.trim().isNotEmpty)
        'customFeeLabel': customFeeLabel!.trim(),
      'isPermanentExempt': isPermanentExempt,
      if (exemptStartDate != null && exemptStartDate!.trim().isNotEmpty)
        'exemptStartDate': exemptStartDate!.trim(),
      if (exemptUntilDate != null && exemptUntilDate!.trim().isNotEmpty)
        'exemptUntilDate': exemptUntilDate!.trim(),
      'isGuest': isGuest,
      'feePaid': feePaid,
      'feeStatus': feeStatus.code,
      'isActive': isActive,
      if (homeClub != null) 'homeClub': homeClub,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (memo != null) 'memo': memo,
      if (joinedAt != null) 'joinedAt': joinedAt!.toIso8601String(),
      if (leftAt != null) 'leftAt': leftAt!.toIso8601String(),
      'createdAt': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (clubId != null) 'clubId': clubId,
    };
  }

  /// Firestore 데이터로부터 인스턴스 복원
  factory Member.fromMap(Map<String, dynamic> map, {required String id}) {
    // 상태값 복원: status 필드 우선, 없을 경우 기존 isActive boolean 고려
    MemberStatus memberStatus;
    if (map['status'] != null) {
      memberStatus = MemberStatus.fromCode(map['status'] as String?);
    } else if (map['isActive'] != null) {
      memberStatus = (map['isActive'] as bool) ? MemberStatus.active : MemberStatus.resting;
    } else {
      memberStatus = MemberStatus.active;
    }

    final restoredFeePolicy = FeePolicyType.fromCode(map['feePolicy'] as String?);

    final restoredFeeStatus = FeeStatus.fromCode(
      map['feeStatus'] as String?,
      fallbackFeePaid: map['feePaid'] as bool?,
    );

    return Member(
      id: id,
      clubId: map['clubId'] as String?,
      name: (map['name'] as String?)?.trim() ?? '무명',
      gender: Gender.fromCode(map['gender'] as String?),
      tier: Tier.fromString(map['tier'] as String?),
      role: MemberRole.fromCode(map['role'] as String?),
      customRoleTitle: map['customRoleTitle'] as String?,
      status: memberStatus,
      restingStartDate: map['restingStartDate'] as String?,
      restingReturnDate: map['restingReturnDate'] as String?,
      restingReason: map['restingReason'] as String?,
      feePolicy: restoredFeePolicy,
      customFeeAmount: (map['customFeeAmount'] as num?)?.toInt(),
      customFeeLabel: map['customFeeLabel'] as String?,
      isPermanentExempt: (map['isPermanentExempt'] as bool?) ?? true,
      exemptStartDate: map['exemptStartDate'] as String?,
      exemptUntilDate: map['exemptUntilDate'] as String?,
      isGuest: (map['isGuest'] as bool?) ?? false,
      feeStatus: (memberStatus == MemberStatus.resting ||
              restoredFeePolicy == FeePolicyType.exempt)
          ? FeeStatus.exempt
          : restoredFeeStatus,
      homeClub: map['homeClub'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      memo: map['memo'] as String?,
      joinedAt: map['joinedAt'] != null
          ? DateTime.tryParse(map['joinedAt'] as String)
          : null,
      leftAt: map['leftAt'] != null
          ? DateTime.tryParse(map['leftAt'] as String)
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  Member copyWith({
    String? id,
    String? clubId,
    String? name,
    Gender? gender,
    Tier? tier,
    MemberRole? role,
    String? customRoleTitle,
    bool clearCustomRoleTitle = false,
    MemberStatus? status,
    String? restingStartDate,
    String? restingReturnDate,
    String? restingReason,
    bool clearRestingFields = false,
    FeePolicyType? feePolicy,
    int? customFeeAmount,
    String? customFeeLabel,
    bool clearCustomFee = false,
    bool? isPermanentExempt,
    String? exemptStartDate,
    bool clearExemptStartDate = false,
    String? exemptUntilDate,
    bool clearExemptUntilDate = false,
    bool? isGuest,
    bool? feePaid,
    FeeStatus? feeStatus,
    String? homeClub,
    String? phoneNumber,
    String? memo,
    DateTime? joinedAt,
    DateTime? leftAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextStatus = status ?? this.status;
    final nextFeePolicy = feePolicy ?? this.feePolicy;

    FeeStatus resolvedFeeStatus;
    if (feeStatus != null) {
      resolvedFeeStatus = feeStatus;
    } else if (feePaid != null) {
      resolvedFeeStatus = feePaid ? FeeStatus.paid : FeeStatus.unpaid;
    } else if (nextStatus == MemberStatus.resting ||
        nextFeePolicy == FeePolicyType.exempt) {
      resolvedFeeStatus = FeeStatus.exempt;
    } else {
      resolvedFeeStatus = this.feeStatus;
    }

    return Member(
      id: id ?? this.id,
      clubId: clubId ?? this.clubId,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      tier: tier ?? this.tier,
      role: role ?? this.role,
      customRoleTitle:
          clearCustomRoleTitle ? null : (customRoleTitle ?? this.customRoleTitle),
      status: nextStatus,
      restingStartDate:
          clearRestingFields ? null : (restingStartDate ?? this.restingStartDate),
      restingReturnDate:
          clearRestingFields ? null : (restingReturnDate ?? this.restingReturnDate),
      restingReason:
          clearRestingFields ? null : (restingReason ?? this.restingReason),
      feePolicy: nextFeePolicy,
      customFeeAmount:
          clearCustomFee ? null : (customFeeAmount ?? this.customFeeAmount),
      customFeeLabel:
          clearCustomFee ? null : (customFeeLabel ?? this.customFeeLabel),
      isPermanentExempt: isPermanentExempt ?? this.isPermanentExempt,
      exemptStartDate:
          clearExemptStartDate ? null : (exemptStartDate ?? this.exemptStartDate),
      exemptUntilDate:
          clearExemptUntilDate ? null : (exemptUntilDate ?? this.exemptUntilDate),
      isGuest: isGuest ?? this.isGuest,
      feeStatus: resolvedFeeStatus,
      homeClub: homeClub ?? this.homeClub,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      memo: memo ?? this.memo,
      joinedAt: joinedAt ?? this.joinedAt,
      leftAt: leftAt ?? this.leftAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Member && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Member(id: $id, name: $name, gender: ${gender.label}, tier: ${tier.label}, role: $displayRoleLabel, status: ${status.label}, feePolicy: ${feePolicy.label}, isGuest: $isGuest, feeStatus: ${feeStatus.label})';
  }
}

