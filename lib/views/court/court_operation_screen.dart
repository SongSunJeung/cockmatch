import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// [화면 3] 대진표 및 실시간 코트 운영 화면
/// - 메인 화면 인라인 직접 점수 입력 (숫자 키패드 TextField, 실시간 자동 저장)
/// - 원터치 [경기 완료] 토글/체크 버튼
/// - 라운드별 경기 탭 (1R, 2R, 3R...) 및 알고리즘 기반 즉시 자동 생성
/// - 부상/조퇴 원클릭 대체 선수 치환
/// - 실시간 랭킹(다승->득실차->다득점->승자승) 팝업 모달
/// - 비회원 웹 링크 복사
class CourtOperationScreen extends ConsumerWidget {
  const CourtOperationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentClub = ref.watch(currentClubProvider);
    final session = ref.watch(sessionProvider);

    if (session == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              // 1. 상단 앱바 & 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.pastelMint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text('🏸', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  currentClub.clubName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.pastelYellow,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '모임 대기 중',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.pastelYellowDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            '진행 중인 모임 세션이 없습니다',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.pastelMint,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Icon(
                            Icons.sports_tennis_rounded,
                            size: 44,
                            color: AppTheme.primaryMint,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '진행 중인 모임 세션이 없습니다',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '[오늘 모임 출석부] 탭에서 새 모임을 시작하고 출석 인원을 확정하면 실시간 코트 대진표가 생성됩니다.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryMint,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.checklist_rtl_rounded, size: 20),
                          label: const Text(
                            '출석부에서 새 모임 시작하기',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          onPressed: () {
                            ref.read(currentTabProvider.notifier).setTab(1);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final allMembers = ref.watch(membersProvider);
    final allMatches = ref.watch(matchesProvider);
    final selectedRound = ref.watch(selectedRoundProvider);
    final memberMap = {for (final m in allMembers) m.id: m};
    final isTournament = session.matchFormat == MatchFormat.tournament;

    // 현재 선택된 라운드의 경기 목록 (코트 번호순 정렬)
    final roundMatches = allMatches.where((m) => m.round == selectedRound).toList()
      ..sort((a, b) => a.courtNumber.compareTo(b.courtNumber));

    // 토너먼트 모드일 때 이전 라운드들에서 패배(탈락)한 선수 ID 추출
    final Set<String> eliminatedPlayerIds = {};
    if (isTournament) {
      for (final m in allMatches) {
        if (m.round < selectedRound) {
          if (m.isTeamAWon || m.scoreA > m.scoreB) {
            eliminatedPlayerIds.addAll(m.teamB);
          } else if (m.isTeamBWon || m.scoreB > m.scoreA) {
            eliminatedPlayerIds.addAll(m.teamA);
          }
        }
      }
    }

    // 현재 라운드 출전 선수, 휴식(또는 부전승 대기) 선수, 탈락 선수 계산
    final playingPlayerIds = roundMatches.expand((m) => m.allPlayerIds).toSet();
    final restingMembers = session.activeAttendees
        .where((id) =>
            !playingPlayerIds.contains(id) &&
            !eliminatedPlayerIds.contains(id) &&
            memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList();
    final eliminatedMembers = session.activeAttendees
        .where((id) => eliminatedPlayerIds.contains(id) && memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList();

    // 사용 가능한 총 라운드 목록
    final existingRounds = allMatches.map((m) => m.round).toSet().toList()..sort();
    if (!existingRounds.contains(1)) existingRounds.insert(0, 1);

    final startCourt = session.startCourtNumber;
    final endCourt = startCourt + session.courtCount - 1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // 1. 상단 앱바 & 헤더
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.pastelPeriwinkle,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Center(
                        child: Text(
                          '⚡',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  currentClub.clubName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.pastelMint,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '실시간 대진',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.pastelMintDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '코트 $startCourt~$endCourt번(${session.courtCount}면) · ${session.matchFormat.label} · ${session.matchMode.label}${session.partnerMode == PartnerMode.fixedAll ? ' · 전원 고정 페어' : session.fixedPairs.isNotEmpty ? ' · 고정 페어 ${session.fixedPairs.length}팀' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.leaderboard_rounded, color: AppTheme.textDark),
                      tooltip: '실시간 랭킹 순위표',
                      onPressed: () => _showRankingsDialog(context, ref, allMatches, allMembers),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: AppTheme.textDark),
                      tooltip: '일반 회원용 웹 링크 복사',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: 'https://cockmatch.web.app/viewer/${session.id}'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('일반 회원용 실시간 웹 뷰어 링크가 복사되었습니다!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 2. 파스텔 벤토 상단 요약 카드 (소프트 페리윙클)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelPeriwinkle,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              isTournament
                                  ? '🏆 토너먼트 $selectedRound라운드'
                                  : '라운드 $selectedRound 운영 중',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.pastelPeriwinkleDark,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppTheme.textDark,
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                icon: const Icon(Icons.add_circle_outline, size: 15, color: AppTheme.primaryDark),
                                label: const Text(
                                  '+ 특별 매치 추가',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _showAddCustomMatchModal(
                                  context,
                                  ref,
                                  session,
                                  selectedRound,
                                  roundMatches,
                                  allMembers,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryDark,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                icon: const Icon(Icons.auto_awesome, size: 16),
                                label: const Text(
                                  '대진표 자동 생성',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _handleGenerateRound(
                                  context: context,
                                  ref: ref,
                                  targetRound: selectedRound,
                                  isTournament: isTournament,
                                  allMatches: allMatches,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMetricItem(
                            '출전 인원',
                            '${playingPlayerIds.length}명',
                            '코트 ${roundMatches.length}개',
                          ),
                          if (isTournament)
                            _buildMetricItem(
                              '탈락 인원',
                              '${eliminatedMembers.length}명',
                              '패배 팀 자동 탈락',
                            )
                          else
                            _buildMetricItem(
                              '휴식 인원',
                              '${restingMembers.length}명',
                              '다음 라운드 우선',
                            ),
                          if (isTournament && selectedRound > 1)
                            _buildMetricItem(
                              '부전승 대기',
                              '${restingMembers.length}명',
                              '차기 라운드 진출',
                            )
                          else
                            _buildMetricItem(
                              '출석 인원',
                              '${session.activeAttendees.length}명',
                              '총원 대비 실시간',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. 라운드 선택 탭 (가로 스크롤)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...existingRounds.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () {
                              ref.read(selectedRoundProvider.notifier).setRound(r);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                              decoration: BoxDecoration(
                                color: selectedRound == r ? AppTheme.primaryDark : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selectedRound == r ? Colors.transparent : Colors.grey.shade200,
                                ),
                              ),
                              child: Text(
                                '$r 라운드',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: selectedRound == r ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 새 라운드 추가 버튼
                      InkWell(
                        onTap: () {
                          final nextRound = (existingRounds.isEmpty ? 0 : existingRounds.last) + 1;
                          _handleGenerateRound(
                            context: context,
                            ref: ref,
                            targetRound: nextRound,
                            isTournament: isTournament,
                            allMatches: allMatches,
                            switchRound: true,
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: AppTheme.pastelMint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.add, size: 16, color: AppTheme.pastelMintDark),
                              SizedBox(width: 4),
                              Text(
                                '새 라운드 추가',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.pastelMintDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. 휴식(또는 부전승) 및 토너먼트 탈락 선수 안내 바
            if (restingMembers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isTournament && selectedRound > 1
                              ? Icons.emoji_events_outlined
                              : Icons.pause_circle_outline,
                          size: 18,
                          color: isTournament && selectedRound > 1
                              ? AppTheme.pastelMintDark
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isTournament && selectedRound > 1 ? '부전승 대기: ' : '현재 휴식 중: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isTournament && selectedRound > 1
                                ? AppTheme.pastelMintDark
                                : AppTheme.textMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            restingMembers.map((m) => '${m.name}(${m.tier.label})').join(', '),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (isTournament && eliminatedMembers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelRose.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.pastelRoseDark.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel_outlined, size: 16, color: AppTheme.pastelRoseDark),
                        const SizedBox(width: 8),
                        Text(
                          '토너먼트 탈락 (${eliminatedMembers.length}명): ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.pastelRoseDark,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            eliminatedMembers.map((m) => m.name).join(', '),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 5. 코트별 경기 카드 목록 (인라인 점수 입력 & 원터치 완료 토글)
            if (roundMatches.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sports_tennis_rounded, size: 48, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        '$selectedRound 라운드 대진표가 아직 없습니다.',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.textDark,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.add_circle_outline, size: 16),
                            label: const Text('+ 특별 매치 추가'),
                            onPressed: () => _showAddCustomMatchModal(
                              context,
                              ref,
                              session,
                              selectedRound,
                              roundMatches,
                              allMembers,
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryDark,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: const Text('지금 자동 생성하기'),
                            onPressed: () => _handleGenerateRound(
                              context: context,
                              ref: ref,
                              targetRound: selectedRound,
                              isTournament: isTournament,
                              allMatches: allMatches,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final match = roundMatches[index];
                      return CourtMatchCard(
                        key: ValueKey(match.id),
                        match: match,
                        memberMap: memberMap,
                        restingMembers: restingMembers,
                        roundMatches: roundMatches,
                        isTournament: isTournament,
                      );
                    },
                    childCount: roundMatches.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 라운드 대진표 생성 핸들러 (토너먼트 승자 진출 검증 포함)
  void _handleGenerateRound({
    required BuildContext context,
    required WidgetRef ref,
    required int targetRound,
    required bool isTournament,
    required List<GameMatch> allMatches,
    bool switchRound = false,
  }) {
    if (isTournament && targetRound > 1) {
      final prevRoundMatches = allMatches.where((m) => m.round == targetRound - 1).toList();
      if (prevRoundMatches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('토너먼트 ${targetRound - 1}라운드 경기가 아직 생성되지 않았습니다.'),
          ),
        );
        return;
      }

      // 이전 라운드에 동점(0:0 등)으로 승자가 가려지지 않은 코트가 있는지 확인
      final undecidedMatches = prevRoundMatches
          .where((m) => !m.isTeamAWon && !m.isTeamBWon && m.scoreA == m.scoreB)
          .toList();

      if (undecidedMatches.isNotEmpty) {
        final courtNums = undecidedMatches.map((m) => '${m.courtNumber}번').join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text(
              '⚠️ 토너먼트 ${targetRound - 1}라운드 ($courtNums 코트) 점수를 입력하고 승자(WIN)를 먼저 확정해 주세요!',
            ),
          ),
        );
        return;
      }
    }

    ref.read(matchesProvider.notifier).generateMatchesForRound(targetRound);
    if (switchRound) {
      ref.read(selectedRoundProvider.notifier).setRound(targetRound);
    }

    final updatedMatches = ref.read(matchesProvider).where((m) => m.round == targetRound).toList();
    if (isTournament && targetRound > 1) {
      if (updatedMatches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text('🏆 토너먼트 결승전이 모두 종료되어 최종 우승 페어가 확정되었습니다!'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text(
              '🏆 토너먼트 $targetRound라운드 대진 생성 완료! (승자 페어 ${updatedMatches.length * 2}팀 진출 · ${updatedMatches.length}코트 배정)',
            ),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('라운드 $targetRound 대진표가 생성되었습니다! (${updatedMatches.length}코트)'),
        ),
      );
    }
  }

  /// [+ 특별 매치 추가] 수동 코트 매치 생성 바텀시트 호출
  void _showAddCustomMatchModal(
    BuildContext context,
    WidgetRef ref,
    GameSession session,
    int selectedRound,
    List<GameMatch> roundMatches,
    List<Member> allMembers,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddCustomMatchSheet(
        session: session,
        selectedRound: selectedRound,
        roundMatches: roundMatches,
        allMembers: allMembers,
      ),
    );
  }

  Widget _buildMetricItem(String title, String val, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.pastelPeriwinkleDark, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textDark)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 10, color: Colors.black45)),
      ],
    );
  }

  /// 대회/리그 순위표 모달
  void _showRankingsDialog(
    BuildContext context,
    WidgetRef ref,
    List<GameMatch> matches,
    List<Member> members,
  ) {
    final generator = ref.read(matchGeneratorServiceProvider);
    final rankings = generator.calculateRankings(
      finishedMatches: matches,
      members: members,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('실시간 대회 랭킹 순위표', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: ListView.separated(
            itemCount: rankings.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final r = rankings[index];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: r.rank <= 3 ? Colors.amber.shade100 : Colors.grey.shade100,
                  child: Text(
                    '${r.rank}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: r.rank <= 3 ? Colors.amber.shade900 : Colors.black54,
                    ),
                  ),
                ),
                title: Text(r.memberName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r.wins}승 ${r.losses}패 (승률 ${r.winRate.toStringAsFixed(0)}%)'),
                trailing: Text(
                  '득실 ${r.pointDifference > 0 ? '+${r.pointDifference}' : r.pointDifference} / ${r.pointsFor}점',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}

/// [코트 매치 카드] - 인라인 직접 점수 입력 및 실시간 저장 + 경기 완료 원터치 토글 + 코트 번호 수정
class CourtMatchCard extends ConsumerStatefulWidget {
  final GameMatch match;
  final Map<String, Member> memberMap;
  final List<Member> restingMembers;
  final List<GameMatch> roundMatches;
  final bool isTournament;

  const CourtMatchCard({
    super.key,
    required this.match,
    required this.memberMap,
    required this.restingMembers,
    required this.roundMatches,
    this.isTournament = false,
  });

  @override
  ConsumerState<CourtMatchCard> createState() => _CourtMatchCardState();
}

class _CourtMatchCardState extends ConsumerState<CourtMatchCard> {
  late TextEditingController _scoreACtrl;
  late TextEditingController _scoreBCtrl;

  @override
  void initState() {
    super.initState();
    _scoreACtrl = TextEditingController(text: '${widget.match.scoreA}');
    _scoreBCtrl = TextEditingController(text: '${widget.match.scoreB}');
  }

  @override
  void didUpdateWidget(covariant CourtMatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.match.scoreA.toString() != _scoreACtrl.text) {
      _scoreACtrl.text = '${widget.match.scoreA}';
    }
    if (widget.match.scoreB.toString() != _scoreBCtrl.text) {
      _scoreBCtrl.text = '${widget.match.scoreB}';
    }
  }

  @override
  void dispose() {
    _scoreACtrl.dispose();
    _scoreBCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final teamAMembers = match.teamA.map((id) => widget.memberMap[id] ?? Member(id: id, name: '선수')).toList();
    final teamBMembers = match.teamB.map((id) => widget.memberMap[id] ?? Member(id: id, name: '선수')).toList();

    final teamAWeight = teamAMembers.fold<int>(0, (sum, m) => sum + m.tierWeight);
    final teamBWeight = teamBMembers.fold<int>(0, (sum, m) => sum + m.tierWeight);

    final isFinished = match.isFinished;
    final teamAWon = match.isTeamAWon || (isFinished && match.scoreA > match.scoreB);
    final teamBWon = match.isTeamBWon || (isFinished && match.scoreB > match.scoreA);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isFinished ? AppTheme.primaryMint.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 상단: 코트 번호(터치 시 번호 변경) & 급수합 & [경기 완료] 원터치 버튼 & 선수 교체
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Tooltip(
                    message: '터치하여 코트 번호 변경',
                    child: InkWell(
                      onTap: () => _showEditCourtNumberDialog(context, match),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelYellow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${match.courtNumber}번 코트',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.pastelYellowDark,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit_rounded,
                              size: 11,
                              color: AppTheme.pastelYellowDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '급수합 A:$teamAWeight vs B:$teamBWeight',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  // 원터치 [경기 완료] 토글 버튼
                  InkWell(
                    onTap: () {
                      final nextStatus = isFinished ? MatchStatus.playing : MatchStatus.finished;
                      ref.read(matchesProvider.notifier).updateScore(
                            match.id,
                            match.scoreA,
                            match.scoreB,
                            status: nextStatus,
                          );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isFinished
                            ? AppTheme.primaryMint
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFinished ? AppTheme.primaryMint : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFinished ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 14,
                            color: isFinished ? Colors.white : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isFinished ? '경기 완료됨' : '경기 완료',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isFinished ? Colors.white : AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // [데이터 안전 조건]: 경기 완료 시 Lock 및 교체 비활성화, 진행/대기 시 교체 가능
                  if (isFinished)
                    Tooltip(
                      message: '경기 완료된 코트는 기록 보호를 위해 선수를 교체할 수 없습니다.',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 13, color: Colors.grey),
                            SizedBox(width: 3),
                            Text(
                              '잠김',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => _showPlayerSwapSheet(
                        context: context,
                        match: match,
                        initialTargetPlayer: teamAMembers.first,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelPeriwinkle.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz_rounded, size: 15, color: AppTheme.pastelPeriwinkleDark),
                            SizedBox(width: 3),
                            Text(
                              '선수 교체',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.pastelPeriwinkleDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 메인 대진: TEAM A vs TEAM B 및 인라인 점수 입력창
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // TEAM A 카드 (인라인 점수 입력 필드 포함)
              Expanded(
                child: _buildTeamInlineCard(
                  teamTitle: 'TEAM A',
                  members: teamAMembers,
                  controller: _scoreACtrl,
                  isWinner: teamAWon,
                  isLoser: teamBWon,
                  isFinished: isFinished,
                  onScoreChanged: (val) {
                    final sc = int.tryParse(val.trim()) ?? 0;
                    ref.read(matchesProvider.notifier).updateScore(
                          match.id,
                          sc,
                          match.scoreB,
                          status: match.status == MatchStatus.pending ? MatchStatus.playing : match.status,
                        );
                  },
                  onPlayerTap: (member) {
                    if (!isFinished) {
                      _showPlayerSwapSheet(
                        context: context,
                        match: match,
                        initialTargetPlayer: member,
                      );
                    }
                  },
                ),
              ),

              // 중앙 VS 구분
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // TEAM B 카드 (인라인 점수 입력 필드 포함)
              Expanded(
                child: _buildTeamInlineCard(
                  teamTitle: 'TEAM B',
                  members: teamBMembers,
                  controller: _scoreBCtrl,
                  isWinner: teamBWon,
                  isLoser: teamAWon,
                  isFinished: isFinished,
                  onScoreChanged: (val) {
                    final sc = int.tryParse(val.trim()) ?? 0;
                    ref.read(matchesProvider.notifier).updateScore(
                          match.id,
                          match.scoreA,
                          sc,
                          status: match.status == MatchStatus.pending ? MatchStatus.playing : match.status,
                        );
                  },
                  onPlayerTap: (member) {
                    if (!isFinished) {
                      _showPlayerSwapSheet(
                        context: context,
                        match: match,
                        initialTargetPlayer: member,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [코트 변경/이동] 팝업 다이얼로그 (탭 선택 방식: 빈 코트 이동 / 배정 코트 맞바꿈 Swap)
  void _showEditCourtNumberDialog(BuildContext context, GameMatch match) {
    final ctrl = TextEditingController(text: '${match.courtNumber}');
    final session = ref.read(sessionProvider);
    final startCourt = session?.startCourtNumber ?? 1;
    final configuredEndCourt = startCourt + (session?.courtCount ?? 4) - 1;

    // 사용 가능한 코트 번호 목록 구성 (1번부터 최소 8번 또는 현재 배정된 최대 코트 번호 + 2까지 표시)
    int maxCourtNumber = configuredEndCourt < 8 ? 8 : configuredEndCourt;
    for (final m in widget.roundMatches) {
      if (m.courtNumber + 1 > maxCourtNumber) {
        maxCourtNumber = m.courtNumber + 1;
      }
    }
    final availableCourts = List.generate(maxCourtNumber, (i) => i + 1);

    String formatMatchTeams(GameMatch m) {
      final teamA = m.teamA.map((id) => widget.memberMap[id]?.name ?? '선수').join('·');
      final teamB = m.teamB.map((id) => widget.memberMap[id]?.name ?? '선수').join('·');
      return '$teamA vs $teamB';
    }

    void applyCourtChange(BuildContext dialogContext, int targetCourtNumber) {
      final result = ref.read(matchesProvider.notifier).updateCourtNumber(
            match.id,
            targetCourtNumber,
          );
      Navigator.pop(dialogContext);
      if (result.oldCourt != result.newCourt && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text(
              result.swapped
                  ? '🔄 ${result.oldCourt}번 코트 ↔ ${result.newCourt}번 코트 경기 배치가 서로 맞바꿈(Swap) 되었습니다!'
                  : '✅ ${result.oldCourt}번 코트 경기가 빈 ${result.newCourt}번 코트로 이동되었습니다.',
            ),
          ),
        );
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.swap_calls_rounded, color: AppTheme.primaryMint, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '코트 변경/이동 (현재 ${match.courtNumber}번 코트)',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '• 빈 코트 선택 시: 해당 매치가 새 코트 번호로 즉시 이동합니다.\n'
                    '• 다른 매치가 배정된 코트 선택 시: 두 코트의 경기 배치가 서로 맞바꿈(Swap) 됩니다.',
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: AppTheme.textDark),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '코트 번호 탭하여 즉시 선택',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                ),
                const SizedBox(height: 8),
                ...availableCourts.map((courtNum) {
                  final isCurrent = courtNum == match.courtNumber;
                  final occupyingMatch = widget.roundMatches
                      .where((m) => m.id != match.id && m.courtNumber == courtNum)
                      .firstOrNull;
                  final isOccupied = occupyingMatch != null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => applyCourtChange(ctx, courtNum),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppTheme.pastelYellow.withValues(alpha: 0.45)
                              : isOccupied
                                  ? AppTheme.pastelPeriwinkle.withValues(alpha: 0.3)
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrent
                                ? AppTheme.pastelYellowDark
                                : isOccupied
                                    ? AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.45)
                                    : Colors.grey.shade300,
                            width: isCurrent ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? AppTheme.pastelYellow
                                    : isOccupied
                                        ? AppTheme.pastelPeriwinkle
                                        : AppTheme.pastelMint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$courtNum번 코트',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: isCurrent
                                      ? AppTheme.pastelYellowDark
                                      : isOccupied
                                          ? AppTheme.pastelPeriwinkleDark
                                          : AppTheme.pastelMintDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isCurrent
                                    ? '현재 배정 코트 (${formatMatchTeams(match)})'
                                    : isOccupied
                                        ? formatMatchTeams(occupyingMatch)
                                        : '비어 있음 · 탭하여 이동',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isOccupied || isCurrent ? FontWeight.w700 : FontWeight.w600,
                                  color: isOccupied || isCurrent ? AppTheme.textDark : AppTheme.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? Colors.white
                                    : isOccupied
                                        ? AppTheme.primaryDark
                                        : AppTheme.primaryMint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isCurrent
                                    ? '현재 코트'
                                    : isOccupied
                                        ? '맞바꿈 Swap'
                                        : '빈 코트 이동',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isCurrent ? AppTheme.pastelYellowDark : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '기타 코트 번호 직접 입력',
                    suffixText: '번 코트',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMint,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final num = int.tryParse(ctrl.text.trim());
              if (num != null && num > 0) {
                applyCourtChange(ctx, num);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('직접 번호 적용'),
          ),
        ],
      ),
    );
  }

  /// 팀별 인라인 점수 입력 카드 위젯
  Widget _buildTeamInlineCard({
    required String teamTitle,
    required List<Member> members,
    required TextEditingController controller,
    required bool isWinner,
    required bool isLoser,
    required bool isFinished,
    required ValueChanged<String> onScoreChanged,
    required ValueChanged<Member> onPlayerTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWinner
            ? AppTheme.pastelMint.withValues(alpha: 0.6)
            : (widget.isTournament && isLoser)
                ? AppTheme.pastelRose.withValues(alpha: 0.25)
                : AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWinner
              ? AppTheme.primaryMint
              : (widget.isTournament && isLoser)
                  ? AppTheme.pastelRoseDark.withValues(alpha: 0.35)
                  : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                teamTitle,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              if (isWinner)
                Text(
                  widget.isTournament ? 'WIN · 진출' : 'WIN',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.pastelMintDark),
                )
              else if (widget.isTournament && isLoser)
                const Text(
                  '탈락',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.pastelRoseDark),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...members.map(
            (m) => InkWell(
              onTap: isFinished ? null : () => onPlayerTap(m),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.getTierBgColor(m.tier),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        m.tier.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTierTextColor(m.tier),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        m.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: (widget.isTournament && isLoser) ? Colors.grey.shade600 : AppTheme.textDark,
                          decoration: (widget.isTournament && isLoser) ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isFinished)
                      const Icon(
                        Icons.swap_horiz_rounded,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 인라인 실시간 점수 입력창 (숫자 키보드 바로 작동)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                '점수: ',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              SizedBox(
                width: 56,
                height: 38,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primaryMint, width: 2),
                    ),
                  ),
                  onChanged: onScoreChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [기능 1] 선수 수동 교체 (Player Swap) 바텀시트 호출
  void _showPlayerSwapSheet({
    required BuildContext context,
    required GameMatch match,
    required Member initialTargetPlayer,
  }) {
    if (match.isFinished) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 완료된 경기는 데이터 안전을 위해 선수를 교체할 수 없습니다.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlayerSwapBottomSheet(
        match: match,
        initialTargetPlayer: initialTargetPlayer,
        restingMembers: widget.restingMembers,
        roundMatches: widget.roundMatches,
        memberMap: widget.memberMap,
      ),
    );
  }
}

/// [기능 1 구현체] 선수 수동 교체 바텀시트
/// - 휴식/대기 회원과 교체 (치환)
/// - 같은 코트 상대팀 선수 및 다른 대기 코트 선수와 1:1 맞바꿈 (Player Swap)
/// - 교체 시 예상 팀 급수합 실시간 비교 프리뷰 제공
class _PlayerSwapBottomSheet extends ConsumerStatefulWidget {
  final GameMatch match;
  final Member initialTargetPlayer;
  final List<Member> restingMembers;
  final List<GameMatch> roundMatches;
  final Map<String, Member> memberMap;

  const _PlayerSwapBottomSheet({
    required this.match,
    required this.initialTargetPlayer,
    required this.restingMembers,
    required this.roundMatches,
    required this.memberMap,
  });

  @override
  ConsumerState<_PlayerSwapBottomSheet> createState() => _PlayerSwapBottomSheetState();
}

class _PlayerSwapBottomSheetState extends ConsumerState<_PlayerSwapBottomSheet> {
  late String _currentTargetId;
  int _tabIndex = 0; // 0: 휴식/대기 회원 교체, 1: 1:1 선수 맞바꿈

  @override
  void initState() {
    super.initState();
    _currentTargetId = widget.initialTargetPlayer.id;
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final allFourPlayerIds = [...match.teamA, ...match.teamB];
    final currentTarget = widget.memberMap[_currentTargetId] ??
        Member(id: _currentTargetId, name: '선수');

    final isTargetInTeamA = match.teamA.contains(_currentTargetId);
    final currentTeamTitle = isTargetInTeamA ? 'TEAM A' : 'TEAM B';

    // 다른 대기 중인 코트 목록 (완료된 코트는 안전을 위해 제외)
    final otherPendingMatches = widget.roundMatches
        .where((m) => m.id != match.id && !m.isFinished)
        .toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: AppTheme.primaryDark, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${match.courtNumber}번 코트 선수 수동 교체',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '선택한 선수를 다른 선수나 대기 회원과 즉시 교체합니다.',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 1. 교체할 코트 내 선수 선택 (4명 칩)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. 코트에서 교체할 선수 선택',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: allFourPlayerIds.map((id) {
                      final m = widget.memberMap[id] ?? Member(id: id, name: '선수');
                      final isSelected = id == _currentTargetId;
                      final isA = match.teamA.contains(id);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isA ? 'A팀 ' : 'B팀 ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? Colors.white70 : AppTheme.textMuted,
                                ),
                              ),
                              Text(
                                '${m.name}(${m.tier.label})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryDark,
                          backgroundColor: Colors.grey.shade100,
                          onSelected: (val) {
                            if (val) setState(() => _currentTargetId = id);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelMint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: AppTheme.pastelMintDark),
                      const SizedBox(width: 6),
                      Text(
                        '현재 선택: $currentTeamTitle ${currentTarget.name} (${currentTarget.tier.label}, ${currentTarget.tierWeight}점)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.pastelMintDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. 탭 선택 (휴식/대기 회원 vs 1:1 선수 맞바꿈)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _tabIndex = 0),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _tabIndex == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _tabIndex == 0
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '대기/휴식 회원과 교체 (${widget.restingMembers.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _tabIndex == 0 ? AppTheme.primaryDark : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _tabIndex = 1),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _tabIndex == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _tabIndex == 1
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '선수 1:1 맞바꿈 (코트/팀 간)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _tabIndex == 1 ? AppTheme.primaryDark : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. 교체 대상 목록
          Expanded(
            child: _tabIndex == 0
                ? _buildRestingMembersList(context, match, currentTarget, isTargetInTeamA)
                : _buildSwapWithOtherPlayersList(context, match, currentTarget, isTargetInTeamA, otherPendingMatches),
          ),
        ],
      ),
    );
  }

  /// 탭 1: 휴식/대기 회원과 교체 (치환)
  Widget _buildRestingMembersList(
    BuildContext context,
    GameMatch match,
    Member currentTarget,
    bool isTargetInTeamA,
  ) {
    if (widget.restingMembers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 40, color: AppTheme.textMuted),
              SizedBox(height: 8),
              Text(
                '현재 라운드에 휴식 중인 회원이 없습니다.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              SizedBox(height: 4),
              Text(
                '상단의 [선수 1:1 맞바꿈] 탭에서 다른 선수와 자리를 변경해 보세요.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currentTeamIds = isTargetInTeamA ? match.teamA : match.teamB;
    final currentSum = currentTeamIds.fold<int>(
      0,
      (sum, id) => sum + (widget.memberMap[id]?.tierWeight ?? 1),
    );

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: widget.restingMembers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final restingMember = widget.restingMembers[index];

        // 교체 후 예상 팀 급수합 계산
        final newSum = currentSum - currentTarget.tierWeight + restingMember.tierWeight;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.getTierBgColor(restingMember.tier),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  restingMember.tier.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTierTextColor(restingMember.tier),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restingMember.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '교체 시 팀 급수합: $currentSum점 ➔ $newSum점',
                      style: TextStyle(
                        fontSize: 11,
                        color: newSum == currentSum ? AppTheme.pastelMintDark : AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final ok = ref.read(matchesProvider.notifier).swapPlayers(
                        targetMatchId: match.id,
                        targetPlayerId: _currentTargetId,
                        otherMatchId: null,
                        otherPlayerId: restingMember.id,
                      );
                  Navigator.pop(context);
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${currentTarget.name} ➔ ${restingMember.name} 선수 교체 및 급수합 재계산이 완료되었습니다!',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('교체 투입', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 탭 2: 1:1 선수 맞바꿈 (같은 코트 상대팀 or 다른 대기 코트)
  Widget _buildSwapWithOtherPlayersList(
    BuildContext context,
    GameMatch match,
    Member currentTarget,
    bool isTargetInTeamA,
    List<GameMatch> otherPendingMatches,
  ) {
    // 1) 같은 코트 내 상대팀 선수 목록
    final oppositeTeamIds = isTargetInTeamA ? match.teamB : match.teamA;
    final oppositeTeamTitle = isTargetInTeamA ? 'TEAM B' : 'TEAM A';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        // 같은 코트 상대팀과 맞바꿈 섹션
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.pastelMint.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryMint.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sync_alt_rounded, size: 16, color: AppTheme.pastelMintDark),
                  const SizedBox(width: 4),
                  Text(
                    '같은 코트 내 상대 팀 ($oppositeTeamTitle)과 맞바꿈',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.pastelMintDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...oppositeTeamIds.map((oppId) {
                final opp = widget.memberMap[oppId] ?? Member(id: oppId, name: '선수');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.getTierBgColor(opp.tier),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          opp.tier.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.getTierTextColor(opp.tier),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${opp.name} (${opp.tierWeight}점)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryDark,
                          side: const BorderSide(color: AppTheme.primaryDark),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final ok = ref.read(matchesProvider.notifier).swapPlayers(
                                targetMatchId: match.id,
                                targetPlayerId: _currentTargetId,
                                otherMatchId: match.id,
                                otherPlayerId: opp.id,
                              );
                          Navigator.pop(context);
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${currentTarget.name} ⇄ ${opp.name} 팀 맞바꿈이 완료되었습니다!',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('1:1 팀 맞바꿈', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 다른 대기 코트 선수들과 맞바꿈 섹션
        const Text(
          '다른 대기 중인 코트와 1:1 맞바꿈',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 6),

        if (otherPendingMatches.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Column(
              children: [
                Icon(Icons.lock_clock_rounded, size: 28, color: AppTheme.textMuted),
                SizedBox(height: 6),
                Text(
                  '맞바꿀 수 있는 다른 대기 코트가 없습니다.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                ),
                SizedBox(height: 2),
                Text(
                  '경기 완료된 코트는 기록 보호를 위해 교체 목록에서 자동으로 제외됩니다.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...otherPendingMatches.map((otherMatch) {
            final allOtherIds = [...otherMatch.teamA, ...otherMatch.teamB];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelYellow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${otherMatch.courtNumber}번 코트 (대기 중)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.pastelYellowDark,
                          ),
                        ),
                      ),
                      const Text(
                        '1:1 자리 교환',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...allOtherIds.map((pId) {
                    final p = widget.memberMap[pId] ?? Member(id: pId, name: '선수');
                    final isA = otherMatch.teamA.contains(pId);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.getTierBgColor(p.tier),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.tier.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getTierTextColor(p.tier),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${isA ? 'A팀 ' : 'B팀 '}${p.name} (${p.tierWeight}점)',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryDark,
                              side: const BorderSide(color: AppTheme.primaryDark),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              final ok = ref.read(matchesProvider.notifier).swapPlayers(
                                    targetMatchId: match.id,
                                    targetPlayerId: _currentTargetId,
                                    otherMatchId: otherMatch.id,
                                    otherPlayerId: p.id,
                                  );
                              Navigator.pop(context);
                              if (ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${match.courtNumber}코트 ${currentTarget.name} ⇄ ${otherMatch.courtNumber}코트 ${p.name} 맞바꿈이 완료되었습니다!',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: const Text('1:1 맞바꿈', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// [기능 2 구현체] 특별 매치 수동 생성 바텀시트
/// - 코트 번호 설정
/// - 출석 회원 중 4명을 선택하여 TEAM A(2명), TEAM B(2명) 직접 구성
/// - 실시간 급수합 밸런스 비교 프리뷰 (차이 점수 표시)
/// - 코트 투입 후 일반 게임과 동일하게 점수 기록 및 완료 처리
class _AddCustomMatchSheet extends ConsumerStatefulWidget {
  final GameSession session;
  final int selectedRound;
  final List<GameMatch> roundMatches;
  final List<Member> allMembers;

  const _AddCustomMatchSheet({
    required this.session,
    required this.selectedRound,
    required this.roundMatches,
    required this.allMembers,
  });

  @override
  ConsumerState<_AddCustomMatchSheet> createState() => _AddCustomMatchSheetState();
}

class _AddCustomMatchSheetState extends ConsumerState<_AddCustomMatchSheet> {
  late int _courtNumber;
  final List<String> _teamAIds = [];
  final List<String> _teamBIds = [];

  @override
  void initState() {
    super.initState();
    // 기존 코트 번호의 최댓값 + 1
    final existingCourtNums = widget.roundMatches.map((m) => m.courtNumber).toList();
    _courtNumber = existingCourtNums.isEmpty
        ? 1
        : existingCourtNums.reduce((a, b) => a > b ? a : b) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final memberMap = {for (final m in widget.allMembers) m.id: m};

    // 현재 라운드 출전 중인 선수 ID Set
    final playingPlayerIds = widget.roundMatches.expand((m) => m.allPlayerIds).toSet();

    // 출석 회원 전체 목록 (급수 내림차순 정렬)
    final attendees = widget.session.activeAttendees
        .where((id) => memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList()
      ..sort((a, b) => b.tierWeight.compareTo(a.tierWeight));

    // 급수합 계산
    final teamAWeight = _teamAIds.fold<int>(
      0,
      (sum, id) => sum + (memberMap[id]?.tierWeight ?? 0),
    );
    final teamBWeight = _teamBIds.fold<int>(
      0,
      (sum, id) => sum + (memberMap[id]?.tierWeight ?? 0),
    );
    final diff = (teamAWeight - teamBWeight).abs();

    final isReady = _teamAIds.length == 2 && _teamBIds.length == 2;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_circle_outline, color: AppTheme.primaryDark, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.selectedRound}R 특별 매치 수동 추가',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '원하는 선수 4명을 직접 배치하여 코트에 투입합니다.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. 코트 번호 설정
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '코트 번호 지정',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: _courtNumber > 1
                              ? () => setState(() => _courtNumber--)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.pastelYellow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$_courtNumber번 코트',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.pastelYellowDark,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          onPressed: () => setState(() => _courtNumber++),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 2. 대진 구성 프리뷰 카드 (TEAM A vs TEAM B & 실시간 급수합)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // TEAM A 박스
                          Expanded(
                            child: _buildTeamSelectBox(
                              teamTitle: 'TEAM A (최대 2명)',
                              playerIds: _teamAIds,
                              memberMap: memberMap,
                              teamWeight: teamAWeight,
                              onRemove: (id) => setState(() => _teamAIds.remove(id)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              children: [
                                const Text(
                                  'VS',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: diff <= 1 ? AppTheme.pastelMint : AppTheme.pastelCoral,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '차이 $diff점',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: diff <= 1 ? AppTheme.pastelMintDark : AppTheme.pastelCoralDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // TEAM B 박스
                          Expanded(
                            child: _buildTeamSelectBox(
                              teamTitle: 'TEAM B (최대 2명)',
                              playerIds: _teamBIds,
                              memberMap: memberMap,
                              teamWeight: teamBWeight,
                              onRemove: (id) => setState(() => _teamBIds.remove(id)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 3. 출석 회원 선택 안내 및 목록
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '출석 회원 터치하여 팀 배정',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    Text(
                      '터치 시 A팀 ➔ B팀 자동 배정',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                ...attendees.map((m) {
                  final inA = _teamAIds.contains(m.id);
                  final inB = _teamBIds.contains(m.id);
                  final isAlreadyInMatch = playingPlayerIds.contains(m.id);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: inA || inB
                          ? AppTheme.primaryMint.withValues(alpha: 0.12)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: inA || inB
                            ? AppTheme.primaryMint
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.getTierBgColor(m.tier),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          m.tier.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.getTierTextColor(m.tier),
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          if (isAlreadyInMatch && !inA && !inB)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '타 코트 출전 중',
                                style: TextStyle(fontSize: 9, color: Colors.black54),
                              ),
                            )
                          else if (!isAlreadyInMatch && !inA && !inB)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.pastelMint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '휴식 중',
                                style: TextStyle(fontSize: 9, color: AppTheme.pastelMintDark, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      trailing: inA
                          ? const Chip(
                              label: Text('A팀 배정됨', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                              backgroundColor: AppTheme.primaryDark,
                            )
                          : inB
                              ? const Chip(
                                  label: Text('B팀 배정됨', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  backgroundColor: AppTheme.primaryMint,
                                )
                              : const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.textMuted),
                      onTap: () {
                        if (inA) {
                          setState(() => _teamAIds.remove(m.id));
                        } else if (inB) {
                          setState(() => _teamBIds.remove(m.id));
                        } else {
                          if (_teamAIds.length < 2) {
                            setState(() => _teamAIds.add(m.id));
                          } else if (_teamBIds.length < 2) {
                            setState(() => _teamBIds.add(m.id));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('팀당 2명씩 총 4명이 이미 모두 선택되었습니다. 제외 후 다시 선택하세요.'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

          // 하단 코트 투입 버튼
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isReady ? AppTheme.primaryDark : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.sports_tennis_rounded),
                label: Text(
                  isReady
                      ? '$_courtNumber번 코트에 특별 매치 투입 (A:$teamAWeight vs B:$teamBWeight)'
                      : '선수 4명을 모두 선택해 주세요 (${_teamAIds.length + _teamBIds.length}/4)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: isReady
                    ? () {
                        final customMatch = GameMatch(
                          id: 'custom_r${widget.selectedRound}_c${_courtNumber}_${DateTime.now().millisecondsSinceEpoch}',
                          sessionId: widget.session.id,
                          round: widget.selectedRound,
                          courtNumber: _courtNumber,
                          teamA: List.from(_teamAIds),
                          teamB: List.from(_teamBIds),
                          status: MatchStatus.playing,
                        );

                        ref.read(matchesProvider.notifier).addCustomMatch(customMatch);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '$_courtNumber번 코트에 특별 매치가 즉시 추가 및 가동되었습니다!',
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamSelectBox({
    required String teamTitle,
    required List<String> playerIds,
    required Map<String, Member> memberMap,
    required int teamWeight,
    required ValueChanged<String> onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                teamTitle,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              Text(
                '합: $teamWeight점',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (playerIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('선수를 선택하세요', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ),
            )
          else
            ...playerIds.map((id) {
              final m = memberMap[id] ?? Member(id: id, name: '선수');
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.getTierBgColor(m.tier),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        m.tier.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTierTextColor(m.tier),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        m.name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => onRemove(id),
                      child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
