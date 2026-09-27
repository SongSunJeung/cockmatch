import '../../models/models.dart';

/// 앱 초기 실행 시 즉시 대진표 생성 및 검색 테스트가 가능한 실전 클럽 데이터
class MockData {
  MockData._();

  /// 다중 클럽/모임 목록 (관리자가 전환 가능한 모임들)
  static final List<Club> initialClubs = [
    const Club(
      id: 'club_mega',
      ownerId: 'admin_1',
      clubName: '메가 배드민턴 클럽',
      description: '화/목 19:00 정기모임 · 4코트 운영',
      memberCount: 21,
    ),
    const Club(
      id: 'club_gangnam',
      ownerId: 'admin_1',
      clubName: '강남 에이스 동호회',
      description: '월/수/금 20:00 모임 · 2코트 운영',
      memberCount: 8,
    ),
    const Club(
      id: 'club_dawn',
      ownerId: 'admin_1',
      clubName: '새벽콕 주말 번개모임',
      description: '토/일 07:00 아침 운동 · 2코트 운영',
      memberCount: 6,
    ),
  ];

  /// 메가 배드민턴 클럽 회원 (21명)
  static final List<Member> _megaMembers = [
    Member(
      id: 'm01',
      clubId: 'club_mega',
      name: '안세영',
      gender: Gender.female,
      tier: Tier.a,
      role: MemberRole.matchDirector,
      status: MemberStatus.active,
      phoneNumber: '010-1111-2222',
      homeClub: '메가콕클럽',
      feePaid: true,
    ),
    Member(
      id: 'm02',
      clubId: 'club_mega',
      name: '이용대',
      gender: Gender.male,
      tier: Tier.a,
      role: MemberRole.president,
      status: MemberStatus.active,
      phoneNumber: '010-2222-3333',
      homeClub: '메가콕클럽',
      feeStatus: FeeStatus.exempt,
    ),
    Member(
      id: 'm03',
      clubId: 'club_mega',
      name: '손흥민',
      gender: Gender.male,
      tier: Tier.b,
      role: MemberRole.vicePresident,
      status: MemberStatus.active,
      phoneNumber: '010-3333-4444',
      feePaid: true,
    ),
    Member(
      id: 'm04',
      clubId: 'club_mega',
      name: '김연아',
      gender: Gender.female,
      tier: Tier.b,
      role: MemberRole.manager,
      status: MemberStatus.active,
      phoneNumber: '010-4444-5555',
      feePolicy: FeePolicyType.exempt,
      isPermanentExempt: false,
      exemptUntilDate: '2026.12.31',
      feeStatus: FeeStatus.exempt,
    ),
    Member(
      id: 'm05',
      clubId: 'club_mega',
      name: '유재석',
      gender: Gender.male,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-5555-6666',
      feePaid: true,
    ),
    Member(
      id: 'm06',
      clubId: 'club_mega',
      name: '강호동',
      gender: Gender.male,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-6666-7777',
      feePolicy: FeePolicyType.discounted,
      customFeeLabel: '가족할인',
      customFeeAmount: 20000,
      feePaid: true,
    ),
    Member(
      id: 'm07',
      clubId: 'club_mega',
      name: '박지성',
      gender: Gender.male,
      tier: Tier.a,
      customRoleTitle: '자문위원',
      status: MemberStatus.active,
      phoneNumber: '010-7777-8888',
      feePaid: true,
    ),
    Member(
      id: 'm08',
      clubId: 'club_mega',
      name: '이효리',
      gender: Gender.female,
      tier: Tier.d,
      status: MemberStatus.active,
      phoneNumber: '010-8888-9999',
      feePaid: true,
    ),
    Member(
      id: 'm09',
      clubId: 'club_mega',
      name: '정우성',
      gender: Gender.male,
      tier: Tier.b,
      status: MemberStatus.active,
      phoneNumber: '010-9999-0000',
      feePaid: true,
    ),
    Member(
      id: 'm10',
      clubId: 'club_mega',
      name: '한지민',
      gender: Gender.female,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-1212-3434',
      feePaid: true,
    ),
    Member(
      id: 'm11',
      clubId: 'club_mega',
      name: '송중기',
      gender: Gender.male,
      tier: Tier.b,
      status: MemberStatus.active,
      phoneNumber: '010-2323-4545',
      feePaid: true,
    ),
    Member(
      id: 'm12',
      clubId: 'club_mega',
      name: '송혜교',
      gender: Gender.female,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-3434-5656',
      feePaid: true,
    ),
    Member(
      id: 'm13',
      clubId: 'club_mega',
      name: '이정재',
      gender: Gender.male,
      tier: Tier.a,
      status: MemberStatus.active,
      phoneNumber: '010-4545-6767',
      feePaid: true,
    ),
    Member(
      id: 'm14',
      clubId: 'club_mega',
      name: '전지현',
      gender: Gender.female,
      tier: Tier.b,
      status: MemberStatus.active,
      phoneNumber: '010-5656-7878',
      feePaid: true,
    ),
    Member(
      id: 'm15',
      clubId: 'club_mega',
      name: '조인성',
      gender: Gender.male,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-6767-8989',
      feePaid: true,
    ),
    Member(
      id: 'm16',
      clubId: 'club_mega',
      name: '김민재',
      gender: Gender.male,
      tier: Tier.c,
      role: MemberRole.associate,
      status: MemberStatus.active,
      phoneNumber: '010-7878-9090',
      feePaid: true,
    ),
    Member(
      id: 'm17',
      clubId: 'club_mega',
      name: '신유빈',
      gender: Gender.female,
      tier: Tier.b,
      status: MemberStatus.active,
      phoneNumber: '010-8989-0101',
      feePaid: true,
    ),
    Member(
      id: 'm18',
      clubId: 'club_mega',
      name: '황희찬',
      gender: Gender.male,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-9090-1212',
      feePaid: true,
    ),
    Member(
      id: 'm19',
      clubId: 'club_mega',
      name: '조규성',
      gender: Gender.male,
      tier: Tier.d,
      role: MemberRole.associate,
      status: MemberStatus.active,
      phoneNumber: '010-2468-1357',
      feePaid: false,
    ),
    Member(
      id: 'm20',
      clubId: 'club_mega',
      name: '배수지',
      gender: Gender.female,
      tier: Tier.novice,
      role: MemberRole.associate,
      status: MemberStatus.active,
      phoneNumber: '010-1357-2468',
      feePaid: false,
    ),
    Member(
      id: 'm21',
      clubId: 'club_mega',
      name: '아이유',
      gender: Gender.female,
      tier: Tier.d,
      status: MemberStatus.resting,
      restingStartDate: '2026.09.01',
      restingReturnDate: '2026.11.30',
      restingReason: '엘보 부상',
      phoneNumber: '010-3690-1470',
      feePaid: false,
    ),
  ];

  /// 강남 에이스 동호회 회원 (8명)
  static final List<Member> _gangnamMembers = [
    Member(
      id: 'gn01',
      clubId: 'club_gangnam',
      name: '이민우',
      gender: Gender.male,
      tier: Tier.a,
      role: MemberRole.president,
      status: MemberStatus.active,
      phoneNumber: '010-8888-1111',
      feePaid: true,
    ),
    Member(
      id: 'gn02',
      clubId: 'club_gangnam',
      name: '박하늘',
      gender: Gender.female,
      tier: Tier.a,
      role: MemberRole.matchDirector,
      status: MemberStatus.active,
      phoneNumber: '010-8888-2222',
      feePaid: true,
    ),
    Member(
      id: 'gn03',
      clubId: 'club_gangnam',
      name: '정다은',
      gender: Gender.female,
      tier: Tier.b,
      role: MemberRole.manager,
      status: MemberStatus.active,
      phoneNumber: '010-8888-3333',
      feePaid: true,
    ),
    Member(
      id: 'gn04',
      clubId: 'club_gangnam',
      name: '송지호',
      gender: Gender.male,
      tier: Tier.b,
      status: MemberStatus.active,
      phoneNumber: '010-8888-4444',
      feePaid: true,
    ),
    Member(
      id: 'gn05',
      clubId: 'club_gangnam',
      name: '한소희',
      gender: Gender.female,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-8888-5555',
      feePaid: false,
    ),
    Member(
      id: 'gn06',
      clubId: 'club_gangnam',
      name: '강동원',
      gender: Gender.male,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-8888-6666',
      feePaid: true,
    ),
    Member(
      id: 'gn07',
      clubId: 'club_gangnam',
      name: '정우진',
      gender: Gender.male,
      tier: Tier.d,
      status: MemberStatus.active,
      phoneNumber: '010-8888-7777',
      feePaid: true,
    ),
    Member(
      id: 'gn08',
      clubId: 'club_gangnam',
      name: '김지원',
      gender: Gender.female,
      tier: Tier.novice,
      status: MemberStatus.active,
      phoneNumber: '010-8888-8888',
      feePaid: false,
    ),
  ];

  /// 새벽콕 주말 번개모임 회원 (6명)
  static final List<Member> _dawnMembers = [
    Member(
      id: 'dw01',
      clubId: 'club_dawn',
      name: '최영진',
      gender: Gender.male,
      tier: Tier.a,
      role: MemberRole.president,
      status: MemberStatus.active,
      phoneNumber: '010-7777-1111',
      feePaid: true,
    ),
    Member(
      id: 'dw02',
      clubId: 'club_dawn',
      name: '문채원',
      gender: Gender.female,
      tier: Tier.b,
      role: MemberRole.manager,
      status: MemberStatus.active,
      phoneNumber: '010-7777-2222',
      feePaid: true,
    ),
    Member(
      id: 'dw03',
      clubId: 'club_dawn',
      name: '박보검',
      gender: Gender.male,
      tier: Tier.b,
      status: MemberStatus.active,
      phoneNumber: '010-7777-3333',
      feePaid: true,
    ),
    Member(
      id: 'dw04',
      clubId: 'club_dawn',
      name: '임윤아',
      gender: Gender.female,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-7777-4444',
      feePaid: true,
    ),
    Member(
      id: 'dw05',
      clubId: 'club_dawn',
      name: '공유',
      gender: Gender.male,
      tier: Tier.c,
      status: MemberStatus.active,
      phoneNumber: '010-7777-5555',
      feePaid: true,
    ),
    Member(
      id: 'dw06',
      clubId: 'club_dawn',
      name: '서현진',
      gender: Gender.female,
      tier: Tier.d,
      status: MemberStatus.active,
      phoneNumber: '010-7777-6666',
      feePaid: false,
    ),
  ];

  /// 전체 회원 통합 풀
  static final List<Member> initialMembers = [
    ..._megaMembers,
    ..._gangnamMembers,
    ..._dawnMembers,
  ];

  /// 보관(아카이빙)된 지난 모임 히스토리 초기 데이터
  /// - 모임이 종료되어도 절대 자동 삭제되지 않고 보존되는 [지난 모임] 기록
  static final List<GameSession> initialArchivedSessions = [
    GameSession(
      id: 'session_mega_archive_0922',
      clubId: 'club_mega',
      title: '2026.09.22 화요 정기 모임',
      sessionDate: '2026-09-22',
      courtCount: 3,
      startCourtNumber: 1,
      memberFee: 5000,
      guestFee: 10000,
      matchFormat: MatchFormat.regular,
      matchType: MatchType.normal,
      matchMode: MatchMode.tiered,
      attendees: const ['m01', 'm02', 'm03', 'm04', 'm05', 'm06', 'm07', 'm08', 'm09', 'm10', 'm11', 'm12'],
      attendeeStatusMap: const {
        'm01': AttendanceStatus.active,
        'm02': AttendanceStatus.active,
        'm03': AttendanceStatus.active,
        'm04': AttendanceStatus.active,
        'm05': AttendanceStatus.active,
        'm06': AttendanceStatus.active,
        'm07': AttendanceStatus.active,
        'm08': AttendanceStatus.active,
        'm09': AttendanceStatus.active,
        'm10': AttendanceStatus.active,
        'm11': AttendanceStatus.resting,
        'm12': AttendanceStatus.withdrawn,
      },
      attendeeFeeStatusMap: const {
        'm01': FeeStatus.paid,
        'm02': FeeStatus.exempt,
        'm03': FeeStatus.paid,
        'm04': FeeStatus.exempt,
        'm05': FeeStatus.paid,
        'm06': FeeStatus.paid,
        'm07': FeeStatus.paid,
        'm08': FeeStatus.paid,
        'm09': FeeStatus.paid,
        'm10': FeeStatus.paid,
        'm11': FeeStatus.paid,
        'm12': FeeStatus.paid,
      },
      currentRound: 2,
      isCompleted: true,
      completedAt: DateTime(2026, 9, 22, 22, 0),
      createdAt: DateTime(2026, 9, 22, 19, 0),
    ),
    GameSession(
      id: 'session_mega_archive_0919',
      clubId: 'club_mega',
      title: '2026.09.19 주말 교류전',
      sessionDate: '2026-09-19',
      courtCount: 2,
      startCourtNumber: 1,
      memberFee: 5000,
      guestFee: 10000,
      matchFormat: MatchFormat.league,
      matchType: MatchType.mixedOnly,
      matchMode: MatchMode.all,
      attendees: const ['m01', 'm02', 'm03', 'm04', 'm09', 'm10', 'm11', 'm12'],
      attendeeStatusMap: const {
        'm01': AttendanceStatus.active,
        'm02': AttendanceStatus.active,
        'm03': AttendanceStatus.active,
        'm04': AttendanceStatus.active,
        'm09': AttendanceStatus.active,
        'm10': AttendanceStatus.active,
        'm11': AttendanceStatus.active,
        'm12': AttendanceStatus.active,
      },
      attendeeFeeStatusMap: const {
        'm01': FeeStatus.paid,
        'm02': FeeStatus.exempt,
        'm03': FeeStatus.paid,
        'm04': FeeStatus.exempt,
        'm09': FeeStatus.paid,
        'm10': FeeStatus.paid,
        'm11': FeeStatus.paid,
        'm12': FeeStatus.unpaid,
      },
      currentRound: 2,
      isCompleted: true,
      completedAt: DateTime(2026, 9, 19, 18, 0),
      createdAt: DateTime(2026, 9, 19, 14, 0),
    ),
    GameSession(
      id: 'session_mega_archive_0915',
      clubId: 'club_mega',
      title: '2026.09.15 추계 클럽 토너먼트',
      sessionDate: '2026-09-15',
      courtCount: 2,
      startCourtNumber: 1,
      memberFee: 10000,
      guestFee: 15000,
      matchFormat: MatchFormat.tournament,
      matchType: MatchType.normal,
      matchMode: MatchMode.all,
      attendees: const ['m01', 'm02', 'm03', 'm04', 'm05', 'm06', 'm07', 'm08'],
      attendeeStatusMap: const {
        'm01': AttendanceStatus.active,
        'm02': AttendanceStatus.active,
        'm03': AttendanceStatus.active,
        'm04': AttendanceStatus.active,
        'm05': AttendanceStatus.active,
        'm06': AttendanceStatus.active,
        'm07': AttendanceStatus.active,
        'm08': AttendanceStatus.active,
      },
      attendeeFeeStatusMap: const {
        'm01': FeeStatus.paid,
        'm02': FeeStatus.exempt,
        'm03': FeeStatus.paid,
        'm04': FeeStatus.exempt,
        'm05': FeeStatus.paid,
        'm06': FeeStatus.paid,
        'm07': FeeStatus.paid,
        'm08': FeeStatus.paid,
      },
      currentRound: 2,
      isCompleted: true,
      completedAt: DateTime(2026, 9, 15, 17, 30),
      createdAt: DateTime(2026, 9, 15, 13, 0),
    ),
  ];

  /// 보관(아카이빙)된 지난 모임의 경기 전적 초기 데이터
  static final Map<String, List<GameMatch>> initialArchivedMatches = {
    'session_mega_archive_0922': const [
      GameMatch(
        id: 'arch_0922_r1_c1',
        sessionId: 'session_mega_archive_0922',
        round: 1,
        courtNumber: 1,
        teamA: ['m01', 'm08'],
        teamB: ['m02', 'm05'],
        scoreA: 25,
        scoreB: 22,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0922_r1_c2',
        sessionId: 'session_mega_archive_0922',
        round: 1,
        courtNumber: 2,
        teamA: ['m03', 'm06'],
        teamB: ['m04', 'm09'],
        scoreA: 21,
        scoreB: 25,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0922_r2_c1',
        sessionId: 'session_mega_archive_0922',
        round: 2,
        courtNumber: 1,
        teamA: ['m01', 'm05'],
        teamB: ['m07', 'm10'],
        scoreA: 25,
        scoreB: 19,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0922_r2_c2',
        sessionId: 'session_mega_archive_0922',
        round: 2,
        courtNumber: 2,
        teamA: ['m02', 'm09'],
        teamB: ['m03', 'm08'],
        scoreA: 25,
        scoreB: 20,
        status: MatchStatus.finished,
      ),
    ],
    'session_mega_archive_0919': const [
      GameMatch(
        id: 'arch_0919_r1_c1',
        sessionId: 'session_mega_archive_0919',
        round: 1,
        courtNumber: 1,
        teamA: ['m02', 'm01'],
        teamB: ['m03', 'm04'],
        scoreA: 25,
        scoreB: 23,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0919_r1_c2',
        sessionId: 'session_mega_archive_0919',
        round: 1,
        courtNumber: 2,
        teamA: ['m09', 'm10'],
        teamB: ['m11', 'm12'],
        scoreA: 20,
        scoreB: 25,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0919_r2_c1',
        sessionId: 'session_mega_archive_0919',
        round: 2,
        courtNumber: 1,
        teamA: ['m02', 'm01'],
        teamB: ['m11', 'm12'],
        scoreA: 25,
        scoreB: 21,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0919_r2_c2',
        sessionId: 'session_mega_archive_0919',
        round: 2,
        courtNumber: 2,
        teamA: ['m03', 'm04'],
        teamB: ['m09', 'm10'],
        scoreA: 25,
        scoreB: 18,
        status: MatchStatus.finished,
      ),
    ],
    'session_mega_archive_0915': const [
      GameMatch(
        id: 'arch_0915_r1_c1',
        sessionId: 'session_mega_archive_0915',
        round: 1,
        courtNumber: 1,
        teamA: ['m01', 'm02'],
        teamB: ['m05', 'm06'],
        scoreA: 25,
        scoreB: 18,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0915_r1_c2',
        sessionId: 'session_mega_archive_0915',
        round: 1,
        courtNumber: 2,
        teamA: ['m03', 'm04'],
        teamB: ['m07', 'm08'],
        scoreA: 25,
        scoreB: 21,
        status: MatchStatus.finished,
      ),
      GameMatch(
        id: 'arch_0915_r2_c1',
        sessionId: 'session_mega_archive_0915',
        round: 2,
        courtNumber: 1,
        teamA: ['m01', 'm02'],
        teamB: ['m03', 'm04'],
        scoreA: 25,
        scoreB: 22,
        status: MatchStatus.finished,
      ),
    ],
  };

  /// 특정 클럽의 초기 세션 데이터 생성
  static GameSession getInitialSessionForClub(String clubId) {
    if (clubId == 'club_gangnam') {
      final attendees = _gangnamMembers.where((m) => m.status == MemberStatus.active).map((m) => m.id).toList();
      return GameSession(
        id: 'session_gangnam_today',
        clubId: 'club_gangnam',
        title: '강남 에이스 월수금 정기모임',
        sessionDate: '2026-09-25',
        courtCount: 2, // 2코트
        memberFee: 6000,
        guestFee: 10000,
        matchFormat: MatchFormat.regular,
        matchType: MatchType.normal,
        matchMode: MatchMode.all,
        attendees: attendees,
        activeAttendees: attendees,
        currentRound: 1,
      );
    } else if (clubId == 'club_dawn') {
      final attendees = _dawnMembers.where((m) => m.status == MemberStatus.active).map((m) => m.id).toList();
      return GameSession(
        id: 'session_dawn_today',
        clubId: 'club_dawn',
        title: '새벽콕 주말 상쾌한 아침 운동',
        sessionDate: '2026-09-25',
        courtCount: 1, // 1코트
        memberFee: 3000,
        guestFee: 5000,
        matchFormat: MatchFormat.regular,
        matchType: MatchType.normal,
        matchMode: MatchMode.tiered,
        attendees: attendees,
        activeAttendees: attendees,
        currentRound: 1,
      );
    }

    // 기본 메가 배드민턴 클럽
    final attendees = _megaMembers.where((m) => m.status == MemberStatus.active).map((m) => m.id).toList();
    return GameSession(
      id: 'session_mega_today',
      clubId: 'club_mega',
      title: '메가콕 정기 모임',
      sessionDate: '2026-09-25',
      courtCount: 4, // 4코트 운영 (라운드당 16명 출전)
      memberFee: 5000,
      guestFee: 10000,
      matchFormat: MatchFormat.regular,
      matchType: MatchType.normal,
      matchMode: MatchMode.tiered,
      attendees: attendees,
      activeAttendees: attendees,
      currentRound: 1,
    );
  }

  /// 기본 초기 세션
  static GameSession initialSession = getInitialSessionForClub('club_mega');

  /// 클럽별 기본 회비 정책 및 계좌 정보 초기값
  static final Map<String, ClubFeePolicy> initialClubFeePolicies = {
    'club_mega': const ClubFeePolicy(
      clubId: 'club_mega',
      defaultMonthlyFee: 30000,
      paymentDueDay: 25,
      bankName: '카카오뱅크',
      accountNumber: '3333-01-5829104',
      accountHolder: '김연아(메가배드민턴)',
      rulesAndMemo: ClubFeePolicy.defaultRulesText,
    ),
    'club_gangnam': const ClubFeePolicy(
      clubId: 'club_gangnam',
      defaultMonthlyFee: 35000,
      paymentDueDay: 20,
      bankName: '신한은행',
      accountNumber: '110-482-991023',
      accountHolder: '박서준(강남에이스)',
      rulesAndMemo:
          '1. 정기 월 회비: 월 35,000원 (매월 20일 마감)\n'
          '2. 부부/가족 할인: 1인당 월 25,000원 적용\n'
          '3. 장기 부상·출장 휴회 신청 시 해당 기간 회비 면제',
    ),
    'club_dawn': const ClubFeePolicy(
      clubId: 'club_dawn',
      defaultMonthlyFee: 25000,
      paymentDueDay: 25,
      bankName: '토스뱅크',
      accountNumber: '1000-8291-4402',
      accountHolder: '차은우(새벽콕)',
      rulesAndMemo:
          '1. 정기 월 회비: 월 25,000원 (매월 25일 마감)\n'
          '2. 총무·회장 운영진 회비 면제 적용',
    ),
  };

  /// 연간/월별 회비 납부 현황표 초기 시드 데이터 생성 (2025년 ~ 2026년)
  static Map<String, MonthlyFeeRecord> buildInitialFeeLedgerMap() {
    final map = <String, MonthlyFeeRecord>{};

    for (final member in initialMembers) {
      if (member.isGuest) continue;
      final clubId = member.clubId ?? 'club_mega';
      final policy = initialClubFeePolicies[clubId] ??
          ClubFeePolicy(clubId: clubId);
      final standardFee =
          FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);

      // 2025년: 1~12월 전체 완납(면제자는 자동 면제) 시드
      for (int m = 1; m <= 12; m++) {
        final autoReason2025 =
            FeeLedgerCalculator.resolveAutoExemptReason(member, 2025, m);
        final key2025 = FeeLedgerCalculator.buildCellKey(
          clubId: clubId,
          year: 2025,
          memberId: member.id,
          month: m,
        );
        if (autoReason2025 != null) {
          map[key2025] = MonthlyFeeRecord(
            status: FeeStatus.exempt,
            paidAmount: 0,
            memo: autoReason2025,
          );
        } else {
          final mm = m.toString().padLeft(2, '0');
          map[key2025] = MonthlyFeeRecord(
            status: FeeStatus.paid,
            paidAmount: standardFee,
            paidDate: '2025.$mm.18',
            memo: member.feePolicy == FeePolicyType.discounted
                ? '${member.customFeeLabel ?? "할인"} 적용'
                : '정기 자동이체',
          );
        }
      }

      // 2026년: 1~8월 완납, 9월(당월)은 회원 현재 feeStatus 반영, 10~12월은 미납/면제 기본 반영
      for (int m = 1; m <= 12; m++) {
        final autoReason =
            FeeLedgerCalculator.resolveAutoExemptReason(member, 2026, m);
        final key = FeeLedgerCalculator.buildCellKey(
          clubId: clubId,
          year: 2026,
          memberId: member.id,
          month: m,
        );

        if (autoReason != null) {
          map[key] = MonthlyFeeRecord(
            status: FeeStatus.exempt,
            paidAmount: 0,
            memo: autoReason,
          );
          continue;
        }

        final mm = m.toString().padLeft(2, '0');
        if (m <= 8) {
          map[key] = MonthlyFeeRecord(
            status: FeeStatus.paid,
            paidAmount: standardFee,
            paidDate: '2026.$mm.18',
            memo: member.feePolicy == FeePolicyType.discounted
                ? '${member.customFeeLabel ?? "할인"} 적용'
                : '정기 납부 완료',
          );
        } else if (m == 9) {
          if (member.feeStatus == FeeStatus.paid) {
            map[key] = MonthlyFeeRecord(
              status: FeeStatus.paid,
              paidAmount: standardFee,
              paidDate: '2026.09.15',
              memo: member.feePolicy == FeePolicyType.discounted
                  ? '${member.customFeeLabel ?? "할인"} 입금 완료'
                  : '9월 정기회비 완납',
            );
          } else {
            map[key] = MonthlyFeeRecord(
              status: FeeStatus.unpaid,
              paidAmount: standardFee,
              memo: '9월 납부 대기',
            );
          }
        }
      }
    }

    return map;
  }
}
