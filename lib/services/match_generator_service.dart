import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// 배드민턴 스마트 대진표 자동 생성 및 랭킹 산출 서비스
class MatchGeneratorService {
  static const _uuid = Uuid();
  final Random _random;

  MatchGeneratorService({Random? random}) : _random = random ?? Random();

  /// 지정 라운드의 경기 목록을 자동 생성합니다.
  /// - session: 현재 게임 세션
  /// - allMembers: 전체 회원 목록
  /// - existingMatches: 이전 라운드 경기 이력 (출전 횟수, 파트너/상대 중복 방지용)
  /// - targetRound: 생성할 라운드 번호
  /// - priorityMemberIds: 우선 출전 대상자 (예: 지각자 등)
  List<GameMatch> generateRoundMatches({
    required GameSession session,
    required List<Member> allMembers,
    required List<GameMatch> existingMatches,
    required int targetRound,
    Set<String> priorityMemberIds = const {},
    int? customCourtCount,
  }) {
    final courtCount = customCourtCount ?? session.courtCount;
    if (courtCount <= 0) return [];
    final startCourtNumber = session.startCourtNumber;

    // [규칙 1 & 2 & 3] 토너먼트 모드 (2라운드 이상): 승자 진출(탈락제) 및 2인 복식 고정 페어 유지
    if (session.matchFormat == MatchFormat.tournament && targetRound > 1) {
      return _generateTournamentNextRoundMatches(
        session: session,
        allMembers: allMembers,
        existingMatches: existingMatches,
        targetRound: targetRound,
        startCourtNumber: startCourtNumber,
        maxCourtCount: courtCount,
      );
    }

    // 1. 실시간 출전 가능한 참석자 회원 목록 필터링 (휴식/조퇴 제외, 신규 게스트 포함)
    final memberMap = {for (final m in allMembers) m.id: m};
    final activeAttendees = session.activeAttendees
        .where((id) => memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList();

    if (activeAttendees.length < 4) return [];

    // 2. 종목 유형(MatchType)에 따른 필터링 (남복, 여복, 혼복, 일반)
    final eligibleMembers = _filterByMatchType(activeAttendees, session.matchType);
    if (eligibleMembers.length < 4) return [];

    // 3. 누적 출전 횟수 및 직전 라운드 출전 여부 분석
    final playCounts = _calculatePlayCounts(existingMatches);
    final previousRoundPlayerIds = _getPreviousRoundPlayerIds(existingMatches, targetRound - 1);
    final partnerHistory = _buildPartnerHistory(existingMatches);
    final opponentHistory = _buildOpponentHistory(existingMatches);

    // 3-1. 고정 파트너(전원 고정 페어 또는 특정 고정 페어) 설정 확인 및 대진 생성 연동
    final eligibleMap = {for (final m in eligibleMembers) m.id: m};
    final activeFixedPairs = <List<Member>>[];
    final pairedMemberIds = <String>{};

    for (final rawPair in session.fixedPairs) {
      if (rawPair.length == 2) {
        final id1 = rawPair[0];
        final id2 = rawPair[1];
        if (id1 != id2 &&
            eligibleMap.containsKey(id1) &&
            eligibleMap.containsKey(id2) &&
            !pairedMemberIds.contains(id1) &&
            !pairedMemberIds.contains(id2)) {
          activeFixedPairs.add([eligibleMap[id1]!, eligibleMap[id2]!]);
          pairedMemberIds.add(id1);
          pairedMemberIds.add(id2);
        }
      }
    }

    // [전원 고정 페어] 모드에서 아직 짝지어진 페어가 없거나 미배정 인원이 남아있는 경우 자동 2인 짝짓기 보완
    if (session.partnerMode == PartnerMode.fixedAll) {
      final remainingUnpaired = eligibleMembers
          .where((m) => !pairedMemberIds.contains(m.id))
          .toList();
      if (remainingUnpaired.length >= 2) {
        final autoPairs = autoPairByTier(
          members: remainingUnpaired,
          matchMode: session.matchMode,
          matchType: session.matchType,
        );
        for (final pairIds in autoPairs) {
          if (pairIds.length == 2 &&
              eligibleMap.containsKey(pairIds[0]) &&
              eligibleMap.containsKey(pairIds[1])) {
            activeFixedPairs.add([eligibleMap[pairIds[0]]!, eligibleMap[pairIds[1]]!]);
            pairedMemberIds.add(pairIds[0]);
            pairedMemberIds.add(pairIds[1]);
          }
        }
      }
    }

    // 고정된 페어가 1팀 이상 존재하거나 [전원 고정 페어] 모드일 때는 고정 팀 유지 알고리즘으로 생성
    if (activeFixedPairs.isNotEmpty || session.partnerMode == PartnerMode.fixedAll) {
      final soloMembers = eligibleMembers
          .where((m) => !pairedMemberIds.contains(m.id))
          .toList();

      return _generateMatchesWithFixedPairs(
        session: session,
        fixedTeams: activeFixedPairs,
        soloMembers: soloMembers,
        targetRound: targetRound,
        courtCount: courtCount,
        startCourtNumber: startCourtNumber,
        playCounts: playCounts,
        previousRoundPlayerIds: previousRoundPlayerIds,
        priorityMemberIds: priorityMemberIds,
        partnerHistory: partnerHistory,
        opponentHistory: opponentHistory,
      );
    }

    // 4. 성별 매칭 규칙에 따른 정밀 인원 선출 (개인별 로테이션 기본 경로)
    List<Member> selectedMembers;

    if (session.matchType == MatchType.mixedOnly) {
      // [혼합복식]: 각 코트당 남2, 여2 필수
      final allMales = eligibleMembers.where((m) => m.gender == Gender.male).toList();
      final allFemales = eligibleMembers.where((m) => m.gender == Gender.female).toList();
      final maxCourts = min(courtCount, min(allMales.length ~/ 2, allFemales.length ~/ 2));
      if (maxCourts <= 0) return [];

      final selMales = _selectPlayers(
        candidates: allMales,
        targetCount: maxCourts * 2,
        playCounts: playCounts,
        previousRoundPlayerIds: previousRoundPlayerIds,
        priorityMemberIds: priorityMemberIds,
      );
      final selFemales = _selectPlayers(
        candidates: allFemales,
        targetCount: maxCourts * 2,
        playCounts: playCounts,
        previousRoundPlayerIds: previousRoundPlayerIds,
        priorityMemberIds: priorityMemberIds,
      );
      selectedMembers = [...selMales, ...selFemales];
    } else if (session.matchType == MatchType.separate) {
      // [남복/여복 분리]: 남성 코트(4명 단위)와 여성 코트(4명 단위)로 분리 선발
      final allMales = eligibleMembers.where((m) => m.gender == Gender.male).toList();
      final allFemales = eligibleMembers.where((m) => m.gender == Gender.female).toList();
      final maxMaleCourts = allMales.length ~/ 4;
      final maxFemaleCourts = allFemales.length ~/ 4;

      int maleCourts = 0;
      int femaleCourts = 0;
      while ((maleCourts + femaleCourts) < courtCount &&
          (maleCourts < maxMaleCourts || femaleCourts < maxFemaleCourts)) {
        if (maleCourts < maxMaleCourts && (femaleCourts >= maxFemaleCourts || maleCourts <= femaleCourts)) {
          maleCourts++;
        } else if (femaleCourts < maxFemaleCourts) {
          femaleCourts++;
        } else {
          break;
        }
      }

      final selMales = _selectPlayers(
        candidates: allMales,
        targetCount: maleCourts * 4,
        playCounts: playCounts,
        previousRoundPlayerIds: previousRoundPlayerIds,
        priorityMemberIds: priorityMemberIds,
      );
      final selFemales = _selectPlayers(
        candidates: allFemales,
        targetCount: femaleCourts * 4,
        playCounts: playCounts,
        previousRoundPlayerIds: previousRoundPlayerIds,
        priorityMemberIds: priorityMemberIds,
      );
      selectedMembers = [...selMales, ...selFemales];
    } else {
      // [전체 혼합 / 남복·여복 우선]: 가용 코트 수에 맞춰 균등 선발
      final maxPlayersNeeded = courtCount * 4;
      selectedMembers = _selectPlayers(
        candidates: eligibleMembers,
        targetCount: min(eligibleMembers.length - (eligibleMembers.length % 4), maxPlayersNeeded),
        playCounts: playCounts,
        previousRoundPlayerIds: previousRoundPlayerIds,
        priorityMemberIds: priorityMemberIds,
      );
    }

    if (selectedMembers.length < 4) return [];

    // 6. 대진 모드(급수별 분리 / 통합 밸런스 / 급수 무관 랜덤) 및 성별 규칙에 따른 4인 조 편성
    final groupsOfFour = _createFourPlayerGroups(
      selectedMembers,
      session.matchMode,
      session.matchType,
      partnerHistory,
      opponentHistory,
    );

    // 7. 각 4인 조 내에서 팀(2 vs 2) 최적 밸런스(또는 랜덤) 매칭 및 경기 생성
    final generatedMatches = <GameMatch>[];
    int courtNumber = startCourtNumber;

    for (final group in groupsOfFour) {
      if (generatedMatches.length >= courtCount) break;

      final balancedMatch = _balanceMatch(
        sessionId: session.id,
        round: targetRound,
        courtNumber: courtNumber,
        fourPlayers: group,
        matchType: session.matchType,
        matchMode: session.matchMode,
        partnerHistory: partnerHistory,
        opponentHistory: opponentHistory,
      );

      generatedMatches.add(balancedMatch);
      courtNumber++;
    }

    return generatedMatches;
  }

  /// [급수별 자동 짝짓기] 출전 인원 전체를 2명씩 복식 페어로 자동 편성
  /// - matchMode == MatchMode.tiered (급수별 분리): 동일/인접 급수끼리 묶음 (A+A, B+B, C+C...)
  /// - matchMode == MatchMode.all (통합 밸런스): 상위+하위 실력 균형 폴딩 묶음 (A+D, B+C...)
  /// - matchMode == MatchMode.random (급수 무관 랜덤): 무작위 셔플 2인 묶음
  List<List<String>> autoPairByTier({
    required List<Member> members,
    MatchMode matchMode = MatchMode.tiered,
    MatchType matchType = MatchType.normal,
  }) {
    if (members.length < 2) return [];

    List<List<String>> pairGroup(List<Member> group) {
      if (group.length < 2) return [];
      final list = List<Member>.from(group);
      if (matchMode == MatchMode.random) {
        list.shuffle(_random);
      } else {
        list.sort((a, b) {
          final cmp = b.tierWeight.compareTo(a.tierWeight);
          if (cmp != 0) return cmp;
          return a.name.compareTo(b.name);
        });
      }

      final pairs = <List<String>>[];
      final pairCount = list.length ~/ 2;

      if (matchMode == MatchMode.all) {
        // 통합 밸런스: 최상위 + 최하위 폴딩 매칭 (A+D, B+C)
        final evenSlice = list.take(pairCount * 2).toList();
        for (int i = 0; i < pairCount; i++) {
          pairs.add([evenSlice[i].id, evenSlice[evenSlice.length - 1 - i].id]);
        }
      } else {
        // 급수별 분리(인접 급수끼리) 또는 랜덤
        for (int i = 0; i < pairCount; i++) {
          pairs.add([list[i * 2].id, list[i * 2 + 1].id]);
        }
      }
      return pairs;
    }

    if (matchType == MatchType.mixedOnly) {
      final males = members.where((m) => m.gender == Gender.male).toList();
      final females = members.where((m) => m.gender == Gender.female).toList();
      if (matchMode == MatchMode.random) {
        males.shuffle(_random);
        females.shuffle(_random);
      } else {
        males.sort((a, b) => b.tierWeight.compareTo(a.tierWeight));
        females.sort((a, b) => b.tierWeight.compareTo(a.tierWeight));
      }

      final mixedCount = min(males.length, females.length);
      final pairs = <List<String>>[];
      for (int i = 0; i < mixedCount; i++) {
        final fIdx = matchMode == MatchMode.all ? (mixedCount - 1 - i) : i;
        pairs.add([males[i].id, females[fIdx].id]);
      }

      final rem = <Member>[
        ...males.skip(mixedCount),
        ...females.skip(mixedCount),
      ];
      pairs.addAll(pairGroup(rem));
      return pairs;
    }

    if (matchType == MatchType.separate || matchType == MatchType.genderPriority) {
      final males = members.where((m) => m.gender == Gender.male).toList();
      final females = members.where((m) => m.gender == Gender.female).toList();
      final pairs = <List<String>>[
        ...pairGroup(males),
        ...pairGroup(females),
      ];
      final pairedSet = pairs.expand((p) => p).toSet();
      final rem = members.where((m) => !pairedSet.contains(m.id)).toList();
      pairs.addAll(pairGroup(rem));
      return pairs;
    }

    return pairGroup(members);
  }

  /// [고정 파트너(복식팀) 통합 대진 생성]
  /// - 고정된 페어는 절대 해체되지 않고 항상 한 팀(TEAM A 또는 TEAM B)으로 묶여 출전/휴식
  /// - 개인 로테이션 내 특정 고정 페어(1~2조)가 섞여 있는 경우에도 고정 페어는 유지하고 나머지 인원은 로테이션
  /// - 3가지 매칭 모드(tiered / all / random)와 유기적으로 결합하여 코트 배정
  List<GameMatch> _generateMatchesWithFixedPairs({
    required GameSession session,
    required List<List<Member>> fixedTeams,
    required List<Member> soloMembers,
    required int targetRound,
    required int courtCount,
    required int startCourtNumber,
    required Map<String, int> playCounts,
    required Set<String> previousRoundPlayerIds,
    required Set<String> priorityMemberIds,
    required Map<String, int> partnerHistory,
    required Map<String, int> opponentHistory,
  }) {
    // 1. 개인 로테이션 대상자(soloMembers)를 출전 공정성 순으로 정렬
    final sortedSolos = _selectPlayers(
      candidates: soloMembers,
      targetCount: soloMembers.length,
      playCounts: playCounts,
      previousRoundPlayerIds: previousRoundPlayerIds,
      priorityMemberIds: priorityMemberIds,
    );

    // 2. 고정 팀 단위(2인)와 솔로 2인 청크 단위를 합쳐 이번 라운드에 출전할 팀 슬롯(코트당 2팀) 선발
    final totalAvailableTeams = fixedTeams.length + (sortedSolos.length ~/ 2);
    final actualCourts = min(courtCount, totalAvailableTeams ~/ 2);
    if (actualCourts <= 0) return [];
    final targetTeamCount = actualCourts * 2;

    // 각 후보 유닛: (isFixed, members[2], priority, avgPlayCount, playedPrev)
    final units = <({
      bool isFixed,
      List<Member> members,
      int priority,
      double avgPlayCount,
      int playedPrev,
    })>[];

    for (final pair in fixedTeams) {
      final m1 = pair[0];
      final m2 = pair[1];
      final pri = (priorityMemberIds.contains(m1.id) || priorityMemberIds.contains(m2.id)) ? 0 : 1;
      final avgCnt = ((playCounts[m1.id] ?? 0) + (playCounts[m2.id] ?? 0)) / 2.0;
      final prev = (previousRoundPlayerIds.contains(m1.id) || previousRoundPlayerIds.contains(m2.id)) ? 1 : 0;
      units.add((
        isFixed: true,
        members: [m1, m2],
        priority: pri,
        avgPlayCount: avgCnt,
        playedPrev: prev,
      ));
    }

    for (int i = 0; i + 1 < sortedSolos.length; i += 2) {
      final m1 = sortedSolos[i];
      final m2 = sortedSolos[i + 1];
      final pri = (priorityMemberIds.contains(m1.id) || priorityMemberIds.contains(m2.id)) ? 0 : 1;
      final avgCnt = ((playCounts[m1.id] ?? 0) + (playCounts[m2.id] ?? 0)) / 2.0;
      final prev = (previousRoundPlayerIds.contains(m1.id) || previousRoundPlayerIds.contains(m2.id)) ? 1 : 0;
      units.add((
        isFixed: false,
        members: [m1, m2],
        priority: pri,
        avgPlayCount: avgCnt,
        playedPrev: prev,
      ));
    }

    units.sort((a, b) {
      if (a.priority != b.priority) return a.priority.compareTo(b.priority);
      final cntCmp = a.avgPlayCount.compareTo(b.avgPlayCount);
      if (cntCmp != 0) return cntCmp;
      if (a.playedPrev != b.playedPrev) return a.playedPrev.compareTo(b.playedPrev);
      return _random.nextBool() ? 1 : -1;
    });

    final selectedUnits = units.take(targetTeamCount).toList();
    final selectedFixedTeams = selectedUnits
        .where((u) => u.isFixed)
        .map((u) => u.members)
        .toList();
    final selectedSolos = selectedUnits
        .where((u) => !u.isFixed)
        .expand((u) => u.members)
        .toList();

    // 3. 솔로 출전 인원들을 이번 라운드용 2인 팀으로 편성 (파트너 중복 최소화 + 매칭 모드 반영)
    final formedSoloTeams = _formSoloTeamsForRound(
      solos: selectedSolos,
      matchMode: session.matchMode,
      matchType: session.matchType,
      partnerHistory: partnerHistory,
    );

    final allRoundTeams = <List<Member>>[
      ...selectedFixedTeams,
      ...formedSoloTeams,
    ];

    if (allRoundTeams.length < 2) return [];

    // 4. 확정된 2인 팀들을 매칭 모드(급수별 분리 / 통합 밸런스 / 급수 무관 랜덤)에 맞춰 코트에 대진 배정
    return _pairTeamsIntoCourtMatches(
      sessionId: session.id,
      round: targetRound,
      startCourtNumber: startCourtNumber,
      maxCourts: actualCourts,
      teams: allRoundTeams,
      matchMode: session.matchMode,
      matchType: session.matchType,
      opponentHistory: opponentHistory,
    );
  }

  /// 솔로 참가자들을 라운드별 최적 파트너로 2인 1조 편성 (고정 페어와 함께 코트에 들어갈 팀 구성)
  List<List<Member>> _formSoloTeamsForRound({
    required List<Member> solos,
    required MatchMode matchMode,
    required MatchType matchType,
    required Map<String, int> partnerHistory,
  }) {
    if (solos.length < 2) return [];

    final pool = List<Member>.from(solos)..shuffle(_random);
    if (matchMode != MatchMode.random) {
      pool.sort((a, b) => b.tierWeight.compareTo(a.tierWeight));
    }

    final avgTeamWeight = pool.fold<int>(0, (sum, m) => sum + m.tierWeight) / (pool.length / 2.0);
    final used = <String>{};
    final teams = <List<Member>>[];

    for (int i = 0; i < pool.length; i++) {
      final p1 = pool[i];
      if (used.contains(p1.id)) continue;

      Member? bestPartner;
      double bestCost = double.infinity;

      for (int j = i + 1; j < pool.length; j++) {
        final p2 = pool[j];
        if (used.contains(p2.id)) continue;

        double cost = 0;
        final pairKey = _pairKey(p1.id, p2.id);
        // 파트너 중복 회피 최우선
        cost += (partnerHistory[pairKey] ?? 0) * 1500.0;

        // 성별 규칙 반영
        if (matchType == MatchType.mixedOnly) {
          if (p1.gender == p2.gender) cost += 5000.0;
        } else if (matchType == MatchType.separate || matchType == MatchType.genderPriority) {
          if (p1.gender != p2.gender) cost += 3000.0;
        }

        // 급수 매칭 모드 반영
        if (matchMode == MatchMode.tiered) {
          // 급수별 분리: 비슷한 급수끼리 파트너 유도
          cost += (p1.tierWeight - p2.tierWeight).abs() * 120.0;
          if (p1.isHighTier != p2.isHighTier) cost += 500.0;
        } else if (matchMode == MatchMode.all) {
          // 통합 밸런스: 두 선수 합산 급수가 평균 팀 급수에 가깝도록(A+D, B+C) 유도
          cost += ((p1.tierWeight + p2.tierWeight) - avgTeamWeight).abs() * 200.0;
        }

        if (cost < bestCost) {
          bestCost = cost;
          bestPartner = p2;
        }
      }

      if (bestPartner != null) {
        used.add(p1.id);
        used.add(bestPartner.id);
        teams.add([p1, bestPartner]);
      }
    }

    return teams;
  }

  /// 2인 팀(고정 페어 + 라운드 솔로 페어)들을 매칭 모드에 따라 코트별(Team A vs Team B)로 매칭
  List<GameMatch> _pairTeamsIntoCourtMatches({
    required String sessionId,
    required int round,
    required int startCourtNumber,
    required int maxCourts,
    required List<List<Member>> teams,
    required MatchMode matchMode,
    required MatchType matchType,
    required Map<String, int> opponentHistory,
  }) {
    final workingTeams = List<List<Member>>.from(teams)..shuffle(_random);

    if (matchMode == MatchMode.tiered) {
      // 급수별 분리 매칭: 팀 합산 급수 내림차순 정렬 (상위부 팀끼리 상위 코트, 하위부 팀끼리 하위 코트)
      workingTeams.sort((a, b) {
        final wA = a[0].tierWeight + a[1].tierWeight;
        final wB = b[0].tierWeight + b[1].tierWeight;
        return wB.compareTo(wA);
      });
    } else if (matchMode == MatchMode.all) {
      // 통합 밸런스 매칭: 팀 합산 급수 순으로 정렬 후 실력차가 가장 적은 팀과 대결
      workingTeams.sort((a, b) {
        final wA = a[0].tierWeight + a[1].tierWeight;
        final wB = b[0].tierWeight + b[1].tierWeight;
        return wB.compareTo(wA);
      });
    }

    final usedIndices = <int>{};
    final matches = <GameMatch>[];
    int courtNumber = startCourtNumber;

    for (int i = 0; i < workingTeams.length; i++) {
      if (usedIndices.contains(i)) continue;
      if (matches.length >= maxCourts) break;

      final teamA = workingTeams[i];
      int bestOpponentIdx = -1;
      double bestCost = double.infinity;

      for (int j = i + 1; j < workingTeams.length; j++) {
        if (usedIndices.contains(j)) continue;
        final teamB = workingTeams[j];

        // 상대팀 중복 횟수 집계
        int oppRepeat = 0;
        for (final a in teamA) {
          for (final b in teamB) {
            oppRepeat += (opponentHistory[_pairKey(a.id, b.id)] ?? 0);
          }
        }

        final weightA = teamA[0].tierWeight + teamA[1].tierWeight;
        final weightB = teamB[0].tierWeight + teamB[1].tierWeight;
        final tierDiff = (weightA - weightB).abs();

        double cost = 0;
        if (matchMode == MatchMode.random) {
          // 급수 무관(랜덤): 급수차 무시, 상대 중복만 가볍게 회피
          cost = oppRepeat * 10.0 + _random.nextDouble();
        } else if (matchMode == MatchMode.tiered) {
          // 급수별 분리: 상위부/하위부 경계 유지 + 인접 급수 팀끼리 매칭 + 상대 중복 회피
          final aHighCount = teamA.where((m) => m.isHighTier).length;
          final bHighCount = teamB.where((m) => m.isHighTier).length;
          if ((aHighCount >= 1) != (bHighCount >= 1)) {
            cost += 5000.0;
          }
          cost += tierDiff * 400.0 + oppRepeat * 300.0;
        } else {
          // 통합 밸런스(MatchMode.all): 양 팀 급수합 차이 최소화 최우선 + 상대 중복 회피
          cost += tierDiff * 5000.0 + oppRepeat * 250.0;
        }

        if (matchType == MatchType.separate || matchType == MatchType.genderPriority) {
          final gendersA = teamA.map((m) => m.gender).toSet();
          final gendersB = teamB.map((m) => m.gender).toSet();
          if (gendersA.length == 1 && gendersB.length == 1 && gendersA.first != gendersB.first) {
            cost += 8000.0;
          }
        }

        if (cost < bestCost) {
          bestCost = cost;
          bestOpponentIdx = j;
        }
      }

      if (bestOpponentIdx != -1) {
        usedIndices.add(i);
        usedIndices.add(bestOpponentIdx);
        final teamB = workingTeams[bestOpponentIdx];
        matches.add(
          GameMatch(
            id: _uuid.v4(),
            sessionId: sessionId,
            round: round,
            courtNumber: courtNumber,
            teamA: [teamA[0].id, teamA[1].id],
            teamB: [teamB[0].id, teamB[1].id],
            status: MatchStatus.pending,
          ),
        );
        courtNumber++;
      }
    }

    return matches;
  }

  /// [토너먼트 전용] 승자 진출(단두대 탈락제) 및 2인 복식 고정 팀 유지 다음 라운드 대진 생성
  List<GameMatch> _generateTournamentNextRoundMatches({
    required GameSession session,
    required List<Member> allMembers,
    required List<GameMatch> existingMatches,
    required int targetRound,
    required int startCourtNumber,
    required int maxCourtCount,
  }) {
    // 1. 직전 라운드(targetRound - 1) 경기 목록 추출 (코트 순 정렬)
    final prevRoundMatches = existingMatches
        .where((m) => m.round == targetRound - 1)
        .toList()
      ..sort((a, b) => a.courtNumber.compareTo(b.courtNumber));

    if (prevRoundMatches.isEmpty) return [];

    // 2. 과거 모든 라운드에서 탈락한(패배한) 2인 페어 키 집합 추출
    final eliminatedPairKeys = <String>{};
    for (final m in existingMatches.where((m) => m.round < targetRound)) {
      if (m.isFinished || m.scoreA != m.scoreB) {
        final losingTeam = m.scoreA > m.scoreB ? m.teamB : m.teamA;
        if (losingTeam.length == 2) {
          eliminatedPairKeys.add(_pairKey(losingTeam[0], losingTeam[1]));
        }
      }
    }

    // 3. 직전 라운드 경기에서 승리한 페어(2인 고정 팀) 추출
    final winningPairs = <List<String>>[];
    for (final m in prevRoundMatches) {
      List<String> winner;
      if (m.isTeamAWon) {
        winner = m.teamA;
      } else if (m.isTeamBWon) {
        winner = m.teamB;
      } else if (m.scoreA > m.scoreB) {
        winner = m.teamA;
      } else if (m.scoreB > m.scoreA) {
        winner = m.teamB;
      } else {
        // 미완료/동점 상태로 강제 생성 시 기본 팀A
        winner = m.teamA;
      }
      if (winner.length == 2) {
        winningPairs.add(winner);
      }
    }

    // 4. 1라운드에 출전했던 모든 초기 2인 페어 중, 이전 라운드 부전승(Bye)으로 쉬었으나 탈락하지 않은 페어 탐색
    final round1Matches = existingMatches.where((m) => m.round == 1).toList();
    final allInitialPairs = <List<String>>[];
    for (final m in round1Matches) {
      if (m.teamA.length == 2) allInitialPairs.add(m.teamA);
      if (m.teamB.length == 2) allInitialPairs.add(m.teamB);
    }

    final prevRoundPlayerIds = prevRoundMatches.expand((m) => m.allPlayerIds).toSet();
    final byePairs = <List<String>>[];
    for (final pair in allInitialPairs) {
      final key = _pairKey(pair[0], pair[1]);
      if (!eliminatedPairKeys.contains(key)) {
        if (!prevRoundPlayerIds.contains(pair[0]) && !prevRoundPlayerIds.contains(pair[1])) {
          byePairs.add(pair);
        }
      }
    }

    // 부전승이었던 페어를 우선 배치하고 직전 라운드 승자 페어를 결합
    final survivingPairs = [...byePairs, ...winningPairs];
    if (survivingPairs.length < 2) return [];

    // 5. 살아남은 승자 페어들끼리만 맞붙도록 2팀당 1개 코트 생성 (2인 페어 불변 유지!)
    final generatedMatches = <GameMatch>[];
    int courtNumber = startCourtNumber;
    int pairIdx = 0;

    while (pairIdx + 1 < survivingPairs.length && generatedMatches.length < maxCourtCount) {
      final teamA = survivingPairs[pairIdx];
      final teamB = survivingPairs[pairIdx + 1];

      generatedMatches.add(
        GameMatch(
          id: 'tournament_r${targetRound}_c${courtNumber}_${_uuid.v4().substring(0, 8)}',
          sessionId: session.id,
          round: targetRound,
          courtNumber: courtNumber,
          teamA: List.from(teamA),
          teamB: List.from(teamB),
          status: MatchStatus.playing,
        ),
      );

      courtNumber++;
      pairIdx += 2;
    }

    return generatedMatches;
  }

  /// 종목 유형별 후보 선수 필터링
  List<Member> _filterByMatchType(List<Member> members, MatchType matchType) {
    switch (matchType) {
      case MatchType.menOnly:
        return members.where((m) => m.gender == Gender.male).toList();
      case MatchType.womenOnly:
        return members.where((m) => m.gender == Gender.female).toList();
      case MatchType.separate:
      case MatchType.mixedOnly:
      case MatchType.genderPriority:
      case MatchType.normal:
        return members;
    }
  }

  /// 선수별 누적 출전 경기 수 집계
  Map<String, int> _calculatePlayCounts(List<GameMatch> matches) {
    final counts = <String, int>{};
    for (final match in matches) {
      for (final playerId in match.allPlayerIds) {
        counts[playerId] = (counts[playerId] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// 직전 라운드에 출전한 선수 ID 집합 추출
  Set<String> _getPreviousRoundPlayerIds(List<GameMatch> matches, int prevRound) {
    if (prevRound <= 0) return {};
    final players = <String>{};
    for (final match in matches.where((m) => m.round == prevRound)) {
      players.addAll(match.allPlayerIds);
    }
    return players;
  }

  /// 공평한 출전 및 휴식을 위한 선수 선발
  List<Member> _selectPlayers({
    required List<Member> candidates,
    required int targetCount,
    required Map<String, int> playCounts,
    required Set<String> previousRoundPlayerIds,
    required Set<String> priorityMemberIds,
  }) {
    final sorted = List<Member>.from(candidates);

    sorted.sort((a, b) {
      // 1. 지각자 등 우선순위 지정 회원 최우선 선발
      final aPriority = priorityMemberIds.contains(a.id) ? 0 : 1;
      final bPriority = priorityMemberIds.contains(b.id) ? 0 : 1;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);

      // 2. 누적 출전 수가 적은 사람 최우선 선발
      final aCount = playCounts[a.id] ?? 0;
      final bCount = playCounts[b.id] ?? 0;
      if (aCount != bCount) return aCount.compareTo(bCount);

      // 3. 직전 라운드에 쉬었던 사람 우선 (연속 출전 방지)
      final aPrev = previousRoundPlayerIds.contains(a.id) ? 1 : 0;
      final bPrev = previousRoundPlayerIds.contains(b.id) ? 1 : 0;
      if (aPrev != bPrev) return aPrev.compareTo(bPrev);

      // 4. 동률 시 랜덤
      return _random.nextBool() ? 1 : -1;
    });

    return sorted.take(targetCount).toList();
  }

  /// 4인 1조 그룹 편성 (급수별 분리 / 통합 밸런스 / 급수 무관 랜덤 + 성별 매칭 옵션 반영)
  List<List<Member>> _createFourPlayerGroups(
    List<Member> selected,
    MatchMode matchMode,
    MatchType matchType,
    Map<String, int> partnerHistory,
    Map<String, int> opponentHistory,
  ) {
    // 1. 혼합복식 전용 (한 팀당 남1 + 여1)
    if (matchType == MatchType.mixedOnly) {
      return _createMixedFourPlayerGroups(selected, matchMode: matchMode);
    }

    // 2. 남복 / 여복 분리 (남성은 남복 코트, 여성은 여복 코트로 분리 배정)
    if (matchType == MatchType.separate) {
      final males = selected.where((m) => m.gender == Gender.male).toList();
      final females = selected.where((m) => m.gender == Gender.female).toList();

      final maleGroups = _createGroupsByTierMode(males, matchMode, partnerHistory, opponentHistory);
      final femaleGroups = _createGroupsByTierMode(females, matchMode, partnerHistory, opponentHistory);
      return [...maleGroups, ...femaleGroups];
    }

    // 3. 남복/여복 우선 (남복/여복 최우선 배정, 성비 불균형 잔여 인원만 혼복 혼용)
    if (matchType == MatchType.genderPriority) {
      final males = selected.where((m) => m.gender == Gender.male).toList();
      final females = selected.where((m) => m.gender == Gender.female).toList();

      final pureMaleCount = (males.length ~/ 4) * 4;
      final pureFemaleCount = (females.length ~/ 4) * 4;

      final pureMales = males.take(pureMaleCount).toList();
      final pureFemales = females.take(pureFemaleCount).toList();

      final maleGroups = _createGroupsByTierMode(pureMales, matchMode, partnerHistory, opponentHistory);
      final femaleGroups = _createGroupsByTierMode(pureFemales, matchMode, partnerHistory, opponentHistory);

      final remMales = males.skip(pureMaleCount).toList();
      final remFemales = females.skip(pureFemaleCount).toList();
      final remCombined = [...remMales, ...remFemales];

      final mixedGroups = <List<Member>>[];
      if (remCombined.length >= 4) {
        if (remMales.length == 2 && remFemales.length == 2) {
          mixedGroups.add([remMales[0], remMales[1], remFemales[0], remFemales[1]]);
        } else {
          mixedGroups.addAll(_createGroupsByTierMode(remCombined, matchMode, partnerHistory, opponentHistory));
        }
      }

      return [...maleGroups, ...femaleGroups, ...mixedGroups];
    }

    // 4. 전체 혼합 (기본값: 성별 무관 실력/로테이션 위주 자유 매칭)
    return _createGroupsByTierMode(selected, matchMode, partnerHistory, opponentHistory);
  }

  /// 급수 모드(급수별 분리 / 통합 밸런스 / 급수 무관 랜덤)에 따른 4인 조 생성 헬퍼
  List<List<Member>> _createGroupsByTierMode(
    List<Member> members,
    MatchMode matchMode,
    Map<String, int> partnerHistory,
    Map<String, int> opponentHistory,
  ) {
    if (members.length < 4) return [];

    // [급수 무관 (랜덤 매칭)]: 급수 점수를 고려하지 않고 완전 무작위 셔플 후 4인 1조 편성
    if (matchMode == MatchMode.random) {
      final shuffled = List<Member>.from(members)..shuffle(_random);
      final numCourts = shuffled.length ~/ 4;
      return List.generate(
        numCourts,
        (c) => shuffled.sublist(c * 4, (c + 1) * 4),
      );
    }

    if (matchMode == MatchMode.tiered) {
      final highTier = members.where((m) => m.isHighTier).toList();
      final lowTier = members.where((m) => m.isLowTier).toList();

      final highGroups = _distributeIntoBalancedGroups(highTier, partnerHistory, opponentHistory);
      final lowGroups = _distributeIntoBalancedGroups(lowTier, partnerHistory, opponentHistory);

      final highRem = highTier.length % 4;
      final lowRem = lowTier.length % 4;
      if (highRem + lowRem >= 4) {
        final merged = [
          ...highTier.sublist(highTier.length - highRem),
          ...lowTier.sublist(lowTier.length - lowRem),
        ];
        final remGroups = _distributeIntoBalancedGroups(merged, partnerHistory, opponentHistory);
        return [...highGroups, ...lowGroups, ...remGroups];
      }

      return [...highGroups, ...lowGroups];
    } else {
      return _distributeIntoBalancedGroups(members, partnerHistory, opponentHistory);
    }
  }

  /// N명의 선수를 급수합 밸런스가 최적화되도록 4인 1조들로 스네이크(Folding) 분배
  /// - 코트별로 상위 2명 + 하위 2명이 균등하게 들어가 A+D vs B+C 조합을 만들 수 있도록 보장
  /// - 동일 급수대 내에서 이전 파트너/상대 중복이 가장 적은 코트로 배정
  List<List<Member>> _distributeIntoBalancedGroups(
    List<Member> members,
    Map<String, int> partnerHistory,
    Map<String, int> opponentHistory,
  ) {
    if (members.length < 4) return [];

    final count = (members.length ~/ 4) * 4;
    // 동일 급수 내 순서 편향 방지를 위해 셔플 후 급수 내림차순 정렬
    final sorted = List<Member>.from(members)..shuffle(_random);
    sorted.sort((a, b) => b.tierWeight.compareTo(a.tierWeight));

    final target = sorted.take(count).toList();
    final numCourts = count ~/ 4;

    final courtGroups = List.generate(numCourts, (_) => <Member>[]);

    // 4개 급수 구간(Band 0: 최상위, Band 1: 차상위, Band 2: 중하위, Band 3: 최하위)으로 분할
    for (int band = 0; band < 4; band++) {
      final bandPlayers = target.sublist(band * numCourts, (band + 1) * numCourts);
      if (band == 0) {
        for (int c = 0; c < numCourts; c++) {
          courtGroups[c].add(bandPlayers[c]);
        }
      } else {
        // 스네이크 기본 순서를 따르되, 코트 내 기존 배정 선수와의 급수 균형 및 중복 페널티가 최소인 코트에 배치
        final isForward = (band == 3);
        final orderedPlayers = isForward ? bandPlayers : bandPlayers.reversed.toList();
        final assignedCourts = <int>{};

        for (final candidate in orderedPlayers) {
          int bestCourt = -1;
          double bestCost = double.infinity;

          for (int c = 0; c < numCourts; c++) {
            if (assignedCourts.contains(c)) continue;
            final existing = courtGroups[c];

            double cost = 0;
            for (final ex in existing) {
              final key = _pairKey(candidate.id, ex.id);
              cost += (partnerHistory[key] ?? 0) * 50.0;
              cost += (opponentHistory[key] ?? 0) * 10.0;
            }

            // 4번째 마지막 선수 배정 시, 해당 코트 4명이 이룰 수 있는 최소 급수차(minTierDiff) 검증
            if (existing.length == 3) {
              final four = [...existing, candidate];
              final d1 = ((four[0].tierWeight + four[1].tierWeight) - (four[2].tierWeight + four[3].tierWeight)).abs();
              final d2 = ((four[0].tierWeight + four[2].tierWeight) - (four[1].tierWeight + four[3].tierWeight)).abs();
              final d3 = ((four[0].tierWeight + four[3].tierWeight) - (four[1].tierWeight + four[2].tierWeight)).abs();
              final minDiff = min(d1, min(d2, d3));
              // 급수합 차이 1점 초과 시 큰 페널티 부여하여 0~1점 차이 코트 구성을 최우선 유도
              if (minDiff > 1) {
                cost += minDiff * 5000.0;
              } else {
                cost += minDiff * 200.0;
              }
            }

            if (cost < bestCost) {
              bestCost = cost;
              bestCourt = c;
            }
          }

          assignedCourts.add(bestCourt);
          courtGroups[bestCourt].add(candidate);
        }
      }
    }

    return courtGroups;
  }

  /// 혼합 복식 전용 4인 조 편성 (각 조당 남성 2명, 여성 2명 필수 배정)
  List<List<Member>> _createMixedFourPlayerGroups(
    List<Member> selected, {
    MatchMode matchMode = MatchMode.tiered,
  }) {
    final males = selected.where((m) => m.gender == Gender.male).toList()
      ..shuffle(_random);
    final females = selected.where((m) => m.gender == Gender.female).toList()
      ..shuffle(_random);

    if (matchMode != MatchMode.random) {
      males.sort((a, b) => b.tierWeight.compareTo(a.tierWeight));
      females.sort((a, b) => b.tierWeight.compareTo(a.tierWeight));
    }

    final maxCourts = min(males.length ~/ 2, females.length ~/ 2);
    final groups = <List<Member>>[];

    for (int i = 0; i < maxCourts; i++) {
      final m1 = males[i];
      final m2 = males[maxCourts * 2 - 1 - i];
      final f1 = females[i];
      final f2 = females[maxCourts * 2 - 1 - i];
      groups.add([m1, m2, f1, f2]);
    }

    return groups;
  }

  /// 4인 1조 내에서 최적의 급수 밸런스(A+D vs B+C) 또는 무작위 셔플 및 파트너/상대 중복 최소화 매칭
  /// - MatchMode.random인 경우: 급수 점수를 고려하지 않고 무작위 셔플 매칭
  /// - 그 외(tiered / all):
  ///   1순위: 코트 내 양 팀 급수합 차이 최소화 (최대 1~2점 이내 강제, A+A vs B+B 방지)
  ///   2순위: 파트너 중복 회피
  ///   3순위: 상대팀 중복 회피
  GameMatch _balanceMatch({
    required String sessionId,
    required int round,
    required int courtNumber,
    required List<Member> fourPlayers,
    required MatchType matchType,
    MatchMode matchMode = MatchMode.tiered,
    required Map<String, int> partnerHistory,
    required Map<String, int> opponentHistory,
  }) {
    assert(fourPlayers.length == 4);

    // 가능한 3가지 2 vs 2 팀 분할 조합 생성
    final candidates = <(List<Member>, List<Member>)>[];
    final males = fourPlayers.where((m) => m.gender == Gender.male).toList();
    final females = fourPlayers.where((m) => m.gender == Gender.female).toList();

    if ((matchType == MatchType.mixedOnly || matchType == MatchType.genderPriority) &&
        males.length == 2 &&
        females.length == 2) {
      // 혼복(또는 남복/여복 우선의 잔여 혼복 코트)인 경우 반드시 (남1, 여1) vs (남1, 여1) 편성
      candidates.add(([males[0], females[0]], [males[1], females[1]]));
      candidates.add(([males[0], females[1]], [males[1], females[0]]));
    } else if (matchType == MatchType.mixedOnly) {
      // 예외 폴백
      candidates.add(([fourPlayers[0], fourPlayers[1]], [fourPlayers[2], fourPlayers[3]]));
    } else {
      // 일반/남복/여복 복식: 3가지 조합
      candidates.add(([fourPlayers[0], fourPlayers[1]], [fourPlayers[2], fourPlayers[3]]));
      candidates.add(([fourPlayers[0], fourPlayers[2]], [fourPlayers[1], fourPlayers[3]]));
      candidates.add(([fourPlayers[0], fourPlayers[3]], [fourPlayers[1], fourPlayers[2]]));
    }

    // [급수 무관 (랜덤 매칭)]: 급수 차이를 고려하지 않고 무작위 셔플 후 선택
    if (matchMode == MatchMode.random) {
      final shuffled = List<(List<Member>, List<Member>)>.from(candidates)..shuffle(_random);
      final chosen = shuffled.first;
      return GameMatch(
        id: _uuid.v4(),
        sessionId: sessionId,
        round: round,
        courtNumber: courtNumber,
        teamA: [chosen.$1[0].id, chosen.$1[1].id],
        teamB: [chosen.$2[0].id, chosen.$2[1].id],
        status: MatchStatus.pending,
      );
    }

    // 1단계: 가능한 조합 중 최소 급수합 차이(minTierDiff) 계산
    int minTierDiff = 999;
    for (final combo in candidates) {
      final diff = ((combo.$1[0].tierWeight + combo.$1[1].tierWeight) -
              (combo.$2[0].tierWeight + combo.$2[1].tierWeight))
          .abs();
      if (diff < minTierDiff) {
        minTierDiff = diff;
      }
    }

    // 2단계: 최우선 조건 강제:
    // 급수 차이가 minTierDiff(또는 최대 minTierDiff + 1 이내)인 밸런스 조합 우선 필터링
    // 0~1점 차이 균등 조합이 존재할 경우 2점 이상 차이나는 편중 조합은 제외
    final balancedCandidates = candidates.where((combo) {
      final diff = ((combo.$1[0].tierWeight + combo.$1[1].tierWeight) -
              (combo.$2[0].tierWeight + combo.$2[1].tierWeight))
          .abs();
      if (minTierDiff <= 1) {
        return diff <= 1;
      }
      return diff <= minTierDiff;
    }).toList();

    final validCandidates = balancedCandidates.isNotEmpty ? balancedCandidates : candidates;

    // 3단계: 차순위 조건 스코어링 (파트너 중복 회피 -> 상대팀 중복 회피)
    (List<Member>, List<Member>) bestCombo = validCandidates.first;
    double minPenalty = double.infinity;

    for (final combo in validCandidates) {
      final teamA = combo.$1;
      final teamB = combo.$2;

      // 1. 급수 밸런스 점수차: |(teamA 급수합) - (teamB 급수합)|
      final weightA = teamA[0].tierWeight + teamA[1].tierWeight;
      final weightB = teamB[0].tierWeight + teamB[1].tierWeight;
      final tierDiff = (weightA - weightB).abs();

      // 2. 파트너 중복 페널티 (최근 파트너를 했던 횟수)
      final pairA = _pairKey(teamA[0].id, teamA[1].id);
      final pairB = _pairKey(teamB[0].id, teamB[1].id);
      final partnerCount = (partnerHistory[pairA] ?? 0) + (partnerHistory[pairB] ?? 0);

      // 3. 상대팀 중복 페널티
      int opponentCount = 0;
      for (final a in teamA) {
        for (final b in teamB) {
          opponentCount += (opponentHistory[_pairKey(a.id, b.id)] ?? 0);
        }
      }

      // [핵심 가중치 체계]:
      // 급수 차이 페널티는 압도적 가중치(10,000점)를 두어 실력 균형을 최우선시함.
      // 파트너 중복은 100점, 상대팀 중복은 10점으로 차순위 적용하여,
      // 인원이 적어 중복 회피와 실력 균형이 충돌할 때 중복을 허용하더라도 경기 균형(점수 격차 최소화)을 무조건 보장함!
      final penalty = (tierDiff * 10000.0) + (partnerCount * 100.0) + (opponentCount * 10.0);

      if (penalty < minPenalty) {
        minPenalty = penalty;
        bestCombo = combo;
      }
    }

    return GameMatch(
      id: _uuid.v4(),
      sessionId: sessionId,
      round: round,
      courtNumber: courtNumber,
      teamA: [bestCombo.$1[0].id, bestCombo.$1[1].id],
      teamB: [bestCombo.$2[0].id, bestCombo.$2[1].id],
      status: MatchStatus.pending,
    );
  }

  /// 두 회원 ID의 정렬된 쌍 키 생성 (중복 방지 맵용)
  String _pairKey(String id1, String id2) {
    return id1.compareTo(id2) < 0 ? '$id1:$id2' : '$id2:$id1';
  }

  /// 과거 파트너 매칭 이력 맵 구축
  Map<String, int> _buildPartnerHistory(List<GameMatch> matches) {
    final history = <String, int>{};
    for (final m in matches) {
      if (m.teamA.length == 2) {
        final keyA = _pairKey(m.teamA[0], m.teamA[1]);
        history[keyA] = (history[keyA] ?? 0) + 1;
      }
      if (m.teamB.length == 2) {
        final keyB = _pairKey(m.teamB[0], m.teamB[1]);
        history[keyB] = (history[keyB] ?? 0) + 1;
      }
    }
    return history;
  }

  /// 과거 상대팀 매칭 이력 맵 구축
  Map<String, int> _buildOpponentHistory(List<GameMatch> matches) {
    final history = <String, int>{};
    for (final m in matches) {
      for (final a in m.teamA) {
        for (final b in m.teamB) {
          final key = _pairKey(a, b);
          history[key] = (history[key] ?? 0) + 1;
        }
      }
    }
    return history;
  }

  /// 경기 중 부상/조퇴 발생 시 원클릭 대체 선수 치환
  GameMatch replacePlayerInMatch({
    required GameMatch match,
    required String outPlayerId,
    required String substitutePlayerId,
  }) {
    if (!match.containsPlayer(outPlayerId)) return match;

    final updatedTeamA = match.teamA
        .map((id) => id == outPlayerId ? substitutePlayerId : id)
        .toList();
    final updatedTeamB = match.teamB
        .map((id) => id == outPlayerId ? substitutePlayerId : id)
        .toList();

    return match.copyWith(
      teamA: updatedTeamA,
      teamB: updatedTeamB,
    );
  }

  /// 현재 라운드에서 대기(휴식) 중인 선수 중 가장 출전 횟수가 적은 최적의 대체 선수 추천
  String? findBestSubstitute({
    required GameSession session,
    required List<GameMatch> currentRoundMatches,
    required List<GameMatch> allMatches,
  }) {
    final playingNow = <String>{};
    for (final m in currentRoundMatches) {
      playingNow.addAll(m.allPlayerIds);
    }

    final playCounts = _calculatePlayCounts(allMatches);

    // 실시간 활동 참석자 중 현재 라운드 미출전 회원 검색
    final waiting = session.activeAttendees
        .where((id) => !playingNow.contains(id))
        .toList();

    if (waiting.isEmpty) return null;

    // 출전 횟수가 가장 적은 순으로 정렬
    waiting.sort((a, b) => (playCounts[a] ?? 0).compareTo(playCounts[b] ?? 0));
    return waiting.first;
  }

  /// 지각자 실시간 합류 등록 (세션의 activeAttendees에 추가 및 반환)
  GameSession registerLatecomer(GameSession session, String memberId) {
    final updatedAttendees = List<String>.from(session.attendees);
    final updatedActive = List<String>.from(session.activeAttendees);

    if (!updatedAttendees.contains(memberId)) {
      updatedAttendees.add(memberId);
    }
    if (!updatedActive.contains(memberId)) {
      updatedActive.add(memberId);
    }

    return session.copyWith(
      attendees: updatedAttendees,
      activeAttendees: updatedActive,
    );
  }

  /// 조퇴/부상자 실시간 제외 처리
  GameSession markEarlyDeparture(GameSession session, String memberId) {
    final updatedActive = List<String>.from(session.activeAttendees)
      ..remove(memberId);
    return session.copyWith(activeAttendees: updatedActive);
  }

  /// 대회/리그 순위 자동 산출 (다승 -> 득실차 -> 다득점 -> 승자승 순)
  List<PlayerStanding> calculateRankings({
    required List<GameMatch> finishedMatches,
    required List<Member> members,
  }) {
    final standings = <String, PlayerStanding>{};

    for (final m in members) {
      standings[m.id] = PlayerStanding(
        memberId: m.id,
        memberName: m.name,
        tier: m.tier,
      );
    }

    // 경기별 결과 집계
    for (final match in finishedMatches.where((m) => m.isFinished)) {
      final scoreA = match.scoreA;
      final scoreB = match.scoreB;
      final isAWon = match.isTeamAWon;
      final isBWon = match.isTeamBWon;
      final isDraw = match.isDraw;

      for (final id in match.teamA) {
        if (!standings.containsKey(id)) continue;
        final current = standings[id]!;
        standings[id] = current.copyWith(
          matchesPlayed: current.matchesPlayed + 1,
          wins: current.wins + (isAWon ? 1 : 0),
          losses: current.losses + (isBWon ? 1 : 0),
          draws: current.draws + (isDraw ? 1 : 0),
          pointsFor: current.pointsFor + scoreA,
          pointsAgainst: current.pointsAgainst + scoreB,
        );
      }

      for (final id in match.teamB) {
        if (!standings.containsKey(id)) continue;
        final current = standings[id]!;
        standings[id] = current.copyWith(
          matchesPlayed: current.matchesPlayed + 1,
          wins: current.wins + (isBWon ? 1 : 0),
          losses: current.losses + (isAWon ? 1 : 0),
          draws: current.draws + (isDraw ? 1 : 0),
          pointsFor: current.pointsFor + scoreB,
          pointsAgainst: current.pointsAgainst + scoreA,
        );
      }
    }

    // 랭킹 정렬: 다승 -> 득실차 -> 다득점 -> 승자승
    final result = standings.values.toList();
    result.sort((a, b) {
      // 1. 다승
      if (a.wins != b.wins) return b.wins.compareTo(a.wins);

      // 2. 득실차
      if (a.pointDifference != b.pointDifference) {
        return b.pointDifference.compareTo(a.pointDifference);
      }

      // 3. 다득점
      if (a.pointsFor != b.pointsFor) {
        return b.pointsFor.compareTo(a.pointsFor);
      }

      // 4. 승자승 (Head-to-head)
      final headToHead = _compareHeadToHead(a.memberId, b.memberId, finishedMatches);
      if (headToHead != 0) return headToHead;

      return a.memberName.compareTo(b.memberName);
    });

    // 순위(rank) 부여
    for (int i = 0; i < result.length; i++) {
      result[i].rank = i + 1;
    }

    return result;
  }

  /// [정기 로테이션 (개인 기준)] 순위 산출
  /// - 개인별 경기 수 편차를 반영하여 승률 최우선 적용
  /// - 타이브레이커: 1순위 승률 -> 2순위 득실차 -> 3순위 다승 -> 4순위 다득점 (승자승 제외)
  List<PlayerStanding> calculateRegularRotationRankings({
    required List<GameMatch> finishedMatches,
    required List<Member> members,
    bool onlyPlayedPlayers = false,
  }) {
    final memberMap = {for (final m in members) m.id: m};
    final standings = <String, PlayerStanding>{};

    for (final m in members) {
      standings[m.id] = PlayerStanding(
        memberId: m.id,
        memberName: m.name,
        tier: m.tier,
      );
    }

    for (final match in finishedMatches.where((m) => m.isFinished)) {
      final scoreA = match.scoreA;
      final scoreB = match.scoreB;
      final isAWon = match.isTeamAWon;
      final isBWon = match.isTeamBWon;
      final isDraw = match.isDraw;

      for (final id in match.teamA) {
        final current = standings[id] ??
            PlayerStanding(
              memberId: id,
              memberName: memberMap[id]?.name ?? id,
              tier: memberMap[id]?.tier,
            );
        standings[id] = current.copyWith(
          matchesPlayed: current.matchesPlayed + 1,
          wins: current.wins + (isAWon ? 1 : 0),
          losses: current.losses + (isBWon ? 1 : 0),
          draws: current.draws + (isDraw ? 1 : 0),
          pointsFor: current.pointsFor + scoreA,
          pointsAgainst: current.pointsAgainst + scoreB,
        );
      }

      for (final id in match.teamB) {
        final current = standings[id] ??
            PlayerStanding(
              memberId: id,
              memberName: memberMap[id]?.name ?? id,
              tier: memberMap[id]?.tier,
            );
        standings[id] = current.copyWith(
          matchesPlayed: current.matchesPlayed + 1,
          wins: current.wins + (isBWon ? 1 : 0),
          losses: current.losses + (isAWon ? 1 : 0),
          draws: current.draws + (isDraw ? 1 : 0),
          pointsFor: current.pointsFor + scoreB,
          pointsAgainst: current.pointsAgainst + scoreA,
        );
      }
    }

    final result = standings.values
        .where((s) => !onlyPlayedPlayers || s.matchesPlayed > 0)
        .toList();

    result.sort((a, b) {
      // 출전 경기가 있는 선수를 미출전(0경기) 선수보다 우선 배치
      if ((a.matchesPlayed > 0) != (b.matchesPlayed > 0)) {
        return a.matchesPlayed > 0 ? -1 : 1;
      }

      // 1순위: 승률 (Win Rate)
      if ((a.winRate - b.winRate).abs() > 1e-6) {
        return b.winRate.compareTo(a.winRate);
      }

      // 2순위: 득실차 (Point Difference)
      if (a.pointDifference != b.pointDifference) {
        return b.pointDifference.compareTo(a.pointDifference);
      }

      // 3순위: 다승 (Wins)
      if (a.wins != b.wins) {
        return b.wins.compareTo(a.wins);
      }

      // 4순위: 다득점 (Points For) - 승자승 제외
      if (a.pointsFor != b.pointsFor) {
        return b.pointsFor.compareTo(a.pointsFor);
      }

      return a.memberName.compareTo(b.memberName);
    });

    for (int i = 0; i < result.length; i++) {
      result[i].rank = i + 1;
    }

    return result;
  }

  /// [풀리그전 (팀 기준)] 순위 산출
  /// - 2인 복식 페어(팀) 단위 집계
  /// - 타이브레이커: 1순위 다승 -> 2순위 승자승 -> 3순위 득실차 -> 4순위 다득점
  List<TeamStanding> calculateLeagueTeamRankings({
    required List<GameMatch> finishedMatches,
    required List<Member> members,
  }) {
    final memberMap = {for (final m in members) m.id: m};
    final teamStandings = <String, TeamStanding>{};

    String makeTeamKey(List<String> teamIds) {
      final sorted = List<String>.from(teamIds)..sort();
      return sorted.join('_');
    }

    TeamStanding getOrCreateTeam(List<String> teamIds) {
      final key = makeTeamKey(teamIds);
      if (teamStandings.containsKey(key)) {
        return teamStandings[key]!;
      }
      final names = teamIds.map((id) => memberMap[id]?.name ?? id).toList();
      final tiers = teamIds.map((id) => memberMap[id]?.tier ?? Tier.c).toList();
      final created = TeamStanding(
        teamKey: key,
        playerIds: List<String>.from(teamIds),
        playerNames: names,
        playerTiers: tiers,
      );
      teamStandings[key] = created;
      return created;
    }

    final completed = finishedMatches.where((m) => m.isFinished).toList();

    for (final match in completed) {
      final scoreA = match.scoreA;
      final scoreB = match.scoreB;
      final isAWon = match.isTeamAWon;
      final isBWon = match.isTeamBWon;
      final isDraw = match.isDraw;

      final teamAStanding = getOrCreateTeam(match.teamA);
      teamStandings[teamAStanding.teamKey] = teamAStanding.copyWith(
        matchesPlayed: teamAStanding.matchesPlayed + 1,
        wins: teamAStanding.wins + (isAWon ? 1 : 0),
        losses: teamAStanding.losses + (isBWon ? 1 : 0),
        draws: teamAStanding.draws + (isDraw ? 1 : 0),
        pointsFor: teamAStanding.pointsFor + scoreA,
        pointsAgainst: teamAStanding.pointsAgainst + scoreB,
      );

      final teamBStanding = getOrCreateTeam(match.teamB);
      teamStandings[teamBStanding.teamKey] = teamBStanding.copyWith(
        matchesPlayed: teamBStanding.matchesPlayed + 1,
        wins: teamBStanding.wins + (isBWon ? 1 : 0),
        losses: teamBStanding.losses + (isAWon ? 1 : 0),
        draws: teamBStanding.draws + (isDraw ? 1 : 0),
        pointsFor: teamBStanding.pointsFor + scoreB,
        pointsAgainst: teamBStanding.pointsAgainst + scoreA,
      );
    }

    final result = teamStandings.values.toList();
    result.sort((a, b) {
      // 1순위: 다승 (Wins)
      if (a.wins != b.wins) {
        return b.wins.compareTo(a.wins);
      }

      // 2순위: 승자승 (Head-to-head between Team A and Team B)
      final h2h = _compareTeamHeadToHead(a.teamKey, b.teamKey, completed);
      if (h2h != 0) return h2h;

      // 3순위: 득실차 (Point Difference)
      if (a.pointDifference != b.pointDifference) {
        return b.pointDifference.compareTo(a.pointDifference);
      }

      // 4순위: 다득점 (Points For)
      if (a.pointsFor != b.pointsFor) {
        return b.pointsFor.compareTo(a.pointsFor);
      }

      return a.teamName.compareTo(b.teamName);
    });

    for (int i = 0; i < result.length; i++) {
      result[i].rank = i + 1;
    }

    return result;
  }

  /// 두 팀(페어) 간의 승자승 비교
  int _compareTeamHeadToHead(
    String teamKeyA,
    String teamKeyB,
    List<GameMatch> completedMatches,
  ) {
    String makeTeamKey(List<String> teamIds) {
      final sorted = List<String>.from(teamIds)..sort();
      return sorted.join('_');
    }

    int aWinsOverB = 0;
    int bWinsOverA = 0;

    for (final match in completedMatches) {
      final mKeyA = makeTeamKey(match.teamA);
      final mKeyB = makeTeamKey(match.teamB);

      if (mKeyA == teamKeyA && mKeyB == teamKeyB) {
        if (match.isTeamAWon) aWinsOverB++;
        if (match.isTeamBWon) bWinsOverA++;
      } else if (mKeyA == teamKeyB && mKeyB == teamKeyA) {
        if (match.isTeamBWon) aWinsOverB++;
        if (match.isTeamAWon) bWinsOverA++;
      }
    }

    if (aWinsOverB != bWinsOverA) {
      return bWinsOverA.compareTo(aWinsOverB);
    }
    return 0;
  }

  /// [토너먼트] 최종 트리 (우승, 준우승, 4강, 8강 등 진출 단계 기준) 생성
  TournamentResultTree buildTournamentResultTree({
    required List<GameMatch> matches,
    required List<Member> members,
  }) {
    final memberMap = {for (final m in members) m.id: m};
    final matchesByRound = <int, List<GameMatch>>{};

    for (final m in matches) {
      matchesByRound.putIfAbsent(m.round, () => []).add(m);
    }
    for (final r in matchesByRound.keys) {
      matchesByRound[r]!.sort((a, b) => a.courtNumber.compareTo(b.courtNumber));
    }

    if (matches.isEmpty) {
      return const TournamentResultTree();
    }

    String makeTeamKey(List<String> teamIds) {
      final sorted = List<String>.from(teamIds)..sort();
      return sorted.join('_');
    }

    // 전체 페어 누적 전적 집계
    final teamNodes = <String, TournamentTeamNode>{};
    TournamentTeamNode getOrUpdateNode(
      List<String> teamIds, {
      int addWins = 0,
      int addLosses = 0,
      int addPointsFor = 0,
      int addPointsAgainst = 0,
    }) {
      final key = makeTeamKey(teamIds);
      final existing = teamNodes[key];
      final names = teamIds.map((id) => memberMap[id]?.name ?? id).toList();
      final tiers = teamIds.map((id) => memberMap[id]?.tier ?? Tier.c).toList();
      final updated = TournamentTeamNode(
        teamKey: key,
        playerIds: existing?.playerIds ?? List<String>.from(teamIds),
        playerNames: existing?.playerNames ?? names,
        playerTiers: existing?.playerTiers ?? tiers,
        wins: (existing?.wins ?? 0) + addWins,
        losses: (existing?.losses ?? 0) + addLosses,
        pointsFor: (existing?.pointsFor ?? 0) + addPointsFor,
        pointsAgainst: (existing?.pointsAgainst ?? 0) + addPointsAgainst,
      );
      teamNodes[key] = updated;
      return updated;
    }

    for (final m in matches) {
      final aWon = m.isTeamAWon || (m.scoreA > m.scoreB);
      final bWon = m.isTeamBWon || (m.scoreB > m.scoreA);
      getOrUpdateNode(
        m.teamA,
        addWins: aWon ? 1 : 0,
        addLosses: bWon ? 1 : 0,
        addPointsFor: m.scoreA,
        addPointsAgainst: m.scoreB,
      );
      getOrUpdateNode(
        m.teamB,
        addWins: bWon ? 1 : 0,
        addLosses: aWon ? 1 : 0,
        addPointsFor: m.scoreB,
        addPointsAgainst: m.scoreA,
      );
    }

    final rounds = matchesByRound.keys.toList()..sort();
    final maxRound = rounds.last;
    final placedTeamKeys = <String>{};
    final stagePlacements = <TournamentStagePlacement>[];

    TournamentTeamNode? champion;
    TournamentTeamNode? runnerUp;
    final semiFinalists = <TournamentTeamNode>[];

    // 최종 라운드(결승전 또는 마지막 진행된 라운드) 처리
    final finalRoundMatches = matchesByRound[maxRound] ?? [];
    final finalWinners = <TournamentTeamNode>[];
    final finalLosers = <TournamentTeamNode>[];

    for (final m in finalRoundMatches) {
      final keyA = makeTeamKey(m.teamA);
      final keyB = makeTeamKey(m.teamB);
      final aWon = m.isTeamAWon || (m.scoreA > m.scoreB);
      final bWon = m.isTeamBWon || (m.scoreB > m.scoreA);

      if (aWon) {
        finalWinners.add(teamNodes[keyA]!);
        finalLosers.add(teamNodes[keyB]!);
        placedTeamKeys.add(keyA);
        placedTeamKeys.add(keyB);
      } else if (bWon) {
        finalWinners.add(teamNodes[keyB]!);
        finalLosers.add(teamNodes[keyA]!);
        placedTeamKeys.add(keyB);
        placedTeamKeys.add(keyA);
      } else {
        // 무승부 또는 미완료 시 둘 다 결승 진출로 등록
        finalWinners.add(teamNodes[keyA]!);
        finalWinners.add(teamNodes[keyB]!);
        placedTeamKeys.add(keyA);
        placedTeamKeys.add(keyB);
      }
    }

    if (finalWinners.isNotEmpty) {
      champion = finalWinners.first;
      stagePlacements.add(
        TournamentStagePlacement(
          stageTitle: finalWinners.length == 1 ? '우승 (CHAMPION)' : '결승 / 최종 승자',
          badgeEmoji: '🏆',
          roundNumber: maxRound,
          teams: finalWinners,
        ),
      );
    }

    if (finalLosers.isNotEmpty) {
      runnerUp = finalLosers.first;
      stagePlacements.add(
        TournamentStagePlacement(
          stageTitle: finalLosers.length == 1 ? '준우승 (RUNNER-UP)' : '결승 / 최종 라운드 아쉽게 패배',
          badgeEmoji: '🥈',
          roundNumber: maxRound,
          teams: finalLosers,
        ),
      );
    }

    // 이전 라운드들 역순으로 4강, 8강, 16강 등 단계 산출
    for (int i = rounds.length - 2; i >= 0; i--) {
      final r = rounds[i];
      final rMatches = matchesByRound[r] ?? [];
      final stageTeams = <TournamentTeamNode>[];

      for (final m in rMatches) {
        final keyA = makeTeamKey(m.teamA);
        final keyB = makeTeamKey(m.teamB);
        if (!placedTeamKeys.contains(keyA)) {
          stageTeams.add(teamNodes[keyA]!);
          placedTeamKeys.add(keyA);
        }
        if (!placedTeamKeys.contains(keyB)) {
          stageTeams.add(teamNodes[keyB]!);
          placedTeamKeys.add(keyB);
        }
      }

      if (stageTeams.isEmpty) continue;

      // 득실차 -> 다득점 순 정렬
      stageTeams.sort((a, b) {
        if (a.pointDifference != b.pointDifference) {
          return b.pointDifference.compareTo(a.pointDifference);
        }
        return b.pointsFor.compareTo(a.pointsFor);
      });

      final distanceFromFinal = maxRound - r;
      String stageTitle;
      String emoji;
      if (distanceFromFinal == 1) {
        stageTitle = '4강 (SEMI-FINAL)';
        emoji = '🥉';
        semiFinalists.addAll(stageTeams);
      } else if (distanceFromFinal == 2) {
        stageTitle = '8강 (QUARTER-FINAL)';
        emoji = '🎖️';
      } else if (distanceFromFinal == 3) {
        stageTitle = '16강 (ROUND OF 16)';
        emoji = '🎗️';
      } else {
        stageTitle = '$r라운드 진출';
        emoji = '🏸';
      }

      stagePlacements.add(
        TournamentStagePlacement(
          stageTitle: stageTitle,
          badgeEmoji: emoji,
          roundNumber: r,
          teams: stageTeams,
        ),
      );
    }

    return TournamentResultTree(
      champion: champion,
      runnerUp: runnerUp,
      semiFinalists: semiFinalists,
      stagePlacements: stagePlacements,
      matchesByRound: matchesByRound,
    );
  }

  /// 두 선수 간의 승자승(Head-to-head) 비교
  /// a가 이겼으면 -1, b가 이겼으면 1, 무승부/기록 없으면 0
  int _compareHeadToHead(String idA, String idB, List<GameMatch> matches) {
    int aWinsOverB = 0;
    int bWinsOverA = 0;

    for (final match in matches.where((m) => m.isFinished)) {
      final aInTeamA = match.teamA.contains(idA);
      final aInTeamB = match.teamB.contains(idA);
      final bInTeamA = match.teamA.contains(idB);
      final bInTeamB = match.teamB.contains(idB);

      // 서로 상대팀으로 만났을 때만 계산
      if (aInTeamA && bInTeamB) {
        if (match.isTeamAWon) aWinsOverB++;
        if (match.isTeamBWon) bWinsOverA++;
      } else if (aInTeamB && bInTeamA) {
        if (match.isTeamBWon) aWinsOverB++;
        if (match.isTeamAWon) bWinsOverA++;
      }
    }

    if (aWinsOverB != bWinsOverA) {
      return bWinsOverA.compareTo(aWinsOverB);
    }
    return 0;
  }

  /// 대진표 코트 번호 변경 및 스왑(Swap) 처리
  /// - 빈 코트로 변경 시: 해당 매치가 새 코트 번호로 이동
  /// - 이미 다른 매치가 진행/배정 중인 코트 선택 시: 두 코트의 경기 배치가 서로 맞바꿈(Swap) 처리
  ({List<GameMatch> updatedMatches, bool swapped, int oldCourt, int newCourt}) changeOrSwapCourt({
    required List<GameMatch> matches,
    required String matchId,
    required int targetCourtNumber,
  }) {
    final targetIdx = matches.indexWhere((m) => m.id == matchId);
    if (targetIdx < 0) {
      return (
        updatedMatches: matches,
        swapped: false,
        oldCourt: targetCourtNumber,
        newCourt: targetCourtNumber,
      );
    }

    final targetMatch = matches[targetIdx];
    final oldCourtNumber = targetMatch.courtNumber;
    if (oldCourtNumber == targetCourtNumber) {
      return (
        updatedMatches: matches,
        swapped: false,
        oldCourt: oldCourtNumber,
        newCourt: targetCourtNumber,
      );
    }

    // 동일 세션 및 동일 라운드에 targetCourtNumber를 배정받은 다른 매치 탐색
    final occupyingMatch = matches
        .where(
          (m) =>
              m.id != matchId &&
              m.sessionId == targetMatch.sessionId &&
              m.round == targetMatch.round &&
              m.courtNumber == targetCourtNumber,
        )
        .firstOrNull;

    final updated = matches.map((m) {
      if (m.id == matchId) {
        return m.copyWith(courtNumber: targetCourtNumber);
      }
      if (occupyingMatch != null && m.id == occupyingMatch.id) {
        return m.copyWith(courtNumber: oldCourtNumber);
      }
      return m;
    }).toList();

    return (
      updatedMatches: updated,
      swapped: occupyingMatch != null,
      oldCourt: oldCourtNumber,
      newCourt: targetCourtNumber,
    );
  }
}

