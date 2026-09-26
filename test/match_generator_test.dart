import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockmatch/models/models.dart';
import 'package:cockmatch/services/match_generator_service.dart';

void main() {
  late MatchGeneratorService generator;

  setUp(() {
    // 결정론적 테스트를 위해 시드 고정
    generator = MatchGeneratorService(random: Random(42));
  });

  group('MatchGeneratorService - 선발 및 균등 휴식/출전 테스트', () {
    test('10명 참석, 2코트(8명 출전, 2명 휴식) 후 2라운드에서 휴식자 우선 선발 검증', () {
      final members = List.generate(
        10,
        (i) => Member(
          id: 'p$i',
          name: '선수$i',
          tier: Tier.c,
          gender: Gender.male,
        ),
      );

      const session = GameSession(
        id: 'sess_1',
        clubId: 'club_1',
        sessionDate: '2026-09-25',
        courtCount: 2, // 2코트 = 8명 선발
        matchMode: MatchMode.all,
        attendees: ['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9'],
        activeAttendees: ['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9'],
      );

      // 1라운드 대진 생성
      final round1Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(round1Matches.length, equals(2)); // 2개 코트
      final round1Players = round1Matches.expand((m) => m.allPlayerIds).toSet();
      expect(round1Players.length, equals(8));

      // 1라운드에서 쉬었던 2명 찾기
      final round1Rested = members.map((m) => m.id).where((id) => !round1Players.contains(id)).toList();
      expect(round1Rested.length, equals(2));

      // 2라운드 대진 생성 (1라운드 결과 반영)
      final round2Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: round1Matches,
        targetRound: 2,
      );

      final round2Players = round2Matches.expand((m) => m.allPlayerIds).toSet();
      // 1라운드에서 쉬었던 2명은 2라운드에 반드시 출전해야 함!
      for (final restedId in round1Rested) {
        expect(round2Players.contains(restedId), isTrue,
            reason: '$restedId 선수는 직전 라운드 휴식했으므로 2라운드에 반드시 선발되어야 합니다.');
      }
    });
  });

  group('MatchGeneratorService - 급수 밸런스 (A+D vs B+C) 테스트', () {
    test('A, B, C, D 4인 1조 편성 시 (A+D) vs (B+C)로 최적 균등 편성 검증', () {
      final members = [
        Member(id: 'pA', name: 'A선수', tier: Tier.a), // 5점
        Member(id: 'pB', name: 'B선수', tier: Tier.b), // 4점
        Member(id: 'pC', name: 'C선수', tier: Tier.c), // 3점
        Member(id: 'pD', name: 'D선수', tier: Tier.d), // 2점
      ];

      const session = GameSession(
        id: 'sess_1',
        clubId: 'club_1',
        sessionDate: '2026-09-25',
        courtCount: 1,
        matchMode: MatchMode.all,
        attendees: ['pA', 'pB', 'pC', 'pD'],
        activeAttendees: ['pA', 'pB', 'pC', 'pD'],
      );

      final matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(matches.length, equals(1));
      final match = matches.first;

      // Team A: [pA, pD] (5+2 = 7점), Team B: [pB, pC] (4+3 = 7점)
      final hasBalancedTeamA = (match.teamA.contains('pA') && match.teamA.contains('pD')) ||
          (match.teamA.contains('pB') && match.teamA.contains('pC'));
      final hasBalancedTeamB = (match.teamB.contains('pA') && match.teamB.contains('pD')) ||
          (match.teamB.contains('pB') && match.teamB.contains('pC'));

      expect(hasBalancedTeamA && hasBalancedTeamB, isTrue,
          reason: 'A(5)+D(2)=7 vs B(4)+C(3)=7로 팀 간 급수 차이가 0이어야 합니다.');
    });
  });

  group('MatchGeneratorService - 종목별(혼복, 남복, 여복) 지원 테스트', () {
    test('혼합복식(mixedOnly) 시 팀당 남1 여1 편성 검증', () {
      final members = [
        Member(id: 'm1', name: '남1', gender: Gender.male, tier: Tier.b),
        Member(id: 'm2', name: '남2', gender: Gender.male, tier: Tier.c),
        Member(id: 'f1', name: '여1', gender: Gender.female, tier: Tier.b),
        Member(id: 'f2', name: '여2', gender: Gender.female, tier: Tier.c),
      ];

      const session = GameSession(
        id: 'sess_mixed',
        clubId: 'c1',
        sessionDate: '2026-09-25',
        courtCount: 1,
        matchType: MatchType.mixedOnly,
        attendees: ['m1', 'm2', 'f1', 'f2'],
        activeAttendees: ['m1', 'm2', 'f1', 'f2'],
      );

      final matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(matches.length, equals(1));
      final match = matches.first;

      final memberMap = {for (final m in members) m.id: m};

      // Team A에 남1 여1
      final teamAGenders = match.teamA.map((id) => memberMap[id]!.gender).toList();
      expect(teamAGenders, containsAll([Gender.male, Gender.female]));

      // Team B에 남1 여1
      final teamBGenders = match.teamB.map((id) => memberMap[id]!.gender).toList();
      expect(teamBGenders, containsAll([Gender.male, Gender.female]));
    });
  });

  group('MatchGeneratorService - 실시간 변동(대체 선수, 지각자) 테스트', () {
    test('부상 선수 원클릭 대체 치환 검증', () {
      const match = GameMatch(
        id: 'm1',
        sessionId: 's1',
        round: 1,
        courtNumber: 1,
        teamA: ['p1', 'p2'],
        teamB: ['p3', 'p4'],
      );

      final replaced = generator.replacePlayerInMatch(
        match: match,
        outPlayerId: 'p2',
        substitutePlayerId: 'p_sub',
      );

      expect(replaced.teamA, equals(['p1', 'p_sub']));
      expect(replaced.teamB, equals(['p3', 'p4']));
    });

    test('대기자 중 최적 대체자 추천 검증', () {
      const session = GameSession(
        id: 's1',
        clubId: 'c1',
        sessionDate: '2026-09-25',
        activeAttendees: ['p1', 'p2', 'p3', 'p4', 'wait1', 'wait2'],
      );

      const currentRoundMatches = [
        GameMatch(
          id: 'm1',
          sessionId: 's1',
          round: 1,
          courtNumber: 1,
          teamA: ['p1', 'p2'],
          teamB: ['p3', 'p4'],
        ),
      ];

      // wait1은 과거 1경기 출전, wait2는 0경기 출전
      const pastMatches = [
        GameMatch(
          id: 'past1',
          sessionId: 's1',
          round: 0,
          courtNumber: 1,
          teamA: ['wait1', 'other'],
          teamB: ['other2', 'other3'],
        ),
      ];

      final bestSub = generator.findBestSubstitute(
        session: session,
        currentRoundMatches: currentRoundMatches,
        allMatches: pastMatches,
      );

      // 출전 수가 적은 wait2가 우선 추천되어야 함
      expect(bestSub, equals('wait2'));
    });
  });

  group('MatchGeneratorService - 대회 순위 자동 판정 테스트', () {
    test('다승 -> 득실차 -> 다득점 -> 승자승 순 랭킹 산출 검증', () {
      final members = [
        Member(id: 'p1', name: '김선수'),
        Member(id: 'p2', name: '이선수'),
        Member(id: 'p3', name: '박선수'),
      ];

      final finishedMatches = [
        // 경기 1: p1(Team A: 21) vs p2(Team B: 15) -> p1 1승 (+6), p2 1패 (-6)
        const GameMatch(
          id: 'm1',
          sessionId: 's1',
          round: 1,
          courtNumber: 1,
          teamA: ['p1', 'dummyA'],
          teamB: ['p2', 'dummyB'],
          scoreA: 21,
          scoreB: 15,
          status: MatchStatus.finished,
        ),
        // 경기 2: p1(Team A: 21) vs p3(Team B: 10) -> p1 2승 (+17)
        const GameMatch(
          id: 'm2',
          sessionId: 's1',
          round: 2,
          courtNumber: 1,
          teamA: ['p1', 'dummyA'],
          teamB: ['p3', 'dummyC'],
          scoreA: 21,
          scoreB: 10,
          status: MatchStatus.finished,
        ),
        // 경기 3: p2(Team A: 21) vs p3(Team B: 19) -> p2 1승1패 (-4), p3 2패 (-13)
        const GameMatch(
          id: 'm3',
          sessionId: 's1',
          round: 3,
          courtNumber: 1,
          teamA: ['p2', 'dummyB'],
          teamB: ['p3', 'dummyC'],
          scoreA: 21,
          scoreB: 19,
          status: MatchStatus.finished,
        ),
      ];

      final rankings = generator.calculateRankings(
        finishedMatches: finishedMatches,
        members: members,
      );

      // p1: 2승 0패 (1위)
      // p2: 1승 1패 (2위)
      // p3: 0승 2패 (3위)
      expect(rankings[0].memberId, equals('p1'));
      expect(rankings[0].rank, equals(1));
      expect(rankings[0].wins, equals(2));
      expect(rankings[0].pointDifference, equals(17));

      expect(rankings[1].memberId, equals('p2'));
      expect(rankings[1].rank, equals(2));
      expect(rankings[1].wins, equals(1));
      expect(rankings[1].pointDifference, equals(-4));

      expect(rankings[2].memberId, equals('p3'));
      expect(rankings[2].rank, equals(3));
      expect(rankings[2].wins, equals(0));
      expect(rankings[2].pointDifference, equals(-13));
    });
  });

  group('MatchGeneratorService - 다중 라운드 급수합 밸런스 최우선 강제 테스트', () {
    test('8명 소규모 인원 4개 라운드 연속 생성 시 모든 코트의 팀 급수합 차이가 1점 이내로 유지되는지 검증', () {
      final members = [
        Member(id: 'a1', name: 'A1', tier: Tier.a), // 5
        Member(id: 'a2', name: 'A2', tier: Tier.a), // 5
        Member(id: 'b1', name: 'B1', tier: Tier.b), // 4
        Member(id: 'b2', name: 'B2', tier: Tier.b), // 4
        Member(id: 'c1', name: 'C1', tier: Tier.c), // 3
        Member(id: 'c2', name: 'C2', tier: Tier.c), // 3
        Member(id: 'd1', name: 'D1', tier: Tier.d), // 2
        Member(id: 'd2', name: 'D2', tier: Tier.d), // 2
      ];
      final memberMap = {for (final m in members) m.id: m};

      final session = GameSession(
        id: 'sess_balance',
        clubId: 'c1',
        sessionDate: '2026-09-25',
        courtCount: 2,
        matchMode: MatchMode.all,
        attendees: members.map((m) => m.id).toList(),
        activeAttendees: members.map((m) => m.id).toList(),
      );

      final allMatches = <GameMatch>[];

      for (int r = 1; r <= 4; r++) {
        final roundMatches = generator.generateRoundMatches(
          session: session,
          allMembers: members,
          existingMatches: allMatches,
          targetRound: r,
        );
        expect(roundMatches.length, equals(2));

        for (final m in roundMatches) {
          final weightA = m.teamA.fold<int>(0, (s, id) => s + memberMap[id]!.tierWeight);
          final weightB = m.teamB.fold<int>(0, (s, id) => s + memberMap[id]!.tierWeight);
          final diff = (weightA - weightB).abs();

          // A+A(10) vs D+D(4) 또는 A+A(10) vs B+B(8) 같은 편중 없이 항상 0~1점 차이 유지
          expect(
            diff,
            lessThanOrEqualTo(1),
            reason: '$r라운드 ${m.courtNumber}코트 급수합 불균형 발생 (A:$weightA vs B:$weightB)',
          );
        }

        allMatches.addAll(roundMatches);
      }
    });
  });

  group('MatchGeneratorService - 토너먼트 모드 승자 진출 및 고정 페어 유지 테스트', () {
    test('16명 4코트 토너먼트: 1R 페어 고정 유지 및 승자 진출(4코트 -> 2코트 -> 1코트 결승) 검증', () {
      final members = List.generate(
        16,
        (i) => Member(id: 'p$i', name: '선수$i', tier: Tier.c),
      );

      const session = GameSession(
        id: 'sess_tourney_16',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 4,
        matchFormat: MatchFormat.tournament,
        attendees: [
          'p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7',
          'p8', 'p9', 'p10', 'p11', 'p12', 'p13', 'p14', 'p15'
        ],
        activeAttendees: [
          'p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7',
          'p8', 'p9', 'p10', 'p11', 'p12', 'p13', 'p14', 'p15'
        ],
      );

      // 1. 1라운드 생성: 4코트 (16명 전원 출전)
      final round1Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );
      expect(round1Matches.length, equals(4));

      // 1라운드에서 각 코트의 Team A가 승리한 것으로 결과 기록 (4개 승자 페어 = 8명 진출)
      final finishedRound1 = round1Matches.map((m) {
        return m.copyWith(
          scoreA: 21,
          scoreB: 15,
          status: MatchStatus.finished,
        );
      }).toList();

      final r1WinningPairs = finishedRound1.map((m) => Set<String>.from(m.teamA)).toList();
      final r1LosingPlayers = finishedRound1.expand((m) => m.teamB).toSet();

      // 2. 2라운드 생성: 4개 승자 페어 -> 2코트 매칭
      final round2Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: finishedRound1,
        targetRound: 2,
      );

      expect(round2Matches.length, equals(2), reason: '승자 4팀(8명)이므로 2코트가 배정되어야 합니다.');

      // 2라운드 검증:
      // (1) 탈락한 패배 선수(10명)는 아무도 2라운드에 포함되지 않아야 함!
      for (final m in round2Matches) {
        for (final p in m.allPlayerIds) {
          expect(r1LosingPlayers.contains(p), isFalse,
              reason: '1라운드 패배 선수 $p 는 2라운드에 진출할 수 없습니다 (단두대 탈락).');
        }
      }

      // (2) 1라운드에서 결성된 2인 복식 페어가 2라운드에서도 분리되지 않고 고정 유지되는지 검증!
      for (final m in round2Matches) {
        final pairA = Set<String>.from(m.teamA);
        final pairB = Set<String>.from(m.teamB);

        final pairAMatchesR1 = r1WinningPairs.any((orig) => orig.containsAll(pairA) && pairA.containsAll(orig));
        final pairBMatchesR1 = r1WinningPairs.any((orig) => orig.containsAll(pairB) && pairB.containsAll(orig));

        expect(pairAMatchesR1, isTrue, reason: '2라운드 Team A 페어는 1라운드 결성 페어와 정확히 일치해야 합니다.');
        expect(pairBMatchesR1, isTrue, reason: '2라운드 Team B 페어는 1라운드 결성 페어와 정확히 일치해야 합니다.');
      }

      // 2라운드 결과 기록: 각 코트의 Team A 승리 (2개 승자 페어 진출)
      final finishedRound2 = round2Matches.map((m) {
        return m.copyWith(
          scoreA: 21,
          scoreB: 18,
          status: MatchStatus.finished,
        );
      }).toList();

      // 3. 3라운드 (결승전) 생성: 2개 승자 페어 -> 1코트 매칭
      final round3Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [...finishedRound1, ...finishedRound2],
        targetRound: 3,
      );

      expect(round3Matches.length, equals(1), reason: '최종 결승전은 1코트여야 합니다.');
      final finalMatch = round3Matches.first;
      expect(finalMatch.allPlayerIds.length, equals(4));

      // 4. 결승전 완료 후 4라운드 요청 시 매치 없음 (대회 종료)
      final finishedRound3 = [
        finalMatch.copyWith(scoreA: 21, scoreB: 19, status: MatchStatus.finished),
      ];

      final round4Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [...finishedRound1, ...finishedRound2, ...finishedRound3],
        targetRound: 4,
      );
      expect(round4Matches, isEmpty, reason: '우승 페어가 확정되었으므로 다음 라운드 매치는 없습니다.');
    });

    test('20명 5코트 토너먼트: 홀수 승자 페어(5팀) 시 2코트(4팀) 매칭 + 1팀 부전승 보존 검증', () {
      final members = List.generate(
        20,
        (i) => Member(id: 'p$i', name: '선수$i', tier: Tier.c),
      );

      const session = GameSession(
        id: 'sess_tourney_20',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 5,
        matchFormat: MatchFormat.tournament,
        attendees: [
          'p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9',
          'p10', 'p11', 'p12', 'p13', 'p14', 'p15', 'p16', 'p17', 'p18', 'p19'
        ],
        activeAttendees: [
          'p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9',
          'p10', 'p11', 'p12', 'p13', 'p14', 'p15', 'p16', 'p17', 'p18', 'p19'
        ],
      );

      final round1Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );
      expect(round1Matches.length, equals(5));

      // 1R 5코트 모두 Team A 승리 (5개 승자 페어 = 10명)
      final finishedRound1 = round1Matches.map((m) {
        return m.copyWith(scoreA: 21, scoreB: 12, status: MatchStatus.finished);
      }).toList();

      // 2R 생성: 5개 팀 중 4개 팀이 2코트에 출전, 1개 팀은 부전승(Bye)으로 대기
      final round2Matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: finishedRound1,
        targetRound: 2,
      );

      expect(round2Matches.length, equals(2), reason: '5개 승자 팀 중 4팀(2코트) 배정');
      final r2Players = round2Matches.expand((m) => m.allPlayerIds).toSet();
      expect(r2Players.length, equals(8));

      // 패배한 10명은 2R에 단 한 명도 출전하지 않음
      final r1Losers = finishedRound1.expand((m) => m.teamB).toSet();
      for (final p in r2Players) {
        expect(r1Losers.contains(p), isFalse);
      }
    });
  });

  group('MatchGeneratorService - 4대 성별 매칭 모드 및 시작 코트 번호 테스트', () {
    test('남복/여복 분리(separate): 남성 코트와 여성 코트가 철저히 분리되는지 검증', () {
      final members = [
        // 남성 8명
        ...List.generate(8, (i) => Member(id: 'm$i', name: '남$i', gender: Gender.male, tier: Tier.b)),
        // 여성 4명
        ...List.generate(4, (i) => Member(id: 'f$i', name: '여$i', gender: Gender.female, tier: Tier.c)),
      ];
      final memberMap = {for (final m in members) m.id: m};

      final session = GameSession(
        id: 'sess_separate',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 3,
        matchType: MatchType.separate,
        startCourtNumber: 5, // 시작 코트 번호 5번
        attendees: members.map((m) => m.id).toList(),
        activeAttendees: members.map((m) => m.id).toList(),
      );

      final matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(matches.length, equals(3));
      // 시작 코트 번호 5번 검증: 5, 6, 7번 코트
      final courtNumbers = matches.map((m) => m.courtNumber).toList();
      expect(courtNumbers, equals([5, 6, 7]));

      int maleCourts = 0;
      int femaleCourts = 0;

      for (final m in matches) {
        final genders = m.allPlayerIds.map((id) => memberMap[id]!.gender).toSet();
        if (genders.length == 1) {
          if (genders.first == Gender.male) maleCourts++;
          if (genders.first == Gender.female) femaleCourts++;
        }
      }

      // 8명 남성 = 2코트, 4명 여성 = 1코트
      expect(maleCourts, equals(2), reason: '남복 분리 코트가 2개여야 합니다.');
      expect(femaleCourts, equals(1), reason: '여복 분리 코트가 1개여야 합니다.');
    });

    test('혼합복식(mixedOnly): 모든 코트의 각 팀이 무조건 남1 + 여1로 편성되는지 검증', () {
      final members = [
        ...List.generate(4, (i) => Member(id: 'm$i', name: '남$i', gender: Gender.male, tier: Tier.b)),
        ...List.generate(4, (i) => Member(id: 'f$i', name: '여$i', gender: Gender.female, tier: Tier.c)),
      ];
      final memberMap = {for (final m in members) m.id: m};

      final session = GameSession(
        id: 'sess_mixed_8',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 2,
        matchType: MatchType.mixedOnly,
        startCourtNumber: 3,
        attendees: members.map((m) => m.id).toList(),
        activeAttendees: members.map((m) => m.id).toList(),
      );

      final matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(matches.length, equals(2));
      expect(matches.map((m) => m.courtNumber).toList(), equals([3, 4]));

      for (final m in matches) {
        final teamAGenders = m.teamA.map((id) => memberMap[id]!.gender).toList();
        final teamBGenders = m.teamB.map((id) => memberMap[id]!.gender).toList();

        expect(teamAGenders, containsAll([Gender.male, Gender.female]));
        expect(teamBGenders, containsAll([Gender.male, Gender.female]));
      }
    });

    test('남복/여복 우선(genderPriority): 순수 남복/여복 우선 배정 후 잔여 인원 혼복 편성 검증', () {
      final members = [
        ...List.generate(6, (i) => Member(id: 'm$i', name: '남$i', gender: Gender.male, tier: Tier.b)),
        ...List.generate(6, (i) => Member(id: 'f$i', name: '여$i', gender: Gender.female, tier: Tier.c)),
      ];
      final memberMap = {for (final m in members) m.id: m};

      final session = GameSession(
        id: 'sess_gender_pri',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 3,
        matchType: MatchType.genderPriority,
        startCourtNumber: 1,
        attendees: members.map((m) => m.id).toList(),
        activeAttendees: members.map((m) => m.id).toList(),
      );

      final matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(matches.length, equals(3));

      // 6남 6여 -> 1코트 순수 남복(4인), 1코트 순수 여복(4인), 1코트 남2여2 혼복(4인)
      int pureMaleCourts = 0;
      int pureFemaleCourts = 0;
      int mixedCourts = 0;

      for (final m in matches) {
        final genders = m.allPlayerIds.map((id) => memberMap[id]!.gender).toList();
        final mCount = genders.where((g) => g == Gender.male).length;
        final fCount = genders.where((g) => g == Gender.female).length;

        if (mCount == 4) {
          pureMaleCourts++;
        } else if (fCount == 4) {
          pureFemaleCourts++;
        } else if (mCount == 2 && fCount == 2) {
          mixedCourts++;
        }
      }

      expect(pureMaleCourts, equals(1), reason: '순수 남복 코트가 1개 편성되어야 합니다.');
      expect(pureFemaleCourts, equals(1), reason: '순수 여복 코트가 1개 편성되어야 합니다.');
      expect(mixedCourts, equals(1), reason: '잔여 인원으로 혼복 코트가 1개 편성되어야 합니다.');
    });
  });

  group('MatchGeneratorService - 웹뷰어 경기 방식별 종합 순위 & 리포트 산출 테스트', () {
    test('정기 로테이션(개인 기준): 승률(1순위) -> 득실차(2순위) -> 다승(3순위) -> 다득점(4순위, 승자승 제외) 검증', () {
      final members = [
        Member(id: 'p1', name: '김백퍼', tier: Tier.a), // 1전 1승 (승률 100%, 득실 +3)
        Member(id: 'p2', name: '이칠십', tier: Tier.b), // 3전 2승 1패 (승률 66.7%, 득실 +10)
        Member(id: 'p3', name: '박백퍼고득실', tier: Tier.a), // 2전 2승 (승률 100%, 득실 +9)
        Member(id: 'p4', name: '최백퍼다승', tier: Tier.b), // 1전 1승 (승률 100%, 득실 +9, 1승)
      ];

      final finishedMatches = [
        // p1 & p3 승리 (+3)
        const GameMatch(
          id: 'm1',
          sessionId: 's_reg',
          round: 1,
          courtNumber: 1,
          teamA: ['p1', 'p3'],
          teamB: ['p2', 'x1'],
          scoreA: 21,
          scoreB: 18,
          status: MatchStatus.finished,
        ),
        // p3 & p2 승리 (+6) -> p3는 2전 2승(승률 100%, 득실 +9)
        const GameMatch(
          id: 'm2',
          sessionId: 's_reg',
          round: 2,
          courtNumber: 1,
          teamA: ['p3', 'p2'],
          teamB: ['x1', 'x2'],
          scoreA: 21,
          scoreB: 15,
          status: MatchStatus.finished,
        ),
        // p4 & p2 승리 (+9) -> p4는 1전 1승(승률 100%, 득실 +9, 1승), p2는 3전 2승 1패(승률 66.7%)
        const GameMatch(
          id: 'm3',
          sessionId: 's_reg',
          round: 3,
          courtNumber: 1,
          teamA: ['p4', 'p2'],
          teamB: ['x3', 'x4'],
          scoreA: 21,
          scoreB: 12,
          status: MatchStatus.finished,
        ),
      ];

      final rankings = generator.calculateRegularRotationRankings(
        finishedMatches: finishedMatches,
        members: members,
        onlyPlayedPlayers: true,
      );

      // p3: 승률 100%, 득실 +9, 2승 (1위)
      // p4: 승률 100%, 득실 +9, 1승 (2위 - 다승에서 p3가 앞섬)
      // p1: 승률 100%, 득실 +3, 1승 (3위 - 득실차에서 p3/p4가 앞섬)
      // p2: 승률 66.7%, 2승 1패 (4위 - 다승이 2승이어도 승률 1순위 규칙에 따라 100% 그룹보다 하위)
      expect(rankings[0].memberId, equals('p3'));
      expect(rankings[1].memberId, equals('p4'));
      expect(rankings[2].memberId, equals('p1'));
      expect(rankings[3].memberId, equals('p2'));
    });

    test('풀리그전(팀 기준): 다승(1순위) -> 승자승(2순위) -> 득실차(3순위) -> 다득점(4순위) 검증', () {
      final members = [
        Member(id: 'a1', name: 'A1', tier: Tier.a),
        Member(id: 'a2', name: 'A2', tier: Tier.b),
        Member(id: 'b1', name: 'B1', tier: Tier.a),
        Member(id: 'b2', name: 'B2', tier: Tier.b),
        Member(id: 'c1', name: 'C1', tier: Tier.c),
        Member(id: 'c2', name: 'C2', tier: Tier.c),
      ];

      // Team A(a1,a2)와 Team B(b1,b2)가 모두 1승 1패이지만,
      // 맞대결에서 Team A가 Team B를 이겼고(21:19), 득실차는 Team B가 더 높은 상황 테스트
      final finishedMatches = [
        // 맞대결: Team A 승 (21:19, 득실 +2 vs -2)
        const GameMatch(
          id: 'lg1',
          sessionId: 's_lg',
          round: 1,
          courtNumber: 1,
          teamA: ['a1', 'a2'],
          teamB: ['b1', 'b2'],
          scoreA: 21,
          scoreB: 19,
          status: MatchStatus.finished,
        ),
        // Team B가 Team C에 대승 (21:5, 득실 +16) -> Team B 총 득실 +14 (1승 1패)
        const GameMatch(
          id: 'lg2',
          sessionId: 's_lg',
          round: 2,
          courtNumber: 1,
          teamA: ['b1', 'b2'],
          teamB: ['c1', 'c2'],
          scoreA: 21,
          scoreB: 5,
          status: MatchStatus.finished,
        ),
        // Team C가 Team A에 승리 (21:18) -> Team A 총 득실 -1 (1승 1패)
        const GameMatch(
          id: 'lg3',
          sessionId: 's_lg',
          round: 3,
          courtNumber: 1,
          teamA: ['c1', 'c2'],
          teamB: ['a1', 'a2'],
          scoreA: 21,
          scoreB: 18,
          status: MatchStatus.finished,
        ),
      ];

      // Team A와 Team B만 놓고 비교하기 위해 lg1 + 추가 경기로 1승씩 맞춘 케이스 검증
      final twoTeamMatches = [
        finishedMatches[0], // Team A beats Team B (21:19)
        finishedMatches[1], // Team B beats Team C (21:5) -> Team B: 1W 1L, diff +14
        const GameMatch(
          id: 'lg_extra',
          sessionId: 's_lg',
          round: 3,
          courtNumber: 1,
          teamA: ['a1', 'a2'],
          teamB: ['d1', 'd2'],
          scoreA: 15,
          scoreB: 21,
          status: MatchStatus.finished,
        ), // Team A: 1W 1L, diff -4
      ];

      final teamRankings = generator.calculateLeagueTeamRankings(
        finishedMatches: twoTeamMatches,
        members: members,
      );

      // Team A(1승1패, 득실 -4)와 Team B(1승1패, 득실 +14) 중
      // 2순위 '승자승'에 의해 맞대결 승자인 Team A가 Team B보다 상위여야 함!
      final rankA = teamRankings.firstWhere((t) => t.teamKey == 'a1_a2').rank;
      final rankB = teamRankings.firstWhere((t) => t.teamKey == 'b1_b2').rank;
      expect(rankA, lessThan(rankB), reason: '풀리그전은 다승 동률 시 득실차보다 승자승(2순위)이 우선이어야 합니다.');
    });

    test('토너먼트: 우승, 준우승, 4강 진출 단계별 최종 트리 산출 검증', () {
      final members = [
        Member(id: 'm1', name: '우승1'),
        Member(id: 'm2', name: '우승2'),
        Member(id: 'm3', name: '준우승1'),
        Member(id: 'm4', name: '준우승2'),
        Member(id: 'm5', name: '사강A1'),
        Member(id: 'm6', name: '사강A2'),
        Member(id: 'm7', name: '사강B1'),
        Member(id: 'm8', name: '사강B2'),
      ];

      const matches = [
        GameMatch(
          id: 't_r1_c1',
          sessionId: 's_t',
          round: 1,
          courtNumber: 1,
          teamA: ['m1', 'm2'],
          teamB: ['m5', 'm6'],
          scoreA: 25,
          scoreB: 18,
          status: MatchStatus.finished,
        ),
        GameMatch(
          id: 't_r1_c2',
          sessionId: 's_t',
          round: 1,
          courtNumber: 2,
          teamA: ['m3', 'm4'],
          teamB: ['m7', 'm8'],
          scoreA: 25,
          scoreB: 20,
          status: MatchStatus.finished,
        ),
        GameMatch(
          id: 't_r2_c1',
          sessionId: 's_t',
          round: 2,
          courtNumber: 1,
          teamA: ['m1', 'm2'],
          teamB: ['m3', 'm4'],
          scoreA: 25,
          scoreB: 22,
          status: MatchStatus.finished,
        ),
      ];

      final tree = generator.buildTournamentResultTree(
        matches: matches,
        members: members,
      );

      expect(tree.champion, isNotNull);
      expect(tree.champion!.teamName, equals('우승1 & 우승2'));
      expect(tree.runnerUp, isNotNull);
      expect(tree.runnerUp!.teamName, equals('준우승1 & 준우승2'));
      expect(tree.semiFinalists.length, equals(2));
      expect(tree.stagePlacements.length, equals(3)); // 우승, 준우승, 4강
    });
  });

  group('MatchGeneratorService - 대진표 코트 번호 변경 및 스왑(Swap) 테스트', () {
    test('빈 코트 번호로 변경 시: 해당 매치가 새 코트 번호로 이동 (swapped: false)', () {
      const matches = [
        GameMatch(
          id: 'm1',
          sessionId: 's1',
          round: 1,
          courtNumber: 1,
          teamA: ['p1', 'p2'],
          teamB: ['p3', 'p4'],
        ),
        GameMatch(
          id: 'm2',
          sessionId: 's1',
          round: 1,
          courtNumber: 2,
          teamA: ['p5', 'p6'],
          teamB: ['p7', 'p8'],
        ),
      ];

      final result = generator.changeOrSwapCourt(
        matches: matches,
        matchId: 'm1',
        targetCourtNumber: 4, // 빈 코트(4번)로 이동
      );

      expect(result.swapped, isFalse);
      expect(result.oldCourt, equals(1));
      expect(result.newCourt, equals(4));

      final movedMatch = result.updatedMatches.firstWhere((m) => m.id == 'm1');
      final otherMatch = result.updatedMatches.firstWhere((m) => m.id == 'm2');
      expect(movedMatch.courtNumber, equals(4));
      expect(otherMatch.courtNumber, equals(2));
    });

    test('이미 다른 매치가 배정 중인 코트 선택 시: 두 코트의 경기 배치가 서로 맞바꿈(Swap) 처리 (swapped: true)', () {
      const matches = [
        GameMatch(
          id: 'm1',
          sessionId: 's1',
          round: 1,
          courtNumber: 1,
          teamA: ['p1', 'p2'],
          teamB: ['p3', 'p4'],
        ),
        GameMatch(
          id: 'm2',
          sessionId: 's1',
          round: 1,
          courtNumber: 3,
          teamA: ['p5', 'p6'],
          teamB: ['p7', 'p8'],
        ),
      ];

      final result = generator.changeOrSwapCourt(
        matches: matches,
        matchId: 'm1',
        targetCourtNumber: 3, // 이미 m2가 배정된 3번 코트 선택
      );

      expect(result.swapped, isTrue);
      expect(result.oldCourt, equals(1));
      expect(result.newCourt, equals(3));

      final match1 = result.updatedMatches.firstWhere((m) => m.id == 'm1');
      final match2 = result.updatedMatches.firstWhere((m) => m.id == 'm2');
      expect(match1.courtNumber, equals(3));
      expect(match2.courtNumber, equals(1));
    });
  });

  group('MatchGeneratorService - 3단 매칭 모드(분리/밸런스/랜덤) 및 고정 파트너 편성 테스트', () {
    test('급수 무관 (랜덤 매칭 - MatchMode.random): 급수 점수 제약 없이 무작위 셔플 대진 생성 검증', () {
      final members = [
        Member(id: 'r1', name: '선수1', tier: Tier.a),
        Member(id: 'r2', name: '선수2', tier: Tier.a),
        Member(id: 'r3', name: '선수3', tier: Tier.b),
        Member(id: 'r4', name: '선수4', tier: Tier.c),
        Member(id: 'r5', name: '선수5', tier: Tier.d),
        Member(id: 'r6', name: '선수6', tier: Tier.novice),
        Member(id: 'r7', name: '선수7', tier: Tier.b),
        Member(id: 'r8', name: '선수8', tier: Tier.d),
      ];

      final session = GameSession(
        id: 'sess_random',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 2,
        matchMode: MatchMode.random,
        attendees: members.map((m) => m.id).toList(),
        activeAttendees: members.map((m) => m.id).toList(),
      );

      final matches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: [],
        targetRound: 1,
      );

      expect(matches.length, equals(2));
      final allPlayed = matches.expand((m) => m.allPlayerIds).toSet();
      expect(allPlayed.length, equals(8));
    });

    test('전원 고정 페어(PartnerMode.fixedAll) + 급수별 자동 짝짓기: 다중 라운드 진행 시 모든 페어 불변 유지 검증', () {
      final members = [
        Member(id: 'f1', name: 'A1', tier: Tier.a),
        Member(id: 'f2', name: 'A2', tier: Tier.a),
        Member(id: 'f3', name: 'B1', tier: Tier.b),
        Member(id: 'f4', name: 'B2', tier: Tier.b),
        Member(id: 'f5', name: 'C1', tier: Tier.c),
        Member(id: 'f6', name: 'C2', tier: Tier.c),
        Member(id: 'f7', name: 'D1', tier: Tier.d),
        Member(id: 'f8', name: 'D2', tier: Tier.d),
      ];

      final autoPairs = generator.autoPairByTier(
        members: members,
        matchMode: MatchMode.tiered,
      );
      expect(autoPairs.length, equals(4));

      for (final mode in [MatchMode.tiered, MatchMode.all, MatchMode.random]) {
        final session = GameSession(
          id: 'sess_fixed_all_${mode.code}',
          clubId: 'c1',
          sessionDate: '2026-09-26',
          courtCount: 2,
          matchMode: mode,
          partnerMode: PartnerMode.fixedAll,
          fixedPairs: autoPairs,
          attendees: members.map((m) => m.id).toList(),
          activeAttendees: members.map((m) => m.id).toList(),
        );

        final r1 = generator.generateRoundMatches(
          session: session,
          allMembers: members,
          existingMatches: [],
          targetRound: 1,
        );
        final r2 = generator.generateRoundMatches(
          session: session,
          allMembers: members,
          existingMatches: r1,
          targetRound: 2,
        );

        // 1R 및 2R의 모든 코트에서 고정된 4개 페어가 절대 찢어지지 않고 항상 한 팀(teamA 또는 teamB)으로 출전해야 함
        final expectedPairKeys = autoPairs
            .map((p) => p[0].compareTo(p[1]) < 0 ? '${p[0]}:${p[1]}' : '${p[1]}:${p[0]}')
            .toSet();

        for (final m in [...r1, ...r2]) {
          final keyA = m.teamA[0].compareTo(m.teamA[1]) < 0
              ? '${m.teamA[0]}:${m.teamA[1]}'
              : '${m.teamA[1]}:${m.teamA[0]}';
          final keyB = m.teamB[0].compareTo(m.teamB[1]) < 0
              ? '${m.teamB[0]}:${m.teamB[1]}'
              : '${m.teamB[1]}:${m.teamB[0]}';
          expect(expectedPairKeys.contains(keyA), isTrue);
          expect(expectedPairKeys.contains(keyB), isTrue);
        }
      }
    });

    test('개인별 로테이션(PartnerMode.rotation) + 특정 고정 페어 1조 지정: 지정 페어는 고정되고 나머지는 로테이션 검증', () {
      final members = List.generate(
        8,
        (i) => Member(
          id: 'p${i + 1}',
          name: '선수${i + 1}',
          tier: i < 2 ? Tier.a : i < 4 ? Tier.b : i < 6 ? Tier.c : Tier.d,
        ),
      );

      // p1과 p8만 대회 준비 특정 고정 페어로 지정, 나머지 6명(p2~p7)은 개인 로테이션
      final session = GameSession(
        id: 'sess_partial_fixed',
        clubId: 'c1',
        sessionDate: '2026-09-26',
        courtCount: 2,
        matchMode: MatchMode.all,
        partnerMode: PartnerMode.rotation,
        fixedPairs: const [
          ['p1', 'p8'],
        ],
        attendees: members.map((m) => m.id).toList(),
        activeAttendees: members.map((m) => m.id).toList(),
      );

      final history = <GameMatch>[];
      for (int round = 1; round <= 3; round++) {
        final roundMatches = generator.generateRoundMatches(
          session: session,
          allMembers: members,
          existingMatches: history,
          targetRound: round,
        );
        expect(roundMatches.length, equals(2));

        // p1이 속한 매치를 찾아 p1과 p8이 항상 같은 팀(teamA 또는 teamB)에 있는지 확인
        final matchWithP1 = roundMatches.firstWhere((m) => m.allPlayerIds.contains('p1'));
        final isTogetherInA =
            matchWithP1.teamA.contains('p1') && matchWithP1.teamA.contains('p8');
        final isTogetherInB =
            matchWithP1.teamB.contains('p1') && matchWithP1.teamB.contains('p8');
        expect(
          isTogetherInA || isTogetherInB,
          isTrue,
          reason: '$round라운드에서도 특정 고정 페어(p1, p8)는 반드시 한 팀으로 묶여야 합니다.',
        );

        history.addAll(roundMatches);
      }
    });
  });
}



