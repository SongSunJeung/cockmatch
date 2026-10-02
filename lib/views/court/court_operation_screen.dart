import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../widgets/tournament_bracket_tree_widget.dart';

/// [화면 3] 대진표 및 실시간 코트 운영 화면
/// - 메인 화면 인라인 직접 점수 입력 (숫자 키패드 TextField, 실시간 자동 저장)
/// - 원터치 [경기 완료] 토글/체크 버튼
/// - 라운드별 경기 탭 (1R, 2R, 3R...) 및 알고리즘 기반 즉시 자동 생성
/// - 부상/조퇴 원클릭 대체 선수 치환
/// - 실시간 랭킹(다승->득실차->다득점->승자승) 팝업 모달
/// - 비회원 웹 링크 복사
class CourtOperationScreen extends ConsumerStatefulWidget {
  const CourtOperationScreen({super.key});

  @override
  ConsumerState<CourtOperationScreen> createState() => _CourtOperationScreenState();
}

class _CourtOperationScreenState extends ConsumerState<CourtOperationScreen> {
  /// [1. 상단 설정/통계 영역 접이식(Accordion) 전환] 기본 접힌 상태(Collapsed) 유지
  bool _isSummaryExpanded = false;

  @override
  Widget build(BuildContext context) {
    final currentClub = ref.watch(currentClubProvider);
    final session = ref.watch(sessionProvider);
    final pagePalette = AppTheme.getPagePalette(2);

    if (session == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. 최상단 AppBar ([☰] + '대진표' + [○ ○ ●] 고정 인디케이터)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTheme.buildMainAppBarRow(
                      context: context,
                      currentIndex: 2,
                      actions: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.pastelPeriwinkle,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currentClub.clubName,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: pagePalette.softTint,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '모임 대기 중',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: pagePalette.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '진행 중인 모임 세션이 없습니다',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
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
                            color: pagePalette.softTint,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Icon(
                            Icons.sports_tennis_rounded,
                            size: 44,
                            color: pagePalette.primary,
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
                          '[일정/모임] 탭에서 새 모임을 시작하고 출석 인원을 확정하면 실시간 코트 대진표가 생성됩니다.',
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
                            backgroundColor: pagePalette.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.checklist_rtl_rounded, size: 20),
                          label: const Text(
                            '일정/모임에서 새 모임 시작하기',
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

    // 현재 라운드 출전 선수, 휴식(또는 부전승 대기) 선수, 탈락 선수, 출석(출전 가능) 선수 계산
    final playingPlayerIds = roundMatches.expand((m) => m.allPlayerIds).toSet();
    final playingMembers = playingPlayerIds
        .where((id) => memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList();
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
    final activeCourtNumbers = List.generate(session.courtCount, (i) => startCourt + i);
    final occupiedCourtNumbers = roundMatches.map((m) => m.courtNumber).toSet();
    final emptyCourtNumbers = activeCourtNumbers
        .where((c) => !occupiedCourtNumbers.contains(c))
        .toList();

    // 이전 완료된 라운드인지 여부 (과거 완료 라운드는 빈 슬롯을 강제로 표시하지 않고 당시 경기 기록만 보존 표시)
    final maxRound = existingRounds.isEmpty ? 1 : existingRounds.last;
    final isPastCompletedRound = selectedRound < maxRound &&
        roundMatches.isNotEmpty &&
        roundMatches.every((m) => m.isFinished);

    // 현재 라운드에 표시할 코트 번호 목록 (운영 코트 범위 내로 엄격히 제한하여 초과 유령 슬롯 방지)
    final displayCourtNumbers = isPastCompletedRound
        ? (roundMatches
            .map((m) => m.courtNumber)
            .where((c) => activeCourtNumbers.contains(c))
            .toSet()
            .toList()
          ..sort())
        : activeCourtNumbers;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // 1. 최상단 AppBar ([☰] + '대진표' + [○ ○ ●] 고정 인디케이터) & 1줄 미니 툴바 (코트 변경 칩 + 모임 경기 전적 칩)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTheme.buildMainAppBarRow(
                      context: context,
                      currentIndex: 2,
                      actions: [
                        IconButton(
                          key: const Key('court_header_live_viewer_button'),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.live_tv_rounded, color: pagePalette.primary, size: 20),
                          tooltip: '실시간 전광판 웹뷰어',
                          onPressed: () {
                            ref.read(currentTabProvider.notifier).setTab(3);
                          },
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.leaderboard_rounded, color: AppTheme.textDark, size: 20),
                          tooltip: '실시간 랭킹 순위표',
                          onPressed: () => _showRankingsDialog(context, ref, allMatches, allMembers),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.share_rounded, color: AppTheme.textDark, size: 19),
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: pagePalette.softTint,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            currentClub.clubName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: pagePalette.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '운영 코트 ${session.courtCount}면${!isPastCompletedRound && emptyCourtNumbers.isNotEmpty ? ' (빈 코트 ${emptyCourtNumbers.length}면)' : ''} · ${session.matchFormat.label} · ${session.matchMode.label}${session.partnerMode == PartnerMode.fixedAll ? ' · 전원 고정 페어' : session.fixedPairs.isNotEmpty ? ' · 고정 페어 ${session.fixedPairs.length}팀' : ''}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          key: const Key('court_end_game_button'),
                          onTap: () {
                            if (session.isGameEnded) {
                              _showGameEndedStatusDialog(context, ref, session);
                            } else {
                              _showEndGameMatchesConfirmDialog(context, ref, session);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: session.isGameEnded ? Colors.amber.shade50 : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: session.isGameEnded ? Colors.amber.shade400 : AppTheme.errorRed.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  session.isGameEnded ? Icons.check_circle_rounded : Icons.sports_score_rounded,
                                  size: 13,
                                  color: session.isGameEnded ? Colors.amber.shade800 : AppTheme.errorRed,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  session.isGameEnded ? '경기 종료됨' : '오늘 경기 종료',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: session.isGameEnded ? Colors.amber.shade900 : AppTheme.errorRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (session.isGameEnded)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.flag_rounded, size: 16, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '오늘 경기가 공식 종료되었습니다. (웹 뷰어: 경기 결과 확정)\n회비 정산 및 참석 관리는 [모임/행사] 탭에서 계속 진행할 수 있습니다.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade900,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key('court_banner_resume_button'),
                              onPressed: () => _showResumeGameConfirmDialog(context, ref),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('경기 재개', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 2. 상단 설정/통계 영역 접이식(Accordion) 카드 (기본 Collapsed 상태)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: pagePalette.softTint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: pagePalette.borderTint),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isTournament
                                  ? '🏆 토너먼트 $selectedRound라운드'
                                  : '라운드 $selectedRound 운영 중',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: pagePalette.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '출전 ${playingPlayerIds.length} · 휴식 ${restingMembers.length} · 출석 ${session.activeAttendees.length}명',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: pagePalette.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            key: const Key('toggle_operation_summary_button'),
                            onTap: () => setState(() => _isSummaryExpanded = !_isSummaryExpanded),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.settings,
                                    size: 13,
                                    color: pagePalette.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    _isSummaryExpanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: 16,
                                    color: pagePalette.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isSummaryExpanded) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricItem(
                                '출전 인원',
                                '${playingPlayerIds.length}명',
                                '배정 ${roundMatches.length}/${session.courtCount}코트',
                                onTap: () => _showRoundMemberListPopup(
                                  context: context,
                                  title: '출전 인원 명단',
                                  subtitle: '$selectedRound라운드 코트 배정 선수 (${playingMembers.length}명)',
                                  members: playingMembers,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (isTournament)
                              Expanded(
                                child: _buildMetricItem(
                                  '탈락 인원',
                                  '${eliminatedMembers.length}명',
                                  '패배 팀 자동 탈락',
                                  onTap: () => _showRoundMemberListPopup(
                                    context: context,
                                    title: '탈락 인원 명단',
                                    subtitle: '토너먼트 패배 탈락 선수 (${eliminatedMembers.length}명)',
                                    members: eliminatedMembers,
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: _buildMetricItem(
                                  '휴식 인원',
                                  '${restingMembers.length}명',
                                  '다음 라운드 우선',
                                  onTap: () => _showRoundMemberListPopup(
                                    context: context,
                                    title: '휴식 인원 명단',
                                    subtitle: '$selectedRound라운드 대기/휴식 선수 (${restingMembers.length}명)',
                                    members: restingMembers,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildMetricItem(
                                '코트 수',
                                '${session.courtCount}코트',
                                '터치하여 코트 수 설정',
                                key: const Key('open_court_change_dialog_button'),
                                onTap: () => _showCourtCountChangeDialog(context, ref, memberMap),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // 3. 라운드 선택 탭 ('1 라운드' 옆 '+ 라운드 추가' 첫 화면 즉시 노출)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...existingRounds.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: InkWell(
                            onTap: () {
                              ref.read(selectedRoundProvider.notifier).setRound(r);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: selectedRound == r ? pagePalette.primary : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedRound == r ? pagePalette.secondary : Colors.grey.shade200,
                                ),
                              ),
                              child: Text(
                                '$r 라운드',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: selectedRound == r ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // '+ 라운드 추가' 버튼 (가로 스크롤 뒤로 숨지 않고 첫 화면에서 즉시 노출)
                      InkWell(
                        key: const Key('court_add_round_button'),
                        onTap: () {
                          if (session.isGameEnded) {
                            _showGameEndedStatusDialog(context, ref, session);
                            return;
                          }
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
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: pagePalette.softTint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: pagePalette.borderTint),
                          ),
                          child: Text(
                            '+ 라운드 추가',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: pagePalette.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3-2. 핵심 운영 버튼 외부 상시 노출 바 ([특별 매치 추가] / [남은 라운드 재편성] / [대진표 전체 재편성])
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('court_add_custom_match_button'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: pagePalette.primary,
                          side: BorderSide(color: pagePalette.borderTint),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                        ),
                        icon: Icon(Icons.add_circle_outline, size: 12, color: pagePalette.primary),
                        label: const Text(
                          '특별 매치 추가',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          if (session.isGameEnded) {
                            _showGameEndedStatusDialog(context, ref, session);
                            return;
                          }
                          _showAddCustomMatchModal(
                            context,
                            ref,
                            session,
                            selectedRound,
                            roundMatches,
                            allMembers,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('court_reshuffle_remaining_button'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: pagePalette.primary,
                          side: BorderSide(color: pagePalette.borderTint),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                        ),
                        icon: const Icon(Icons.sync_rounded, size: 12),
                        label: const Text(
                          '남은 라운드 재편성',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          if (session.isGameEnded) {
                            _showGameEndedStatusDialog(context, ref, session);
                            return;
                          }
                          _showReshuffleRemainingConfirmDialog(
                            context,
                            ref,
                            selectedRound,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('court_reset_and_regenerate_button'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.errorRed,
                          side: BorderSide(color: AppTheme.errorRed.withValues(alpha: 0.45)),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                        ),
                        icon: const Icon(Icons.sync_rounded, size: 12),
                        label: const Text(
                          '대진표 전체 재편성',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          if (session.isGameEnded) {
                            _showGameEndedStatusDialog(context, ref, session);
                            return;
                          }
                          _showResetAndRegenerateConfirmDialog(context, ref, session);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. 휴식(또는 부전승) 및 토너먼트 탈락 선수 안내 바 (초슬림 1줄)
            if (restingMembers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isTournament && selectedRound > 1
                              ? Icons.emoji_events_outlined
                              : Icons.pause_circle_outline,
                          size: 15,
                          color: isTournament && selectedRound > 1
                              ? AppTheme.pastelMintDark
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isTournament && selectedRound > 1 ? '부전승 대기: ' : '현재 휴식 중: ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isTournament && selectedRound > 1
                                ? AppTheme.pastelMintDark
                                : AppTheme.textMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            restingMembers.map((m) => '${m.name}(${m.tier.label})').join(', '),
                            style: const TextStyle(fontSize: 11, color: AppTheme.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (isTournament)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('open_tournament_tree_dialog_button'),
                      onTap: () => _showTournamentBracketTreeDialog(
                        context,
                        allMatches,
                        memberMap,
                        courtCount: session.courtCount,
                        startCourtNumber: session.startCourtNumber,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(vertical: 10.5, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF9DE), Color(0xFFFEEDAA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.pastelYellowDark.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.pastelYellowDark.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.account_tree_rounded,
                              size: 17,
                              color: AppTheme.pastelYellowDark,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '🏆 전체 토너먼트 트리 보기',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF6B4E00),
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: Color(0xFF8C6500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 5. 코트별 경기 카드 목록 (배정된 코트 매치 카드 + 빈 코트 슬롯 카드)
            if (roundMatches.isEmpty && displayCourtNumbers.isEmpty)
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
                            label: const Text('특별 매치 추가'),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final courtNum = displayCourtNumbers[index];
                      final matchesOnCourt = roundMatches.where((m) {
                        final effectiveCourt = activeCourtNumbers.contains(m.courtNumber)
                            ? m.courtNumber
                            : startCourt + (((m.bracketMatchIndex ?? m.courtNumber) - 1) % session.courtCount);
                        return effectiveCourt == courtNum;
                      }).toList();

                      if (matchesOnCourt.isEmpty) {
                        return _buildEmptyCourtSlotCard(
                          context: context,
                          ref: ref,
                          session: session,
                          selectedRound: selectedRound,
                          courtNumber: courtNum,
                          roundMatches: roundMatches,
                          allMembers: allMembers,
                          restingMembers: restingMembers,
                          isTournament: isTournament,
                        );
                      }

                      return Column(
                        children: matchesOnCourt
                            .map(
                              (match) => CourtMatchCard(
                                key: ValueKey(match.id),
                                match: match,
                                memberMap: memberMap,
                                restingMembers: restingMembers,
                                roundMatches: roundMatches,
                                isTournament: isTournament,
                              ),
                            )
                            .toList(),
                      );
                    },
                    childCount: displayCourtNumbers.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEndGameMatchesConfirmDialog(BuildContext context, WidgetRef ref, GameSession session) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sports_score_rounded, color: AppTheme.errorRed, size: 24),
            SizedBox(width: 8),
            Text('오늘 경기 종료', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '오늘 진행된 경기를 공식 종료하고 결과를 확정하시겠습니까?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
            ),
            SizedBox(height: 10),
            Text(
              '• 대진표 작성이 마감되며, 실시간 웹 뷰어 및 공유 링크 화면이 \'경기 결과\'로 확정되어 노출됩니다.\n• 모임 자체가 완전 마감되는 것은 아니므로, [모임/행사] 탭에서 미납 회비 정산 및 출석부 관리를 계속 진행하실 수 있습니다.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            key: const Key('confirm_end_game_matches_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(sessionProvider.notifier).endGameMatches();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('오늘 경기가 종료되었습니다. 웹 뷰어 화면이 [경기 결과]로 전환되었습니다.'),
                  backgroundColor: AppTheme.primaryDark,
                ),
              );
            },
            child: const Text('경기 종료 및 결과 확정', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showGameEndedStatusDialog(BuildContext context, WidgetRef ref, GameSession session) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.amber.shade800, size: 24),
            const SizedBox(width: 8),
            const Text('경기 종료 상태 안내', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Text(
                '현재 오늘 경기가 공식 종료된 상태입니다.\n웹 뷰어에는 [경기 결과]로 확정 노출되고 있습니다.',
                style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• 회비 미납 관리나 최종 마감은 [모임/행사] 화면에서 진행하세요.\n• 추가 경기를 더 편성해야 한다면 [경기 다시 재개하기]를 누르세요.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.45),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _showResumeGameConfirmDialog(context, ref);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('경기 다시 재개하기'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMint,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(currentTabProvider.notifier).setTab(1);
            },
            child: const Text('모임/정산 관리로 이동', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showResumeGameConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('경기를 다시 재개하시겠습니까?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
          '경기를 재개하면 대진표 작성이 다시 활성화되며, 웹 뷰어도 실시간 LIVE 화면으로 복귀합니다.',
          style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            key: const Key('confirm_resume_game_matches_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(sessionProvider.notifier).resumeGameMatches();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('경기가 재개되었습니다. 대진표 추가 및 실시간 진행이 활성화되었습니다.'),
                  backgroundColor: AppTheme.primaryDark,
                ),
              );
            },
            child: const Text('경기 재개', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// [2. 코트 설정 콤팩트화] `[🏟️ N코트 변경 ⚙️]` 클릭 시 열리는 실시간 코트 수 변경 다이얼로그
  void _showCourtCountChangeDialog(
    BuildContext parentContext,
    WidgetRef ref,
    Map<String, Member> memberMap,
  ) {
    showDialog(
      context: parentContext,
      builder: (dialogCtx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final liveSession = dialogRef.watch(sessionProvider);
          if (liveSession == null) return const SizedBox.shrink();
          final liveMatches = dialogRef.watch(matchesProvider);
          final liveSelectedRound = dialogRef.watch(selectedRoundProvider);
          final liveRoundMatches = liveMatches
              .where((m) => m.round == liveSelectedRound)
              .toList()
            ..sort((a, b) => a.courtNumber.compareTo(b.courtNumber));
          final startCourt = liveSession.startCourtNumber;
          final activeCourts = List.generate(liveSession.courtCount, (i) => startCourt + i);
          final occupiedCourts = liveRoundMatches.map((m) => m.courtNumber).toSet();
          final emptyCourts = activeCourts.where((c) => !occupiedCourts.contains(c)).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Row(
              children: [
                Icon(Icons.stadium_rounded, color: AppTheme.primaryDark, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '실시간 운영 코트 변경',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelYellow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '운영 코트 ${liveSession.courtCount}면',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.pastelYellowDark,
                        ),
                      ),
                    ),
                    if (emptyCourts.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelMint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '빈 코트 ${emptyCourts.length}면',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.pastelMintDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '코트 추가 시 빈 코트 슬롯이 즉시 생성되며, 코트 축소 시 빈 코트부터 안전하게 제거됩니다.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('decrease_court_button'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: liveSession.courtCount > 1
                              ? AppTheme.pastelCoralDark
                              : Colors.grey,
                          side: BorderSide(
                            color: liveSession.courtCount > 1
                                ? AppTheme.pastelCoralDark.withValues(alpha: 0.45)
                                : Colors.grey.shade300,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                        label: const Text(
                          '- 코트 축소',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        onPressed: () {
                          final activeInRound = liveRoundMatches.where((m) => !m.isFinished).toList();
                          if (liveSession.courtCount > 1 &&
                              emptyCourts.isEmpty &&
                              activeInRound.isNotEmpty) {
                            Navigator.pop(dialogCtx);
                          }
                          _handleDecreaseCourt(
                            context: parentContext,
                            ref: ref,
                            session: liveSession,
                            selectedRound: liveSelectedRound,
                            roundMatches: liveRoundMatches,
                            emptyCourtNumbers: emptyCourts,
                            memberMap: memberMap,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        key: const Key('increase_court_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryMint,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                        label: const Text(
                          '+ 코트 추가',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        onPressed: () => _handleIncreaseCourt(
                          context: parentContext,
                          ref: ref,
                          session: liveSession,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text(
                  '닫기',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// [🏆 전체 트리 보기] 팝업 다이얼로그 (InteractiveViewer 2D 줌/팬 지원)
  void _showTournamentBracketTreeDialog(
    BuildContext context,
    List<GameMatch> matches,
    Map<String, Member> memberMap, {
    int courtCount = 5,
    int startCourtNumber = 1,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 960,
          height: 640,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelYellow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: AppTheme.pastelYellowDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '토너먼트 전체 브래킷 (트리 보기)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Text(
                          '승자 승급 및 실시간 스코어가 즉시 반영됩니다 (핀치 줌 & 자유 이동 가능)',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: TournamentBracketTreeWidget(
                    matches: matches,
                    memberMap: memberMap,
                    courtCount: courtCount,
                    startCourtNumber: startCourtNumber,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [+ 코트 추가] 핸들러:
  /// - 현재 라운드에 새 빈 코트 슬롯을 즉시 생성
  /// - 다음 라운드 자동 생성 시 늘어난 코트 수에 맞춰 출전 인원 자동 확대
  void _handleIncreaseCourt({
    required BuildContext context,
    required WidgetRef ref,
    required GameSession session,
  }) {
    if (session.courtCount >= 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 15개 코트까지만 운영할 수 있습니다.')),
      );
      return;
    }

    final newCourtNumber = ref.read(matchesProvider.notifier).addCourtSlot();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.primaryDark,
        content: Text(
          '✅ $newCourtNumber번 빈 코트 슬롯이 추가되었습니다! (현재 총 ${session.courtCount + 1}면 · 다음 라운드부터 출전 인원 자동 확대)',
        ),
      ),
    );
  }

  /// [- 코트 축소] 핸들러:
  /// - 배정된 경기가 없는 빈 코트가 있으면 우선적으로 즉시 제거
  /// - 모든 코트에 진행/배정 중인 경기가 있으면 확인 다이얼로그를 띄워 대기 인원 전환 또는 다른 빈 슬롯으로 이동 유도
  /// - 이전 완료된 라운드의 경기 기록은 손실 없이 안전하게 보존
  void _handleDecreaseCourt({
    required BuildContext context,
    required WidgetRef ref,
    required GameSession session,
    required int selectedRound,
    required List<GameMatch> roundMatches,
    required List<int> emptyCourtNumbers,
    required Map<String, Member> memberMap,
  }) {
    if (session.courtCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 최소 1개 이상의 운영 코트가 유지되어야 합니다.')),
      );
      return;
    }

    // 1. 배정된 경기가 없는 빈 코트가 있으면 우선적으로 제거
    if (emptyCourtNumbers.isNotEmpty) {
      final removedCourt = ref.read(matchesProvider.notifier).removeEmptyCourtSlot(
            currentRound: selectedRound,
          );
      if (removedCourt != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text(
              '✅ 배정된 경기가 없는 빈 $removedCourt번 코트가 우선 제거되었습니다. (현재 ${session.courtCount - 1}면 운영)',
            ),
          ),
        );
        return;
      }
    }

    // 2. 현재 라운드의 미완료(진행/배정 중) 경기 확인
    final activeMatches = roundMatches.where((m) => !m.isFinished).toList()
      ..sort((a, b) => a.courtNumber.compareTo(b.courtNumber));

    // 현재 라운드의 모든 경기가 이미 완료(finished)된 경우: 완료 기록은 보존하고 코트 수만 축소
    if (activeMatches.isEmpty) {
      final nextCount = session.courtCount - 1;
      ref.read(sessionProvider.notifier).updateCourtCount(nextCount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primaryDark,
          content: Text(
            '✅ 완료된 라운드 경기 기록은 안전하게 보존되며, 운영 코트가 $nextCount면으로 축소되었습니다.',
          ),
        ),
      );
      return;
    }

    // 3. 진행/배정 중인 경기가 있는 코트를 닫을 경우 확인 다이얼로그 호출
    _showReduceCourtConfirmDialog(
      context: context,
      ref: ref,
      session: session,
      selectedRound: selectedRound,
      activeMatches: activeMatches,
      roundMatches: roundMatches,
      memberMap: memberMap,
    );
  }

  /// 진행/배정 중인 경기가 있는 코트를 축소할 때 띄우는 확인 다이얼로그
  /// - [대기 인원으로 전환 후 코트 축소] 또는 [다른 빈 슬롯으로 이동] 선택 지원
  void _showReduceCourtConfirmDialog({
    required BuildContext context,
    required WidgetRef ref,
    required GameSession session,
    required int selectedRound,
    required List<GameMatch> activeMatches,
    required List<GameMatch> roundMatches,
    required Map<String, Member> memberMap,
  }) {
    String selectedMatchId = activeMatches.last.id;
    final occupiedCourts = roundMatches.map((m) => m.courtNumber).toSet();
    final startCourt = session.startCourtNumber;
    final endCourt = startCourt + session.courtCount - 1;

    // 이동 가능한 빈 코트 번호 후보 계산 (1번 ~ endCourt + 2 중 현재 점유되지 않은 번호)
    final candidateEmptyCourts = <int>[];
    for (int c = 1; c <= endCourt + 2; c++) {
      if (!occupiedCourts.contains(c)) {
        candidateEmptyCourts.add(c);
      }
    }
    int targetEmptyCourt = candidateEmptyCourts.isNotEmpty
        ? candidateEmptyCourts.first
        : endCourt + 1;

    String formatTeams(GameMatch m) {
      final teamA = m.teamA.map((id) => memberMap[id]?.name ?? '선수').join('·');
      final teamB = m.teamB.map((id) => memberMap[id]?.name ?? '선수').join('·');
      return '$teamA vs $teamB';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final targetMatch = activeMatches.firstWhere(
            (m) => m.id == selectedMatchId,
            orElse: () => activeMatches.last,
          );

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppTheme.pastelCoralDark, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '진행/배정 중인 코트 축소 확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '현재 모든 운영 코트에 경기가 배정되어 있습니다.\n닫을 코트를 선택하고 배정된 선수 처리 방식을 선택해 주세요.',
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelMint.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 15, color: AppTheme.pastelMintDark),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '이전 완료된 라운드 및 완료된 경기 기록은 손실 없이 안전하게 보존됩니다.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.pastelMintDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '축소(닫기) 대상 코트 선택',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 6),
                    ...activeMatches.map((m) {
                      final isSelected = m.id == targetMatch.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setDialogState(() => selectedMatchId = m.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.pastelCoral.withValues(alpha: 0.35)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.pastelCoralDark
                                    : Colors.grey.shade300,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 16,
                                  color: isSelected ? AppTheme.pastelCoralDark : AppTheme.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.pastelYellow,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${m.courtNumber}번 코트',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.pastelYellowDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    formatTeams(m),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              '다른 빈 코트 슬롯으로 경기 이동 시 코트 번호:',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          DropdownButton<int>(
                            value: targetEmptyCourt,
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            items: candidateEmptyCourts
                                .map(
                                  (c) => DropdownMenuItem<int>(
                                    value: c,
                                    child: Text(
                                      '빈 $c번 코트',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primaryDark,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => targetEmptyCourt = val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              OutlinedButton.icon(
                key: const Key('reduce_court_move_slot_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryDark,
                  side: const BorderSide(color: AppTheme.primaryDark),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.swap_calls_rounded, size: 16),
                label: Text('빈 $targetEmptyCourt번 슬롯으로 이동'),
                onPressed: () {
                  final oldCourt = targetMatch.courtNumber;
                  ref.read(matchesProvider.notifier).moveMatchToEmptyCourtAndReduce(
                        matchId: targetMatch.id,
                        targetEmptyCourt: targetEmptyCourt,
                      );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryDark,
                      content: Text(
                        '✅ $oldCourt번 코트 경기가 빈 $targetEmptyCourt번 슬롯으로 이동되고 코트가 축소되었습니다.',
                      ),
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                key: const Key('reduce_court_to_waiting_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.pastelCoralDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
                label: const Text('대기 인원으로 전환 후 축소'),
                onPressed: () {
                  final closedCourt = targetMatch.courtNumber;
                  ref.read(matchesProvider.notifier).cancelMatchAndReduceCourt(
                        matchId: targetMatch.id,
                        reduceCourtCount: true,
                      );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryDark,
                      content: Text(
                        '✅ $closedCourt번 코트가 축소되고 배정되었던 선수 4명이 대기(휴식) 인원으로 전환되었습니다.',
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 빈 코트 슬롯 카드 위젯 (코트 추가(+) 등으로 현재 라운드에 비어 있는 코트 슬롯)
  Widget _buildEmptyCourtSlotCard({
    required BuildContext context,
    required WidgetRef ref,
    required GameSession session,
    required int selectedRound,
    required int courtNumber,
    required List<GameMatch> roundMatches,
    required List<Member> allMembers,
    required List<Member> restingMembers,
    required bool isTournament,
  }) {
    final canAutoAssignWaiting = !isTournament && restingMembers.length >= 4;

    return Container(
      key: ValueKey('empty_court_${selectedRound}_$courtNumber'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryMint.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelMint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$courtNumber번 코트',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.pastelMintDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelYellow.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '빈 코트 슬롯',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.pastelYellowDark,
                      ),
                    ),
                  ),
                ],
              ),
              if (session.courtCount > 1)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final removed = ref.read(matchesProvider.notifier).removeEmptyCourtSlot(
                          currentRound: selectedRound,
                          targetEmptyCourt: courtNumber,
                        );
                    if (removed != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('빈 $courtNumber번 코트 슬롯이 닫혔습니다. (현재 ${session.courtCount - 1}면 운영)'),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 13, color: AppTheme.textMuted),
                        SizedBox(width: 3),
                        Text(
                          '빈 코트 닫기',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_box_outlined, size: 18, color: AppTheme.pastelMintDark),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '배정된 경기가 없는 빈 코트 슬롯입니다',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  canAutoAssignWaiting
                      ? '수동 매치를 직접 추가하거나 현재 휴식 중인 대기 인원(${restingMembers.length}명)에서 4명을 자동 배정할 수 있습니다.'
                      : '수동 매치를 직접 추가할 수 있으며, 다음 라운드 대진 자동 생성 시에는 이 코트에도 경기가 자동 배정됩니다.',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: ValueKey('empty_court_manual_add_$courtNumber'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryDark,
                        side: const BorderSide(color: AppTheme.primaryDark),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                      label: Text(
                        '$courtNumber번 코트 수동 매치 추가',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _showAddCustomMatchModal(
                        context,
                        ref,
                        session,
                        selectedRound,
                        roundMatches,
                        allMembers,
                        initialCourtNumber: courtNumber,
                      ),
                    ),
                    if (!isTournament)
                      ElevatedButton.icon(
                        key: ValueKey('empty_court_auto_assign_$courtNumber'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canAutoAssignWaiting
                              ? AppTheme.primaryMint
                              : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                        label: Text(
                          '대기 인원 4명 자동 배정 (${restingMembers.length}명 대기)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        onPressed: canAutoAssignWaiting
                            ? () {
                                final assigned = ref
                                    .read(matchesProvider.notifier)
                                    .autoAssignWaitingToEmptyCourt(
                                      round: selectedRound,
                                      courtNumber: courtNumber,
                                    );
                                if (assigned != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppTheme.primaryDark,
                                      content: Text(
                                        '✅ 빈 $courtNumber번 코트에 대기 인원 4명이 즉시 배정되었습니다!',
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [남은 라운드 재편성] 클릭 시 확인 경고 팝업
  void _showReshuffleRemainingConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    int selectedRound,
  ) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.autorenew_rounded, color: AppTheme.primaryDark, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '남은 라운드 재편성',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          '진행 중/완료된 경기는 유지되며, 대기 중인 라운드만 현재 출석 인원으로 재편성됩니다. 진행하시겠습니까?',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('court_cancel_reshuffle_button'),
            onPressed: () => Navigator.pop(dCtx),
            child: const Text(
              '취소',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('court_confirm_reshuffle_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(dCtx);
              final count = ref
                  .read(matchesProvider.notifier)
                  .reshuffleRemainingMatches(targetRound: selectedRound);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.primaryDark,
                    content: Text(
                      '✅ 완료된 코트 기록은 보존하고 대기 코트/남은 라운드($count경기)를 현재 출석 인원으로 재편성했습니다.',
                    ),
                  ),
                );
              }
            },
            child: const Text(
              '재편성 진행',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  /// 전체 대진표 1라운드부터 초기화 재생성 시 2단계 안전 확인 모달
  void _showResetAndRegenerateConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    GameSession session,
  ) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '대진표 전체 재편성',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          '⚠️ 완료된 경기 기록과 현재 점수가 모두 삭제됩니다. 처음부터 다시 생성하시겠습니까?',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('court_cancel_regenerate_button'),
            onPressed: () => Navigator.pop(dCtx),
            child: const Text(
              '취소',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('court_confirm_regenerate_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(dCtx);
              ref.read(matchesProvider.notifier).startNewSessionAndGenerate(
                    attendeeIds: session.effectiveAttendees,
                    courtCount: session.courtCount,
                    startCourtNumber: session.startCourtNumber,
                    matchMode: session.matchMode,
                    matchFormat: session.matchFormat,
                    matchType: session.matchType,
                    partnerMode: session.partnerMode,
                    fixedPairs: session.fixedPairs,
                  );
              ref.read(selectedRoundProvider.notifier).setRound(1);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppTheme.primaryDark,
                    content: Text('🔄 전체 대진표가 1라운드부터 새로 생성되었습니다.'),
                  ),
                );
              }
            },
            child: const Text(
              '기록 삭제 후 새로 생성',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
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
    List<Member> allMembers, {
    int? initialCourtNumber,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddCustomMatchSheet(
        session: session,
        selectedRound: selectedRound,
        roundMatches: roundMatches,
        allMembers: allMembers,
        initialCourtNumber: initialCourtNumber,
      ),
    );
  }

  Widget _buildMetricItem(
    String title,
    String val,
    String sub, {
    Key? key,
    VoidCallback? onTap,
  }) {
    return Material(
      key: key,
      color: Colors.white.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.pastelPeriwinkleDark,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: AppTheme.pastelPeriwinkleDark,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                val,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                style: const TextStyle(fontSize: 9.5, color: Colors.black54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 라운드 운영 현황 수치('출전 인원', '휴식 인원', '출석 인원' 등) 터치 시 해당 회원 '이름 (급수)' 목록 팝업 표시
  void _showRoundMemberListPopup({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<Member> members,
  }) {
    final sorted = List<Member>.from(members)
      ..sort((a, b) {
        final cmp = b.tierWeight.compareTo(a.tierWeight);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.pastelPeriwinkle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.people_alt_rounded,
                size: 18,
                color: AppTheme.pastelPeriwinkleDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: sorted.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: const Text(
                    '해당 상태의 회원이 없습니다.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                )
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sorted.map((m) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppTheme.getGenderCardBg(m.gender),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.getGenderCardBorder(m.gender),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 4,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: AppTheme.getGenderAccentColor(m.gender),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${m.name} (${m.tier.label})',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '확인',
              style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryDark),
            ),
          ),
        ],
      ),
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
            Icon(Icons.emoji_events_rounded, color: AppTheme.primaryMint),
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
                  backgroundColor: r.rank <= 3 ? AppTheme.pastelPeriwinkle : AppTheme.surfaceGrey,
                  child: Text(
                    '${r.rank}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: r.rank <= 3 ? AppTheme.pastelPeriwinkleDark : AppTheme.textMuted,
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
  late FocusNode _scoreAFocus;
  late FocusNode _scoreBFocus;

  void _selectAllScoreText(TextEditingController controller) {
    if (controller.text.isEmpty) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _onScoreFocusChanged(FocusNode focusNode, TextEditingController controller) {
    if (focusNode.hasFocus) {
      _selectAllScoreText(controller);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focusNode.hasFocus) {
          _selectAllScoreText(controller);
        }
      });
    } else {
      if (controller.text.trim().isEmpty) {
        controller.text = '0';
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scoreACtrl = TextEditingController(text: '${widget.match.scoreA}');
    _scoreBCtrl = TextEditingController(text: '${widget.match.scoreB}');
    _scoreAFocus = FocusNode()
      ..addListener(() => _onScoreFocusChanged(_scoreAFocus, _scoreACtrl));
    _scoreBFocus = FocusNode()
      ..addListener(() => _onScoreFocusChanged(_scoreBFocus, _scoreBCtrl));
  }

  @override
  void didUpdateWidget(covariant CourtMatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentParsedA = int.tryParse(_scoreACtrl.text.trim()) ?? 0;
    if (widget.match.scoreA != currentParsedA ||
        (!_scoreAFocus.hasFocus && widget.match.scoreA.toString() != _scoreACtrl.text)) {
      _scoreACtrl.text = '${widget.match.scoreA}';
      if (_scoreAFocus.hasFocus) {
        _scoreACtrl.selection = TextSelection.collapsed(offset: _scoreACtrl.text.length);
      }
    }
    final currentParsedB = int.tryParse(_scoreBCtrl.text.trim()) ?? 0;
    if (widget.match.scoreB != currentParsedB ||
        (!_scoreBFocus.hasFocus && widget.match.scoreB.toString() != _scoreBCtrl.text)) {
      _scoreBCtrl.text = '${widget.match.scoreB}';
      if (_scoreBFocus.hasFocus) {
        _scoreBCtrl.selection = TextSelection.collapsed(offset: _scoreBCtrl.text.length);
      }
    }
  }

  @override
  void dispose() {
    _scoreAFocus.dispose();
    _scoreBFocus.dispose();
    _scoreACtrl.dispose();
    _scoreBCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final teamAMembers = match.teamA.map((id) => widget.memberMap[id] ?? Member(id: id, name: '선수')).toList();
    final teamBMembers = match.teamB.map((id) => widget.memberMap[id] ?? Member(id: id, name: '선수')).toList();

    final isFinished = match.isFinished;
    final teamAWon = match.isTeamAWon || (isFinished && match.scoreA > match.scoreB);
    final teamBWon = match.isTeamBWon || (isFinished && match.scoreB > match.scoreA);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
          // 상단: 코트 번호(터치 시 번호 변경) & [경기 완료] 원터치 버튼 & [선수 교체] 버튼 (급수합 표기 제거로 잘림 방지)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isTournament) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          match.formatTournamentMatchLabel(totalMatchesInRound: widget.roundMatches.length),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Tooltip(
                        message: isFinished ? '완료된 경기는 코트가 고정되어 있습니다' : '터치하여 코트 번호 변경',
                        child: InkWell(
                          onTap: isFinished ? null : () => _showEditCourtNumberDialog(context, match),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelYellow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${match.courtNumber}번 코트',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.pastelYellowDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  isFinished ? Icons.lock_outline_rounded : Icons.edit_rounded,
                                  size: 11,
                                  color: AppTheme.pastelYellowDark,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
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
                      if (context.mounted && widget.isTournament && nextStatus == MatchStatus.finished) {
                        final winTeam = match.scoreA >= match.scoreB ? teamAMembers : teamBMembers;
                        final winNames = winTeam.map((m) => m.name).join('·');
                        final label = match.formatTournamentMatchLabel(totalMatchesInRound: widget.roundMatches.length);
                        final isFinalMatch = match.bracketRoundSize == 2 || (widget.roundMatches.length == 1 && match.round > 1);
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.primaryDark,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                            content: Text(
                              isFinalMatch
                                  ? '🎉 결승전 종료! 우승($winNames)이 확정되었습니다!'
                                  : '🏆 $label 승리 팀($winNames)이 다음 라운드 매칭 슬롯으로 자동 배정되었습니다!',
                            ),
                          ),
                        );
                      }
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
                  else if (teamAMembers.isNotEmpty || teamBMembers.isNotEmpty)
                    InkWell(
                      onTap: () => _showPlayerSwapSheet(
                        context: context,
                        match: match,
                        initialTargetPlayer: teamAMembers.isNotEmpty ? teamAMembers.first : teamBMembers.first,
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
                  focusNode: _scoreAFocus,
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

              // 중앙 VS 구분 및 세로 구분선 (컴팩트 & 가로 오버플로우 방어)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 1,
                      height: 14,
                      color: Colors.grey.shade200,
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 1,
                      height: 14,
                      color: Colors.grey.shade200,
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
                  focusNode: _scoreBFocus,
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
    required FocusNode focusNode,
    required bool isWinner,
    required bool isLoser,
    required bool isFinished,
    required ValueChanged<String> onScoreChanged,
    required ValueChanged<Member> onPlayerTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
              Flexible(
                child: Text(
                  teamTitle,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isWinner)
                Flexible(
                  child: Text(
                    widget.isTournament ? 'WIN · 진출' : 'WIN',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.pastelMintDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else if (widget.isTournament && isLoser)
                const Text(
                  '탈락',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.pastelRoseDark),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '⏳ 이전 라운드 승자 대기 (TBD)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
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

          // 인라인 실시간 점수 입력창 (포커스/터치 시 기존 숫자 전체 선택되어 바로 새 점수 입력 가능)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '점수 ',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              SizedBox(
                width: 48,
                height: 36,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: isFinished,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    filled: true,
                    fillColor: isFinished ? Colors.grey.shade100 : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primaryMint, width: 2),
                    ),
                  ),
                  onTap: isFinished
                      ? null
                      : () {
                          _selectAllScoreText(controller);
                        },
                  onChanged: isFinished
                      ? null
                      : (val) {
                          if (val.length > 1 && val.startsWith('0')) {
                            final normalized = (int.tryParse(val) ?? 0).toString();
                            controller.value = TextEditingValue(
                              text: normalized,
                              selection: TextSelection.collapsed(offset: normalized.length),
                            );
                            onScoreChanged(normalized);
                            return;
                          }
                          onScoreChanged(val);
                        },
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
          Flexible(
            child: SafeArea(
              top: false,
              child: _tabIndex == 0
                  ? _buildRestingMembersList(context, match, currentTarget, isTargetInTeamA)
                  : _buildSwapWithOtherPlayersList(context, match, currentTarget, isTargetInTeamA, otherPendingMatches),
            ),
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
      shrinkWrap: true,
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
      shrinkWrap: true,
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
  final int? initialCourtNumber;

  const _AddCustomMatchSheet({
    required this.session,
    required this.selectedRound,
    required this.roundMatches,
    required this.allMembers,
    this.initialCourtNumber,
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
    if (widget.initialCourtNumber != null) {
      _courtNumber = widget.initialCourtNumber!;
    } else {
      final existingCourtNums = widget.roundMatches.map((m) => m.courtNumber).toSet();
      final activeCourts = List.generate(
        widget.session.courtCount,
        (i) => widget.session.startCourtNumber + i,
      );
      final emptyCourts = activeCourts.where((c) => !existingCourtNums.contains(c)).toList();
      if (emptyCourts.isNotEmpty) {
        _courtNumber = emptyCourts.first;
      } else {
        _courtNumber = existingCourtNums.isEmpty
            ? widget.session.startCourtNumber
            : existingCourtNums.reduce((a, b) => a > b ? a : b) + 1;
      }
    }
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

          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4),
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
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
            child: SafeArea(
              top: false,
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

