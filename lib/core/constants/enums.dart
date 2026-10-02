// 콕매치(CockMatch) 도메인 전역 열거형 정의

/// 성별 구분 (남성 / 여성 / 미지정)
enum Gender {
  male('M', '남성'),
  female('F', '여성'),
  undefined('U', '미지정');

  final String code;
  final String label;

  const Gender(this.code, this.label);

  static Gender fromCode(String? code) {
    if (code == null) return Gender.male;
    final normalized = code.trim().toUpperCase();
    if (normalized == 'F' || normalized == 'FEMALE' || normalized == '여' || normalized == '여성') {
      return Gender.female;
    }
    if (normalized == 'U' || normalized == 'UNDEFINED' || normalized == '미지정') {
      return Gender.undefined;
    }
    return Gender.male;
  }
}

/// 배드민턴 급수 체계 및 가중치
/// S(6점), A(5점), B(4점), C(3점), D(2점), 초심/novice(1점)
enum Tier {
  s('S', 'S조', 6),
  a('A', 'A조', 5),
  b('B', 'B조', 4),
  c('C', 'C조', 3),
  d('D', 'D조', 2),
  novice('초심', '초심', 1);

  final String code;
  final String label;
  final int weight;

  const Tier(this.code, this.label, this.weight);

  /// 하위 호환성을 위한 alias
  static const Tier beginner = Tier.novice;

  /// 상위부 여부 (S, A, B)
  bool get isHighTier => this == Tier.s || this == Tier.a || this == Tier.b;

  /// 하위부 여부 (C, D, 초심)
  bool get isLowTier => !isHighTier;

  static Tier fromString(String? value) {
    if (value == null) return Tier.novice;
    final clean = value.trim();
    if (clean.toLowerCase() == 'beginner' || clean == '초심' || clean == 'novice') {
      return Tier.novice;
    }
    final stripped = clean.replaceAll('조', '').replaceAll('급', '').trim();
    for (final tier in Tier.values) {
      if (tier.code.toLowerCase() == clean.toLowerCase() ||
          tier.label.toLowerCase() == clean.toLowerCase() ||
          tier.name.toLowerCase() == clean.toLowerCase() ||
          tier.code.toLowerCase() == stripped.toLowerCase()) {
        return tier;
      }
    }
    return Tier.novice;
  }
}

/// 클럽 회원 직책 및 등급
enum MemberRole {
  president('president', '회장'),
  vicePresident('vicePresident', '부회장'),
  manager('manager', '총무'),
  matchDirector('matchDirector', '경기이사'),
  member('member', '정회원'),
  associate('associate', '준회원');

  final String code;
  final String label;

  const MemberRole(this.code, this.label);

  /// 운영진 직책 여부 (회장, 부회장, 총무, 경기이사)
  bool get isExecutive =>
      this == MemberRole.president ||
      this == MemberRole.vicePresident ||
      this == MemberRole.manager ||
      this == MemberRole.matchDirector;

  static MemberRole fromCode(String? code) {
    if (code == null) return MemberRole.member;
    final normalized = code.trim().toLowerCase();
    if (normalized == '회원' || normalized == '정회원' || normalized == 'member') {
      return MemberRole.member;
    }
    if (normalized == '준회원' || normalized == 'associate') {
      return MemberRole.associate;
    }
    for (final role in MemberRole.values) {
      if (role.code.toLowerCase() == normalized ||
          role.name.toLowerCase() == normalized ||
          role.label.toLowerCase() == normalized) {
        return role;
      }
    }
    return MemberRole.member;
  }
}

/// 회원 등급(자격) 필터 구분: [운영진], [정회원], [준회원], [게스트]
enum MemberGrade {
  executive('executive', '운영진'),
  regular('regular', '정회원'),
  associate('associate', '준회원'),
  guest('guest', '게스트');

  final String code;
  final String label;

  const MemberGrade(this.code, this.label);
}

/// 회원 활동 상태 (활동/정회원, 휴면, 탈퇴)
enum MemberStatus {
  active('active', '활동/정회원'),
  resting('resting', '휴면'),
  withdrawn('withdrawn', '탈퇴');

  final String code;
  final String label;

  const MemberStatus(this.code, this.label);

  static MemberStatus fromCode(String? code) {
    if (code == null) return MemberStatus.active;
    final normalized = code.trim().toLowerCase();
    for (final status in MemberStatus.values) {
      if (status.code.toLowerCase() == normalized || status.name.toLowerCase() == normalized) {
        return status;
      }
    }
    return MemberStatus.active;
  }
}

/// 선수 매칭 모드 (급수 기준 3단 옵션)
/// 1. tiered: 급수별 분리 매칭 (추천) - 상위부/하위부 독립 코트 배정
/// 2. all: 통합 밸런스 매칭 - 전체 인원 통합 후 A+D vs B+C 실력 밸런스 배정
/// 3. random: 급수 무관 (랜덤 매칭) - 급수 점수를 고려하지 않고 출전 인원 내 완전 무작위 셔플 매칭
enum MatchMode {
  tiered('tiered', '급수 분리', '상위부/하위부 독립 코트 배정'),
  all('all', '급수 밸런스', '전체 인원 통합 후 A+D vs B+C 실력 밸런스 배정'),
  random('random', '급수 무관', '급수 점수를 고려하지 않고 출전 인원 내 완전 무작위 셔플 매칭');

  final String code;
  final String label;
  final String description;

  const MatchMode(this.code, this.label, this.description);

  /// 가독성용 별칭 (통합 밸런스 매칭 / 급수 밸런스)
  static const MatchMode balanced = MatchMode.all;

  static MatchMode fromCode(String? code) {
    if (code == null) return MatchMode.tiered;
    final normalized = code.trim().toLowerCase();
    if (normalized == 'all' ||
        normalized == 'balanced' ||
        normalized == '통합' ||
        normalized == '통합매칭' ||
        normalized == '통합밸런스매칭' ||
        normalized == '급수밸런스' ||
        normalized == '급수 밸런스') {
      return MatchMode.all;
    }
    if (normalized == 'random' ||
        normalized == '랜덤' ||
        normalized == '급수무관' ||
        normalized == '랜덤매칭') {
      return MatchMode.random;
    }
    return MatchMode.tiered;
  }
}

/// 파트너 편성 방식 (개인별 로테이션 vs 전원 고정 페어)
enum PartnerMode {
  rotation('rotation', '랜덤 파트너', '매 라운드 파트너와 상대가 자동 교체/순환'),
  fixedAll('fixedAll', '고정 파트너', '모든 참가자가 2인 1조 페어를 구성하여 모임 내내 해당 팀 단위로 대결');

  final String code;
  final String label;
  final String description;

  const PartnerMode(this.code, this.label, this.description);

  static PartnerMode fromCode(String? code) {
    if (code == null) return PartnerMode.rotation;
    final normalized = code.trim().toLowerCase();
    if (normalized == 'fixedall' ||
        normalized == 'fixed_all' ||
        normalized == 'fixed' ||
        normalized == '고정파트너' ||
        normalized == '고정 파트너' ||
        normalized == '전원고정페어') {
      return PartnerMode.fixedAll;
    }
    return PartnerMode.rotation;
  }
}

/// 게임 세션 진행 방식 (로테이션, 풀리그전, 토너먼트)
enum MatchFormat {
  regular('regular', '로테이션'),
  league('league', '풀리그전'),
  tournament('tournament', '토너먼트');

  final String code;
  final String label;

  const MatchFormat(this.code, this.label);

  static MatchFormat fromCode(String? code) {
    if (code == null) return MatchFormat.regular;
    final normalized = code.trim().toLowerCase();
    for (final format in MatchFormat.values) {
      if (format.code.toLowerCase() == normalized || format.name.toLowerCase() == normalized) {
        return format;
      }
    }
    return MatchFormat.regular;
  }
}

/// 성별 매칭 규칙 / 경기 종목 유형
/// 1. normal: 성별무관 - 성별 무관 실력/로테이션 위주 자유 매칭
/// 2. separate: 남복/여복 - 남성은 남복, 여성은 여복 코트로 분리 배정
/// 3. mixedOnly: 혼합복식 - 한 팀당 '남1 + 여1' 조합으로 매칭 강제
/// 4. genderPriority: 남복/여복 우선 - 남복/여복을 최우선 배정하고 성비 불균형 시에만 혼복 혼용
enum MatchType {
  normal('normal', '성별무관', '성별 무관 실력/로테이션 위주 자유 매칭'),
  separate('separate', '남복/여복', '남성은 남복, 여성은 여복 코트로 분리 배정'),
  mixedOnly('mixedOnly', '혼합복식', '한 팀당 남1 + 여1 조합으로 매칭 강제'),
  genderPriority('genderPriority', '남복/여복 우선', '남복/여복 최우선 배정, 성비 불균형 시만 혼복 혼용'),
  menOnly('menOnly', '남자복식 전용', '남성 회원만 출전 배정'),
  womenOnly('womenOnly', '여자복식 전용', '여성 회원만 출전 배정');

  final String code;
  final String label;
  final String description;

  const MatchType(this.code, this.label, this.description);

  /// 대진 설정 화면에서 선택할 수 있는 4가지 핵심 성별 매칭 옵션
  static const List<MatchType> primaryOptions = [
    MatchType.normal,
    MatchType.separate,
    MatchType.mixedOnly,
    MatchType.genderPriority,
  ];

  static MatchType fromCode(String? code) {
    if (code == null) return MatchType.normal;
    final normalized = code.trim().toLowerCase();
    for (final type in MatchType.values) {
      if (type.code.toLowerCase() == normalized || type.name.toLowerCase() == normalized) {
        return type;
      }
    }
    return MatchType.normal;
  }
}

/// 경기 진행 상태
enum MatchStatus {
  pending('pending', '대기'),
  playing('playing', '진행중'),
  finished('finished', '완료');

  final String code;
  final String label;

  const MatchStatus(this.code, this.label);

  static MatchStatus fromCode(String? code) {
    if (code == null) return MatchStatus.pending;
    final normalized = code.trim().toLowerCase();
    for (final status in MatchStatus.values) {
      if (status.code == normalized || status.name == normalized) {
        return status;
      }
    }
    return MatchStatus.pending;
  }
}

/// 당일 모임 참석자 출전 상태 (출전 / 휴식 / 조퇴)
enum AttendanceStatus {
  active('active', '출전'),
  resting('resting', '휴식'),
  withdrawn('withdrawn', '조퇴');

  final String code;
  final String label;

  const AttendanceStatus(this.code, this.label);

  static AttendanceStatus fromCode(String? code) {
    if (code == null) return AttendanceStatus.active;
    final normalized = code.trim().toLowerCase();
    if (normalized == '출전' || normalized == '출전대기' || normalized == '출전 대기') {
      return AttendanceStatus.active;
    }
    if (normalized == '휴식' || normalized == '일시휴식' || normalized == '일시 휴식') {
      return AttendanceStatus.resting;
    }
    if (normalized == '조퇴' || normalized == '조퇴/부상' || normalized == '조퇴 / 부상') {
      return AttendanceStatus.withdrawn;
    }
    for (final status in AttendanceStatus.values) {
      if (status.code == normalized || status.name == normalized) {
        return status;
      }
    }
    return AttendanceStatus.active;
  }
}

/// 당일 모임 참석자 회비 납부 상태 (완납 / 미납 / 면제)
enum FeeStatus {
  paid('paid', '완납'),
  unpaid('unpaid', '미납'),
  exempt('exempt', '면제');

  final String code;
  final String label;

  const FeeStatus(this.code, this.label);

  static FeeStatus fromCode(String? code, {bool? fallbackFeePaid}) {
    if (code != null && code.trim().isNotEmpty) {
      final normalized = code.trim().toLowerCase();
      if (normalized == 'paid' || normalized == '완납') {
        return FeeStatus.paid;
      }
      if (normalized == 'exempt' || normalized == '면제') {
        return FeeStatus.exempt;
      }
      if (normalized == 'unpaid' || normalized == '미납') {
        return FeeStatus.unpaid;
      }
    }
    if (fallbackFeePaid != null) {
      return fallbackFeePaid ? FeeStatus.paid : FeeStatus.unpaid;
    }
    return FeeStatus.unpaid;
  }
}

/// 회원별 회비 부과 기준 (할인 및 면제 정책)
/// 1. standard: 기본 회비 부과 (기본값 - 클럽 기본 정기/일일회비 적용)
/// 2. discounted: 차등/할인 금액 지정 (직접 부과할 금액 입력, 예: 가족할인 20,000원)
/// 3. exempt: 회비 면제 ('영구 면제' 또는 '기간 지정 면제')
enum FeePolicyType {
  standard('standard', '기본 회비 부과', '클럽 기본 정기/일일회비 적용'),
  discounted('discounted', '차등/할인 금액 지정', '직접 부과할 금액 입력 (예: 가족할인 20,000원)'),
  exempt('exempt', '회비 면제', '영구 면제 또는 기간 지정 면제');

  final String code;
  final String label;
  final String description;

  const FeePolicyType(this.code, this.label, this.description);

  static FeePolicyType fromCode(String? code) {
    if (code == null) return FeePolicyType.standard;
    final normalized = code.trim().toLowerCase();
    if (normalized == 'discounted' ||
        normalized == 'discount' ||
        normalized == '차등' ||
        normalized == '할인') {
      return FeePolicyType.discounted;
    }
    if (normalized == 'exempt' || normalized == '면제') {
      return FeePolicyType.exempt;
    }
    return FeePolicyType.standard;
  }
}


