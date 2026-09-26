import '../core/constants/enums.dart';
import 'member.dart';

/// 회원명부 정렬 기준 (기본값: 이름 가나다순 ㄱ -> ㅎ)
enum MemberSortBy {
  nameAsc('이름순 (가나다)', '이름순 (가나다) [기본]'),
  tierDesc('급수순 (A -> 초심)', '급수순 (상위 급수 우선: A -> 초심)'),
  gradeFirst('회원 구분순', '회원 구분순 (운영진 -> 정회원 -> 준회원)'),
  recentRegistered('최근 등록순', '최근 등록순'),
  tierAsc('급수 낮은순 (초심->A)', '급수 낮은순 (초심 -> A)'),
  roleFirst('직책 우선순', '직책 우선순');

  final String label;
  final String menuLabel;
  const MemberSortBy(this.label, this.menuLabel);

  /// 회원명부 탭에서 선택 가능한 4가지 정렬 옵션
  static const List<MemberSortBy> memberPoolOptions = [
    MemberSortBy.nameAsc,
    MemberSortBy.tierDesc,
    MemberSortBy.gradeFirst,
    MemberSortBy.recentRegistered,
  ];
}

/// 출석부 정렬 기준 (기본값: 급수순 상위 급수 우선 A -> 초심)
enum AttendanceSortBy {
  tierDesc('급수순 (A -> 초심)', '급수순 (A -> 초심) [기본]'),
  nameAsc('이름순 (가나다)', '이름순 (가나다)'),
  attendanceStatus('출전 상태순', '출전 상태순 (출전 -> 휴식 -> 조퇴)'),
  feeUnpaidFirst('회비 상태순', '회비 상태순 (미납자 최우선 정렬)');

  final String label;
  final String menuLabel;
  const AttendanceSortBy(this.label, this.menuLabel);
}

/// 회원 풀 다중 필터링 및 정렬 조건 모델
class MemberFilter {
  final String searchQuery;
  final Gender? gender; // null = 전체
  final Tier? tier; // null = 전체
  final MemberGrade? grade; // null = 전체, executive = 운영진, regular = 정회원, associate = 준회원
  final MemberStatus? status; // null = 전체
  final bool? isGuest; // null = 전체, true = 게스트만, false = 회원만
  final MemberRole? role; // null = 전체
  final MemberSortBy sortBy; // 기본값: 이름 가나다순 (ㄱ -> ㅎ)

  const MemberFilter({
    this.searchQuery = '',
    this.gender,
    this.tier,
    this.grade,
    this.status,
    this.isGuest,
    this.role,
    this.sortBy = MemberSortBy.nameAsc,
  });

  /// 필터 초기화 상태 (기본 필터 및 기본 정렬: 이름 가나다순)
  factory MemberFilter.initial() => const MemberFilter();

  /// 활성화된 필터 조건이 하나라도 있는지 여부
  bool get hasActiveFilters =>
      tier != null ||
      grade != null ||
      gender != null ||
      status != null ||
      role != null ||
      isGuest != null;

  /// 특정 회원이 필터 조건들을 모두 만족하는지 판별
  bool matches(Member member) {
    // 1. 이름 및 초성 검색 매칭
    if (searchQuery.isNotEmpty && !member.matchesSearch(searchQuery)) {
      return false;
    }
    // 2. 성별 필터
    if (gender != null && member.gender != gender) {
      return false;
    }
    // 3. 급수 필터
    if (tier != null && member.tier != tier) {
      return false;
    }
    // 4. 회원 등급(자격) 필터: [운영진], [정회원], [준회원]
    if (grade != null && member.grade != grade) {
      return false;
    }
    // 5. 회원 상태 필터 (활동/휴면/탈퇴)
    if (status != null && member.status != status) {
      return false;
    }
    // 6. 게스트 여부 필터
    if (isGuest != null && member.isGuest != isGuest) {
      return false;
    }
    // 7. 세부 직책 필터
    if (role != null && member.role != role) {
      return false;
    }
    return true;
  }

  MemberFilter copyWith({
    String? searchQuery,
    Gender? gender,
    bool clearGender = false,
    Tier? tier,
    bool clearTier = false,
    MemberGrade? grade,
    bool clearGrade = false,
    MemberStatus? status,
    bool clearStatus = false,
    bool? isGuest,
    bool clearIsGuest = false,
    MemberRole? role,
    bool clearRole = false,
    MemberSortBy? sortBy,
  }) {
    return MemberFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      gender: clearGender ? null : (gender ?? this.gender),
      tier: clearTier ? null : (tier ?? this.tier),
      grade: clearGrade ? null : (grade ?? this.grade),
      status: clearStatus ? null : (status ?? this.status),
      isGuest: clearIsGuest ? null : (isGuest ?? this.isGuest),
      role: clearRole ? null : (role ?? this.role),
      sortBy: sortBy ?? this.sortBy,
    );
  }
}


