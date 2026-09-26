import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cockmatch/models/models.dart';
import 'package:cockmatch/providers/providers.dart';
import 'package:cockmatch/services/club_service.dart';
import 'package:cockmatch/core/utils/korean_search_util.dart';

void main() {
  group('KoreanSearchUtil Test', () {
    test('초성 추출 기능 검증', () {
      expect(KoreanSearchUtil.extractChoseong('홍길동'), equals('ㅎㄱㄷ'));
      expect(KoreanSearchUtil.extractChoseong('김민수'), equals('ㄱㅁㅅ'));
      expect(KoreanSearchUtil.extractChoseong('CockMatch'), equals('CockMatch'));
    });

    test('초성 및 일반 이름 검색 매칭 검증', () {
      expect(KoreanSearchUtil.matches('홍길동', 'ㅎㄱㄷ'), isTrue);
      expect(KoreanSearchUtil.matches('홍길동', '길동'), isTrue);
      expect(KoreanSearchUtil.matches('홍길동', 'ㄱㄷ'), isTrue);
      expect(KoreanSearchUtil.matches('홍길동', '이순신'), isFalse);
    });
  });

  group('Member Model Test', () {
    test('이름 하나만으로 기본 등록 시 기본값(초심, 남성, 활동, 일반회원) 부여 검증', () {
      final minimalMember = Member(id: 'm_min', name: '이순신');

      expect(minimalMember.name, equals('이순신'));
      expect(minimalMember.tier, equals(Tier.novice));
      expect(minimalMember.tierWeight, equals(1));
      expect(minimalMember.gender, equals(Gender.male));
      expect(minimalMember.role, equals(MemberRole.member));
      expect(minimalMember.status, equals(MemberStatus.active));
      expect(minimalMember.isActive, isTrue);
      expect(minimalMember.isGuest, isFalse);
      expect(minimalMember.feePaid, isFalse);
      expect(minimalMember.joinedAt, isNotNull);
    });

    test('회원 모델 생성 및 급수 가중치 검증', () {
      final memberA = Member(
        id: 'm1',
        name: '홍길동',
        gender: Gender.male,
        tier: Tier.a,
      );
      final memberBeginner = Member(
        id: 'm2',
        name: '이초심',
        gender: Gender.female,
        tier: Tier.novice,
      );

      expect(memberA.tierWeight, equals(5));
      expect(memberA.isHighTier, isTrue);
      expect(memberA.isLowTier, isFalse);

      expect(memberBeginner.tierWeight, equals(1));
      expect(memberBeginner.isHighTier, isFalse);
      expect(memberBeginner.isLowTier, isTrue);
    });

    test('회원 Firestore Map 변환 및 복원 검증 (신규 확장 필드 포함)', () {
      final now = DateTime.now();
      final member = Member(
        id: 'm100',
        clubId: 'club_mega',
        name: '박배드',
        gender: Gender.female,
        tier: Tier.b,
        role: MemberRole.manager,
        status: MemberStatus.active,
        isGuest: true,
        feePaid: true,
        homeClub: '에이스클럽',
        phoneNumber: '010-9999-8888',
        joinedAt: now,
        createdAt: now,
      );

      final map = member.toMap();
      expect(map['name'], equals('박배드'));
      expect(map['gender'], equals('F'));
      expect(map['tier'], equals('B'));
      expect(map['role'], equals('manager'));
      expect(map['status'], equals('active'));
      expect(map['isGuest'], isTrue);
      expect(map['feePaid'], isTrue);
      expect(map['homeClub'], equals('에이스클럽'));
      expect(map['phoneNumber'], equals('010-9999-8888'));

      final restored = Member.fromMap(map, id: 'm100');
      expect(restored.id, equals('m100'));
      expect(restored.name, equals('박배드'));
      expect(restored.gender, equals(Gender.female));
      expect(restored.tier, equals(Tier.b));
      expect(restored.role, equals(MemberRole.manager));
      expect(restored.isGuest, isTrue);
      expect(restored.feePaid, isTrue);
      expect(restored.homeClub, equals('에이스클럽'));
      expect(restored.phoneNumber, equals('010-9999-8888'));
    });
  });

  group('GameSession Model Test', () {
    test('세션 모델 계산 프로퍼티 및 직렬화 검증 (회비, 종목, 실시간 출전 명단)', () {
      const session = GameSession(
        id: 'sess_01',
        clubId: 'club_01',
        sessionDate: '2026-09-25',
        courtCount: 6,
        memberFee: 5000,
        guestFee: 10000,
        matchFormat: MatchFormat.league,
        matchType: MatchType.mixedOnly,
        matchMode: MatchMode.tiered,
        attendees: ['m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7', 'm8'],
        activeAttendees: ['m1', 'm2', 'm3', 'm4'],
      );

      expect(session.courtCount, equals(6));
      expect(session.maxSimultaneousPlayers, equals(24)); // 6 * 4
      expect(session.attendeeCount, equals(8));
      expect(session.activeAttendeeCount, equals(4));
      expect(session.hasAttendee('m3'), isTrue);
      expect(session.isAttendeeActive('m3'), isTrue);
      expect(session.isAttendeeActive('m8'), isFalse);

      final map = session.toMap();
      expect(map['matchFormat'], equals('league'));
      expect(map['matchType'], equals('mixedOnly'));
      expect(map['memberFee'], equals(5000));
      expect(map['guestFee'], equals(10000));

      final restored = GameSession.fromMap(map, id: 'sess_01');
      expect(restored.matchFormat, equals(MatchFormat.league));
      expect(restored.matchType, equals(MatchType.mixedOnly));
      expect(restored.activeAttendeeCount, equals(4));
    });

    test('회비 정산 계산 검증 (완납 / 미납 / 면제 별도 집계)', () {
      const session = GameSession(
        id: 's1',
        clubId: 'c1',
        sessionDate: '2026-09-25',
        memberFee: 5000,
        guestFee: 10000,
        attendees: ['m1', 'm2', 'm3', 'g1'],
      );

      final m1 = Member(id: 'm1', name: '완납정회원', isGuest: false, feeStatus: FeeStatus.paid);
      final m2 = Member(id: 'm2', name: '미납정회원', isGuest: false, feeStatus: FeeStatus.unpaid);
      final m3 = Member(id: 'm3', name: '면제운영진', isGuest: false, feeStatus: FeeStatus.exempt);
      final g1 = Member(id: 'g1', name: '완납게스트', isGuest: true, feeStatus: FeeStatus.paid);

      final allMembers = [m1, m2, m3, g1];

      // 면제(m3)는 총 수납 대상 합계에서 제외됨: m1(5000) + m2(5000) + g1(10000) = 20000
      expect(session.calculateTotalFee(allMembers), equals(20000));
      // 완납 합계: m1(5000) + g1(10000) = 15000
      expect(session.calculatePaidFee(allMembers), equals(15000));
      // 인원 집계: 완납 2명, 미납 1명(면제자 제외), 면제 1명
      expect(session.calculatePaidCount(allMembers), equals(2));
      expect(session.calculateUnpaidCount(allMembers), equals(1));
      expect(session.calculateExemptCount(allMembers), equals(1));
    });
  });

  group('MemberFilter & ClubService Multi-filtering Test', () {
    final clubService = ClubService();
    final members = [
      Member(id: '1', name: '홍길동', gender: Gender.male, tier: Tier.a, role: MemberRole.president, isGuest: false),
      Member(id: '2', name: '김영희', gender: Gender.female, tier: Tier.b, role: MemberRole.manager, isGuest: false),
      Member(id: '3', name: '이정회', gender: Gender.female, tier: Tier.c, role: MemberRole.member, isGuest: false),
      Member(id: '4', name: '박철수', gender: Gender.male, tier: Tier.d, role: MemberRole.associate, status: MemberStatus.resting),
    ];

    test('성별 및 급수 다중 필터링', () {
      final filter = const MemberFilter(gender: Gender.female);
      final result = clubService.filterMembers(members, filter);
      expect(result.length, equals(2));
      expect(result.map((m) => m.name), containsAll(['김영희', '이정회']));
    });

    test('회원 등급(운영진 / 정회원 / 준회원) 필터링 검증', () {
      final execResult = clubService.filterMembers(
        members,
        const MemberFilter(grade: MemberGrade.executive),
      );
      expect(execResult.length, equals(2));
      expect(execResult.map((m) => m.name), containsAll(['홍길동', '김영희']));

      final regularResult = clubService.filterMembers(
        members,
        const MemberFilter(grade: MemberGrade.regular),
      );
      expect(regularResult.length, equals(1));
      expect(regularResult.first.name, equals('이정회'));

      final associateResult = clubService.filterMembers(
        members,
        const MemberFilter(grade: MemberGrade.associate),
      );
      expect(associateResult.length, equals(1));
      expect(associateResult.first.name, equals('박철수'));
    });

    test('초성 검색과 필터 복합 연동', () {
      final filter = const MemberFilter(
        searchQuery: 'ㅎㄱㄷ',
        gender: Gender.male,
      );
      final result = clubService.filterMembers(members, filter);
      expect(result.length, equals(1));
      expect(result.first.name, equals('홍길동'));
    });

    test('대량 텍스트 명단 파싱 검증 (등급 및 직책 포함)', () {
      const rawText = '''
        강호동 남 A 회장
        유재석 여 B조 총무
        이광수 초심 준회원
        송중기
      ''';
      final parsed = clubService.parseBatchMembersText(rawText);
      expect(parsed.length, equals(4));
      expect(parsed[0].name, equals('강호동'));
      expect(parsed[0].tier, equals(Tier.a));
      expect(parsed[0].role, equals(MemberRole.president));
      expect(parsed[0].grade, equals(MemberGrade.executive));
      expect(parsed[1].name, equals('유재석'));
      expect(parsed[1].gender, equals(Gender.female));
      expect(parsed[1].tier, equals(Tier.b));
      expect(parsed[1].role, equals(MemberRole.manager));
      expect(parsed[1].grade, equals(MemberGrade.executive));
      expect(parsed[2].name, equals('이광수'));
      expect(parsed[2].role, equals(MemberRole.associate));
      expect(parsed[2].grade, equals(MemberGrade.associate));
      expect(parsed[2].tier, equals(Tier.novice));
      expect(parsed[3].name, equals('송중기'));
      expect(parsed[3].tier, equals(Tier.novice)); // 기본값 자동 부여
      expect(parsed[3].grade, equals(MemberGrade.regular));
    });
  });

  group('GameMatch Model Test', () {
    test('경기 모델 출전 선수 확인 및 승패/점수차 판정', () {
      const match = GameMatch(
        id: 'match_01',
        sessionId: 'sess_01',
        round: 1,
        courtNumber: 3,
        teamA: ['m1', 'm2'],
        teamB: ['m3', 'm4'],
        scoreA: 21,
        scoreB: 18,
        status: MatchStatus.finished,
      );

      expect(match.allPlayerIds, equals(['m1', 'm2', 'm3', 'm4']));
      expect(match.containsPlayer('m1'), isTrue);
      expect(match.containsPlayer('m99'), isFalse);
      expect(match.getTeamForPlayer('m2'), equals('A'));
      expect(match.getTeamForPlayer('m3'), equals('B'));
      expect(match.getTeamForPlayer('m5'), isNull);

      expect(match.isFinished, isTrue);
      expect(match.isTeamAWon, isTrue);
      expect(match.isTeamBWon, isFalse);
      expect(match.isDraw, isFalse);
      expect(match.scoreDiff, equals(3));
    });
  });

  group('ClubService CSV Import & Export Test', () {
    final clubService = ClubService();

    test('표준 CSV 템플릿 헤더 규격 및 UTF-8 BOM 바이트 검증', () {
      final csvStr = clubService.generateStandardTemplateCsvString();
      final bytes = clubService.generateStandardTemplateCsvBytes();

      expect(
        ClubService.standardCsvHeaders,
        equals(['이름', '전화번호', '성별', '급수', '회원구분', '메모']),
      );
      expect(csvStr, contains('이름,전화번호,성별,급수,회원구분,메모'));
      expect(bytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));
      expect(clubService.decodeCsvBytes(bytes), equals(csvStr));
    });

    test('백업 파일명 형식 "메가배드민턴_회원명부_YYYYMMDD.csv" 생성 검증', () {
      final fileName = clubService.buildExportFileName(
        '메가 배드민턴 클럽',
        date: DateTime(2026, 9, 26),
      );
      expect(fileName, equals('메가배드민턴_회원명부_20260926.csv'));
    });

    test('전화번호 정규화 (하이픈 유무 및 엑셀 앞자리 0 누락 대응)', () {
      expect(
        ClubService.normalizePhoneNumber('01012345678', strict: true),
        equals('010-1234-5678'),
      );
      expect(
        ClubService.normalizePhoneNumber('010-9876-5432', strict: true),
        equals('010-9876-5432'),
      );
      expect(
        ClubService.normalizePhoneNumber('1055556666', strict: true),
        equals('010-5555-6666'),
      );
      expect(
        () => ClubService.normalizePhoneNumber('12345', strict: true),
        throwsFormatException,
      );
    });

    test('CSV 파싱: 유효 행, 오류 행(필수값 누락/잘못된 급수), 중복 전화번호 검출', () {
      final existing = <Member>[
        Member(
          id: 'ex_1',
          clubId: 'club_mega',
          name: '안세영',
          gender: Gender.female,
          tier: Tier.a,
          role: MemberRole.president,
          phoneNumber: '010-1111-2222',
        ),
      ];

      const rawCsv = '''이름,전화번호,성별,급수,회원구분,메모
안세영,01011112222,여성,A조,운영진(회장),기존번호중복테스트
박신규,010-3333-4444,남,B,총무,신규총무
이초심,01055556666,여,초심,,회원구분기본값정회원
,010-7777-8888,남,C조,정회원,이름누락오류
최오류,010-8888-9999,남,S급,정회원,잘못된급수오류''';

      final result = clubService.analyzeCsvContent(
        rawCsv,
        clubId: 'club_mega',
        existingClubMembers: existing,
      );

      expect(result.totalDetectedCount, equals(5));
      expect(result.validRows.length, equals(3));
      expect(result.errorRows.length, equals(2));
      expect(result.duplicateRows.length, equals(1));

      // 1행: 중복 전화번호 및 하이픈 정규화 확인
      final row1 = result.validRows[0];
      expect(row1.isDuplicatePhone, isTrue);
      expect(row1.member!.phoneNumber, equals('010-1111-2222'));
      expect(row1.member!.role, equals(MemberRole.president));

      // 2행: 운영진(총무) 및 급수 B 파싱 확인
      final row2 = result.validRows[1];
      expect(row2.isDuplicatePhone, isFalse);
      expect(row2.member!.role, equals(MemberRole.manager));
      expect(row2.member!.tier, equals(Tier.b));
      expect(row2.member!.memo, equals('신규총무'));

      // 3행: 회원구분 빈칸 시 기본값 '정회원' 적용 확인
      final row3 = result.validRows[2];
      expect(row3.member!.role, equals(MemberRole.member));
      expect(row3.member!.tier, equals(Tier.novice));

      // 오류 행 검증 (이름 누락, 잘못된 급수)
      expect(result.errorRows[0].errorSummary, contains('이름'));
      expect(result.errorRows[1].errorSummary, contains('급수'));
    });

    test('전체 회원 목록 CSV 백업 내보내기 및 재파싱 왕복 검증', () {
      final sampleMembers = <Member>[
        Member(
          id: 'm1',
          clubId: 'club_mega',
          name: '홍길동',
          gender: Gender.male,
          tier: Tier.a,
          role: MemberRole.president,
          phoneNumber: '010-1234-5678',
          memo: '창립멤버',
        ),
        Member(
          id: 'm2',
          clubId: 'club_mega',
          name: '김민지',
          gender: Gender.female,
          tier: Tier.novice,
          role: MemberRole.associate,
          phoneNumber: '010-8765-4321',
          memo: '레슨반',
        ),
      ];

      final exportedBytes = clubService.exportMembersToCsvBytes(sampleMembers);
      expect(exportedBytes.sublist(0, 3), equals([0xEF, 0xBB, 0xBF]));

      final decoded = clubService.decodeCsvBytes(exportedBytes);
      final reimported = clubService.analyzeCsvContent(
        decoded,
        clubId: 'club_mega',
        existingClubMembers: const [],
      );

      expect(reimported.validRows.length, equals(2));
      expect(reimported.errorRows, isEmpty);
      expect(reimported.validRows[0].member!.name, equals('홍길동'));
      expect(reimported.validRows[0].member!.memo, equals('창립멤버'));
      expect(reimported.validRows[1].member!.role, equals(MemberRole.associate));
    });
  });

  group('MemberSortBy & AttendanceSortBy Sorting Test', () {
    final clubService = ClubService();
    final sampleMembers = [
      Member(
        id: 'm_c_reg',
        name: '다정회',
        gender: Gender.male,
        tier: Tier.c,
        role: MemberRole.member,
        feeStatus: FeeStatus.paid,
        joinedAt: DateTime(2026, 1, 10),
      ),
      Member(
        id: 'm_a_exec',
        name: '나회장',
        gender: Gender.male,
        tier: Tier.a,
        role: MemberRole.president,
        feeStatus: FeeStatus.exempt,
        joinedAt: DateTime(2026, 1, 5),
      ),
      Member(
        id: 'm_b_assoc',
        name: '가준회',
        gender: Gender.female,
        tier: Tier.b,
        role: MemberRole.associate,
        feeStatus: FeeStatus.unpaid,
        joinedAt: DateTime(2026, 3, 1),
      ),
      Member(
        id: 'm_nov_exec',
        name: '라총무',
        gender: Gender.female,
        tier: Tier.novice,
        role: MemberRole.manager,
        feeStatus: FeeStatus.unpaid,
        joinedAt: DateTime(2026, 2, 15),
      ),
    ];

    test('[회원명부] 4종 정렬 옵션(이름순 기본 / 급수순 / 회원 구분순 / 최근 등록순) 및 필터 연동 검증', () {
      // 1. 기본값: 이름 가나다순 (ㄱ -> ㅎ)
      final defaultSorted = clubService.filterMembers(
        sampleMembers,
        MemberFilter.initial(),
      );
      expect(
        defaultSorted.map((m) => m.name).toList(),
        equals(['가준회', '나회장', '다정회', '라총무']),
      );

      // 2. 급수순 (상위 급수 우선: A -> 초심)
      final tierSorted = clubService.filterMembers(
        sampleMembers,
        const MemberFilter(sortBy: MemberSortBy.tierDesc),
      );
      expect(
        tierSorted.map((m) => m.name).toList(),
        equals(['나회장', '가준회', '다정회', '라총무']),
      );

      // 3. 회원 구분순 (운영진 -> 정회원 -> 준회원)
      final gradeSorted = clubService.filterMembers(
        sampleMembers,
        const MemberFilter(sortBy: MemberSortBy.gradeFirst),
      );
      expect(
        gradeSorted.map((m) => m.name).toList(),
        equals(['나회장', '라총무', '다정회', '가준회']),
      );

      // 4. 최근 등록순 (최신 가입일 우선)
      final recentSorted = clubService.filterMembers(
        sampleMembers,
        const MemberFilter(sortBy: MemberSortBy.recentRegistered),
      );
      expect(
        recentSorted.map((m) => m.name).toList(),
        equals(['가준회', '라총무', '다정회', '나회장']),
      );

      // 5. 성별 필터(여성) 적용 상태에서 회원 구분순 정렬 시 필터 결과 내에서 즉시 재정렬
      final filteredAndSorted = clubService.filterMembers(
        sampleMembers,
        const MemberFilter(
          gender: Gender.female,
          sortBy: MemberSortBy.gradeFirst,
        ),
      );
      expect(
        filteredAndSorted.map((m) => m.name).toList(),
        equals(['라총무', '가준회']),
      );
    });

    test('[출석부] 4종 정렬 옵션(급수순 기본 / 이름순 / 출전 상태순 / 회비 상태순) 검증', () {
      const session = GameSession(
        id: 'sess_sort',
        clubId: 'club_mega',
        sessionDate: '2026-09-26',
        attendees: ['m_c_reg', 'm_a_exec', 'm_b_assoc', 'm_nov_exec'],
        attendeeStatusMap: {
          'm_c_reg': AttendanceStatus.active,
          'm_nov_exec': AttendanceStatus.active,
          'm_b_assoc': AttendanceStatus.resting,
          'm_a_exec': AttendanceStatus.withdrawn,
        },
      );

      // 1. 기본값: 급수순 (A -> 초심)
      final tierSorted = clubService.sortAttendanceMembers(
        sampleMembers,
        session,
        sortBy: AttendanceSortBy.tierDesc,
      );
      expect(
        tierSorted.map((m) => m.name).toList(),
        equals(['나회장', '가준회', '다정회', '라총무']),
      );

      // 2. 이름순 (가나다)
      final nameSorted = clubService.sortAttendanceMembers(
        sampleMembers,
        session,
        sortBy: AttendanceSortBy.nameAsc,
      );
      expect(
        nameSorted.map((m) => m.name).toList(),
        equals(['가준회', '나회장', '다정회', '라총무']),
      );

      // 3. 출전 상태순 (출전 -> 휴식 -> 조퇴, 동상태 시 상위 급수 우선)
      final statusSorted = clubService.sortAttendanceMembers(
        sampleMembers,
        session,
        sortBy: AttendanceSortBy.attendanceStatus,
      );
      expect(
        statusSorted.map((m) => m.name).toList(),
        equals(['다정회', '라총무', '가준회', '나회장']),
      );

      // 4. 회비 상태순 (미납자 최우선 정렬: 미납 -> 완납 -> 면제)
      final feeSorted = clubService.sortAttendanceMembers(
        sampleMembers,
        session,
        sortBy: AttendanceSortBy.feeUnpaidFirst,
      );
      expect(
        feeSorted.map((m) => m.name).toList(),
        equals(['가준회', '라총무', '다정회', '나회장']),
      );
    });
  });

  group('Member Custom Role, Resting Status & Fee Policy Tests', () {
    test('1. [회원 활동 상태] 휴면(휴회) 회원 설정 시 휴면 뱃지 및 휴회 면제 자동 연동 검증', () {
      final restingMember = Member(
        id: 'm_rest_test',
        clubId: 'club_mega',
        name: '아이유',
        gender: Gender.female,
        tier: Tier.c,
        status: MemberStatus.resting,
        restingStartDate: '2026.09.01',
        restingReturnDate: '2026.11.30',
        restingReason: '엘보 부상',
      );

      expect(restingMember.isResting, isTrue);
      expect(restingMember.restingBadgeText, equals('휴면 (복귀 예정 26.11.30)'));
      expect(restingMember.feePolicyBadgeText, equals('휴회 면제'));
      expect(restingMember.feeStatus, equals(FeeStatus.exempt));

      const session = GameSession(
        id: 'sess_rest_fee',
        clubId: 'club_mega',
        sessionDate: '2026-09-26',
        attendees: ['m_rest_test'],
      );
      expect(
        session.getAttendeeFeeStatus(restingMember),
        equals(FeeStatus.exempt),
      );
    });

    test('2. [회원 등급 / 직책] 커스텀 직책(예: 자문위원, 고문, 학생회원) 표시 및 직렬화 검증', () {
      final advisorMember = Member(
        id: 'm_advisor',
        clubId: 'club_mega',
        name: '박지성',
        gender: Gender.male,
        tier: Tier.b,
        role: MemberRole.member,
        customRoleTitle: '자문위원',
      );

      expect(advisorMember.displayRoleLabel, equals('자문위원'));
      final map = advisorMember.toMap();
      final restored = Member.fromMap(map, id: advisorMember.id);
      expect(restored.customRoleTitle, equals('자문위원'));
      expect(restored.displayRoleLabel, equals('자문위원'));
    });

    test('3. [회비 부과 기준] 차등/할인 금액 지정 및 기간 지정 면제 뱃지 표시 검증', () {
      final discountedMember = Member(
        id: 'm_discount',
        clubId: 'club_mega',
        name: '강호동',
        gender: Gender.male,
        tier: Tier.b,
        feePolicy: FeePolicyType.discounted,
        customFeeLabel: '가족할인',
        customFeeAmount: 20000,
      );
      expect(discountedMember.feePolicyBadgeText, equals('가족할인 20,000원'));

      final periodExemptMember = Member(
        id: 'm_exempt_period',
        clubId: 'club_mega',
        name: '김연아',
        gender: Gender.female,
        tier: Tier.a,
        feePolicy: FeePolicyType.exempt,
        isPermanentExempt: false,
        exemptUntilDate: '2026.12.31',
      );
      expect(periodExemptMember.feePolicyBadgeText, equals('면제 (~26.12.31)'));
      expect(periodExemptMember.feeStatus, equals(FeeStatus.exempt));
    });
  });

  group('SessionPreferences Persistence & Reset Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. 직전 세션 설정(경기 방식, 코트 수, 시작 코트 번호, 매칭 모드, 성별 옵션, 파트너 편성 등) 직렬화 및 SharedPreferences 저장/복원 검증', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionPreferencesProvider.notifier);

      await notifier.saveSessionSettings(
        matchFormat: MatchFormat.league,
        courtCount: 4,
        startCourtNumber: 3,
        matchMode: MatchMode.all,
        matchType: MatchType.separate,
        partnerMode: PartnerMode.fixedAll,
        fixedPairs: const [
          ['m_1', 'm_2'],
          ['m_3', 'm_4'],
        ],
      );

      final current = container.read(sessionPreferencesProvider);
      expect(current.hasSavedPreferences, isTrue);
      expect(current.matchFormat, equals(MatchFormat.league));
      expect(current.courtCount, equals(4));
      expect(current.startCourtNumber, equals(3));
      expect(current.matchMode, equals(MatchMode.all));
      expect(current.matchType, equals(MatchType.separate));
      expect(current.partnerMode, equals(PartnerMode.fixedAll));
      expect(current.fixedPairs.length, equals(2));

      // 새 ProviderContainer를 생성해도 SharedPreferences에서 직전 설정을 그대로 불러오는지 확인
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(sessionPreferencesProvider.notifier).loadFromSharedPreferences();

      final loaded = container2.read(sessionPreferencesProvider);
      expect(loaded.hasSavedPreferences, isTrue);
      expect(loaded.matchFormat, equals(MatchFormat.league));
      expect(loaded.courtCount, equals(4));
      expect(loaded.startCourtNumber, equals(3));
      expect(loaded.matchMode, equals(MatchMode.all));
      expect(loaded.matchType, equals(MatchType.separate));
      expect(loaded.partnerMode, equals(PartnerMode.fixedAll));
      expect(loaded.fixedPairs, equals([['m_1', 'm_2'], ['m_3', 'm_4']]));
    });

    test('2. [설정 초기화] 호출 시 기본 권장 설정으로 즉시 리셋 및 SharedPreferences 초기화 검증', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionPreferencesProvider.notifier);
      await notifier.saveSessionSettings(
        matchFormat: MatchFormat.tournament,
        courtCount: 5,
        startCourtNumber: 7,
        matchMode: MatchMode.random,
        matchType: MatchType.mixedOnly,
        partnerMode: PartnerMode.fixedAll,
        fixedPairs: const [
          ['m_1', 'm_2'],
        ],
      );

      expect(container.read(sessionPreferencesProvider).hasSavedPreferences, isTrue);

      await notifier.resetToDefaults();

      final resetState = container.read(sessionPreferencesProvider);
      expect(resetState.hasSavedPreferences, isFalse);
      expect(resetState.isDefaultRecommended(recommendedCourts: 3), isTrue);
      expect(resetState.matchFormat, equals(MatchFormat.regular));
      expect(resetState.startCourtNumber, equals(1));
      expect(resetState.matchMode, equals(MatchMode.tiered));
      expect(resetState.matchType, equals(MatchType.normal));
      expect(resetState.partnerMode, equals(PartnerMode.rotation));
      expect(resetState.fixedPairs, isEmpty);
    });
  });

  group('Real-Time Court Addition & Reduction Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. 코트 추가(+) 시 빈 코트 슬롯 생성, 대기 인원 자동 배정, 다음 라운드 출전 인원 자동 확대 검증', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 12명의 참석자로 2개 코트(8명 출전, 4명 휴식) 세션 시작
      final members = container.read(currentClubMembersProvider).where((m) => !m.isResting).take(12).toList();
      final attendeeIds = members.map((m) => m.id).toList();

      container.read(sessionProvider.notifier).createSession(
            clubId: 'club_mega',
            title: '실시간 코트 증감 테스트',
            memberFee: 5000,
            guestFee: 10000,
            attendeeIds: attendeeIds,
            courtCount: 2,
            startCourtNumber: 1,
            matchMode: MatchMode.all,
          );
      container.read(matchesProvider.notifier).generateMatchesForRound(1);

      expect(container.read(sessionProvider)!.courtCount, equals(2));
      final r1MatchesBefore = container.read(matchesProvider).where((m) => m.round == 1).toList();
      expect(r1MatchesBefore.length, equals(2)); // 1번, 2번 코트 (8명 출전)

      // [+ 코트 추가] 실행 -> 3번 빈 코트 슬롯 추가 (운영 코트 3면)
      final newCourt = container.read(matchesProvider.notifier).addCourtSlot();
      expect(newCourt, equals(3));
      expect(container.read(sessionProvider)!.courtCount, equals(3));

      // 다음 라운드(2R) 대진 자동 생성 시 늘어난 3개 코트에 맞춰 출전 인원이 12명(3코트)으로 자동 확대됨
      container.read(matchesProvider.notifier).generateMatchesForRound(2);
      final r2Matches = container.read(matchesProvider).where((m) => m.round == 2).toList();
      expect(r2Matches.length, equals(3));
      expect(r2Matches.expand((m) => m.allPlayerIds).toSet().length, equals(12));

      // 1R의 빈 3번 코트 슬롯에도 대기 인원 4명 즉시 자동 배정 가능 확인
      final assignedMatch = container.read(matchesProvider.notifier).autoAssignWaitingToEmptyCourt(
            round: 1,
            courtNumber: 3,
          );
      expect(assignedMatch, isNotNull);
      expect(assignedMatch!.courtNumber, equals(3));
      expect(container.read(matchesProvider).where((m) => m.round == 1).length, equals(3));
    });

    test('2. 코트 축소(-) 시 빈 코트 우선 제거, 진행 중 코트 대기 인원 전환, 이전 완료 라운드 기록 보존 검증', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final members = container.read(currentClubMembersProvider).where((m) => !m.isResting).take(12).toList();
      final attendeeIds = members.map((m) => m.id).toList();

      container.read(sessionProvider.notifier).createSession(
            clubId: 'club_mega',
            title: '코트 축소 보존 테스트',
            memberFee: 5000,
            guestFee: 10000,
            attendeeIds: attendeeIds,
            courtCount: 3,
            startCourtNumber: 1,
          );
      container.read(matchesProvider.notifier).generateMatchesForRound(1);

      // 1라운드는 3코트 모두 경기 완료 처리
      final r1Matches = container.read(matchesProvider).where((m) => m.round == 1).toList();
      expect(r1Matches.length, equals(3));
      for (final m in r1Matches) {
        container.read(matchesProvider.notifier).updateScore(
              m.id,
              21,
              15,
              status: MatchStatus.finished,
            );
      }

      // 2라운드 대진 생성 (3코트 배정) 후 코트 1개 추가(+ -> 4면, 4번 코트는 빈 슬롯)
      container.read(matchesProvider.notifier).generateMatchesForRound(2);
      container.read(matchesProvider.notifier).addCourtSlot();
      expect(container.read(sessionProvider)!.courtCount, equals(4));

      // [- 코트 축소] 1차: 배정된 경기가 없는 빈 4번 코트가 우선 제거됨 (3면으로 복귀, 2R 3경기 그대로 유지)
      final removedEmpty = container.read(matchesProvider.notifier).removeEmptyCourtSlot(currentRound: 2);
      expect(removedEmpty, equals(4));
      expect(container.read(sessionProvider)!.courtCount, equals(3));
      expect(container.read(matchesProvider).where((m) => m.round == 2).length, equals(3));

      // [- 코트 축소] 2차: 진행 중인 2R 3번 코트를 닫아 대기 인원으로 전환 후 코트 축소(3면 -> 2면)
      final r2Court3Match = container
          .read(matchesProvider)
          .firstWhere((m) => m.round == 2 && m.courtNumber == 3);
      container.read(matchesProvider.notifier).cancelMatchAndReduceCourt(
            matchId: r2Court3Match.id,
            reduceCourtCount: true,
          );

      expect(container.read(sessionProvider)!.courtCount, equals(2));
      final r2Remaining = container.read(matchesProvider).where((m) => m.round == 2).toList();
      expect(r2Remaining.length, equals(2)); // 2R은 2코트(8명 출전, 4명 대기 전환)

      // 이전 완료된 1라운드의 3코트 경기 기록은 손실 없이 100% 보존됨을 검증
      final r1Preserved = container.read(matchesProvider).where((m) => m.round == 1).toList();
      expect(r1Preserved.length, equals(3));
      expect(r1Preserved.every((m) => m.isFinished && m.scoreA == 21 && m.scoreB == 15), isTrue);
    });
  });
}





