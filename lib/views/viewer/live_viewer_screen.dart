import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/korean_search_util.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// [화면 4] 웹뷰어 (라이브 전광판 & 모임 완료 종합 리포트)
/// 1. 모임 진행 중: [실시간 코트 전광판]
///    - 코트별 현재 진행 경기(선수명, 급수, 실시간 점수)를 큰 폰트와 직관적인 카드 UI로 표시
///    - 코트 하단에 다음 라운드 대기자/휴식자 명단 표시
/// 2. 모임 완료(종료) 후: 2개 서브 탭 제공 ([종합 순위 & 리포트] / [라운드별 스코어])
///    - ① [라운드별 스코어] 탭: 라운드 필터 칩(전체, 1R, 2R...) + 코트 번호, TEAM A vs TEAM B 선수명/급수, 최종 점수, 승리팀 WIN 뱃지 강조
///    - ② [종합 순위 & 리포트] 탭: 경기 방식별 자동 분기 처리
///      * [토너먼트]: 개인별 순위표 대신 '최종 트리(우승, 준우승, 4강 등 진출 단계 기준)' 표시
///      * [풀리그전 (팀 기준)]: 팀별 순위표 (1순위 다승 -> 2순위 승자승 -> 3순위 득실차 -> 4순위 다득점)
///      * [정기 로테이션 (개인 기준)]: 개인별 순위표 (1순위 승률 -> 2순위 득실차 -> 3순위 다승 -> 4순위 다득점 / 승자승 제외)
///      * 하단에 해당 모드의 [순위 결정 기준 안내] 정보 박스 상시 노출
/// 3. 공유 및 편의 기능:
///    - 상단 [웹 링크 복사] 버튼 (단톡방 공유용)
///    - 총무용 보조 기능 [결과 요약 텍스트 복사] 버튼
class LiveViewerScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const LiveViewerScreen({
    super.key,
    required this.sessionId,
  });

  @override
  ConsumerState<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// 선택된 세션 ID (null이면 현재 활성 세션 또는 기본 전광판)
  String? _selectedSessionId;

  /// 모임 진행 중(false) vs 모임 완료 후(true) 뷰 강제 오버라이드 (null이면 세션의 isCompleted 상태 따름)
  bool? _isCompletedViewOverride;

  /// 모임 완료 후 서브 탭 인덱스: 0 = [종합 순위 & 리포트], 1 = [라운드별 스코어]
  int _completedSubTabIndex = 0;

  /// [라운드별 스코어] 탭의 라운드 필터 (null = 전체, 1 = 1R, 2 = 2R...)
  int? _scoreFilterRound;

  /// [실시간 코트 전광판] 모드의 선택 라운드 (null이면 현재 라운드)
  int? _liveSelectedRound;

  /// 완료 리포트에서 경기 방식 미리보기 오버라이드 (null이면 선택된 세션의 matchFormat 사용)
  MatchFormat? _formatPreviewOverride;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 진행 중인 모임이 아직 없을 때 실시간 코트 전광판 시연용 기본 세션 생성
  GameSession _buildFallbackLiveSession(String clubId, List<Member> clubMembers) {
    final activeIds = clubMembers
        .where((m) => !m.isGuest && m.status == MemberStatus.active)
        .take(12)
        .map((m) => m.id)
        .toList();
    final Map<String, AttendanceStatus> statusMap = {
      for (int i = 0; i < activeIds.length; i++)
        activeIds[i]: i >= 10 ? AttendanceStatus.resting : AttendanceStatus.active,
    };
    return GameSession(
      id: widget.sessionId,
      clubId: clubId,
      title: '실시간 라이브 코트 전광판',
      sessionDate: '2026-09-26',
      courtCount: 2,
      startCourtNumber: 1,
      matchFormat: MatchFormat.regular,
      matchType: MatchType.normal,
      matchMode: MatchMode.tiered,
      attendees: activeIds,
      activeAttendees: activeIds.take(10).toList(),
      attendeeStatusMap: statusMap,
      currentRound: 1,
      isCompleted: false,
    );
  }

  /// 진행 중인 경기가 아직 없을 때 실시간 코트 전광판 기본 샘플 경기 목록
  List<GameMatch> _buildFallbackLiveMatches(String sessionId, List<Member> clubMembers) {
    final ids = clubMembers.map((m) => m.id).toList();
    if (ids.length < 8) return const [];
    return [
      GameMatch(
        id: 'live_demo_r1_c1',
        sessionId: sessionId,
        round: 1,
        courtNumber: 1,
        teamA: [ids[0], ids[3]],
        teamB: [ids[1], ids[2]],
        scoreA: 18,
        scoreB: 16,
        status: MatchStatus.playing,
      ),
      GameMatch(
        id: 'live_demo_r1_c2',
        sessionId: sessionId,
        round: 1,
        courtNumber: 2,
        teamA: [ids[4], ids[7]],
        teamB: [ids[5], ids[6]],
        scoreA: 11,
        scoreB: 14,
        status: MatchStatus.playing,
      ),
    ];
  }

  /// 단톡방 공유용 [웹 링크 복사] 실행
  Future<void> _copyWebViewerLink(GameSession session) async {
    final shareUrl = 'https://cockmatch.app/live/${session.clubId}/${session.id}';
    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔗 웹뷰어 링크가 복사되었습니다! 단톡방에 붙여넣어 공유하세요.\n($shareUrl)'),
        backgroundColor: AppTheme.primaryDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 총무용 보조 기능 [결과 요약 텍스트 복사] 실행
  Future<void> _copyResultSummaryText({
    required GameSession session,
    required List<GameMatch> matches,
    required List<Member> members,
    required MatchFormat activeFormat,
    required bool isCompletedView,
  }) async {
    final memberMap = {for (final m in members) m.id: m};
    final generator = ref.read(matchGeneratorServiceProvider);
    final buffer = StringBuffer();

    buffer.writeln('🏸 [${AppConstants.appName}] ${session.title}');
    buffer.writeln('📅 일자: ${session.sessionDate} | 방식: ${activeFormat.label}');
    buffer.writeln('────────────────────');

    if (!isCompletedView) {
      final currentRound = _liveSelectedRound ?? session.currentRound;
      final roundMatches = matches.where((m) => m.round == currentRound).toList();
      buffer.writeln('⚡ [실시간 코트 전광판 - ${currentRound}R 진행 현황]');
      for (final m in roundMatches) {
        final namesA = m.teamA.map((id) => memberMap[id]?.name ?? id).join('·');
        final namesB = m.teamB.map((id) => memberMap[id]?.name ?? id).join('·');
        buffer.writeln(
          '• 코트 ${m.courtNumber} (${m.status.label}): $namesA [${m.scoreA} : ${m.scoreB}] $namesB',
        );
      }
    } else {
      final finishedMatches = matches.where((m) => m.isFinished).toList();
      final effectiveMatches = finishedMatches.isNotEmpty
          ? finishedMatches
          : matches.map((m) => m.copyWith(status: MatchStatus.finished)).toList();

      if (activeFormat == MatchFormat.tournament) {
        final tree = generator.buildTournamentResultTree(
          matches: effectiveMatches,
          members: members,
        );
        buffer.writeln('🏆 [토너먼트 최종 결과]');
        for (final stage in tree.stagePlacements) {
          final teamNames = stage.teams.map((t) => t.teamName).join(', ');
          buffer.writeln('${stage.badgeEmoji} ${stage.stageTitle}: $teamNames');
        }
      } else if (activeFormat == MatchFormat.league) {
        final teamRankings = generator.calculateLeagueTeamRankings(
          finishedMatches: effectiveMatches,
          members: members,
        );
        buffer.writeln('🏅 [풀리그전 (팀 기준) 종합 순위]');
        for (final t in teamRankings.take(5)) {
          final diffStr = t.pointDifference >= 0 ? '+${t.pointDifference}' : '${t.pointDifference}';
          buffer.writeln(
            '${t.rank}위: ${t.teamName} (${t.wins}승 ${t.losses}패 / 득실 $diffStr / 총득점 ${t.pointsFor})',
          );
        }
      } else {
        final playerRankings = generator.calculateRegularRotationRankings(
          finishedMatches: effectiveMatches,
          members: members,
          onlyPlayedPlayers: true,
        );
        buffer.writeln('🏅 [정기 로테이션 (개인 기준) 종합 순위]');
        for (final p in playerRankings.take(5)) {
          final diffStr = p.pointDifference >= 0 ? '+${p.pointDifference}' : '${p.pointDifference}';
          buffer.writeln(
            '${p.rank}위: ${p.memberName} (승률 ${p.winRate.toStringAsFixed(0)}% / ${p.wins}승 ${p.losses}패 / 득실 $diffStr / 총득점 ${p.pointsFor})',
          );
        }
      }

      buffer.writeln('────────────────────');
      buffer.writeln('📊 [라운드별 스코어 요약]');
      final sortedMatches = List<GameMatch>.from(matches)
        ..sort((a, b) {
          final r = a.round.compareTo(b.round);
          return r != 0 ? r : a.courtNumber.compareTo(b.courtNumber);
        });
      for (final m in sortedMatches) {
        final namesA = m.teamA.map((id) => memberMap[id]?.name ?? id).join('·');
        final namesB = m.teamB.map((id) => memberMap[id]?.name ?? id).join('·');
        final winTagA = m.scoreA > m.scoreB ? '(WIN)' : '';
        final winTagB = m.scoreB > m.scoreA ? '(WIN)' : '';
        buffer.writeln(
          '• ${m.round}R 코트${m.courtNumber}: $namesA$winTagA ${m.scoreA} : ${m.scoreB} $namesB$winTagB',
        );
      }
    }

    buffer.writeln('🔗 상세 웹뷰어: https://cockmatch.app/live/${session.clubId}/${session.id}');

    final summaryText = buffer.toString().trim();
    await Clipboard.setData(ClipboardData(text: summaryText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 결과 요약 텍스트가 복사되었습니다! 단톡방이나 공지에 바로 붙여넣으세요.'),
        backgroundColor: AppTheme.primaryMint,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentClub = ref.watch(currentClubProvider);
    final clubMembers = ref.watch(currentClubMembersProvider);
    final activeSession = ref.watch(sessionProvider);
    final ongoingSessions = ref.watch(currentClubOngoingSessionsProvider);
    final archivedSessions = ref.watch(currentClubArchivedSessionsProvider);
    final currentMatches = ref.watch(matchesProvider);

    // 활성 세션이 변경되면 자동으로 해당 세션을 선택하도록 동기화
    ref.listen<GameSession?>(sessionProvider, (prev, next) {
      if (prev?.id != next?.id) {
        setState(() {
          _selectedSessionId = next?.id;
          _isCompletedViewOverride = null;
          _formatPreviewOverride = null;
          _scoreFilterRound = null;
          _liveSelectedRound = null;
        });
      }
    });

    // 클럽 내 전체 선택 가능한 모임 목록 구성
    final fallbackLiveSession = _buildFallbackLiveSession(currentClub.id, clubMembers);
    final allAvailableSessions = <GameSession>[
      ?activeSession,
      ...ongoingSessions.where((s) => s.id != activeSession?.id),
      if (activeSession == null && ongoingSessions.isEmpty) fallbackLiveSession,
      ...archivedSessions.where((s) => s.id != activeSession?.id),
    ];

    // 현재 표시할 대상 세션 결정
    GameSession targetSession;
    if (_selectedSessionId != null) {
      targetSession = allAvailableSessions.firstWhere(
        (s) => s.id == _selectedSessionId,
        orElse: () => activeSession ?? allAvailableSessions.first,
      );
    } else if (activeSession != null) {
      targetSession = activeSession;
    } else {
      targetSession = allAvailableSessions.first;
    }

    // 대상 세션의 경기 목록 조회
    List<GameMatch> sessionMatches;
    if (activeSession != null && targetSession.id == activeSession.id && currentMatches.isNotEmpty) {
      sessionMatches = currentMatches;
    } else {
      final archived = ref.read(matchesProvider.notifier).getMatchesForSession(targetSession.id);
      if (archived.isNotEmpty) {
        sessionMatches = archived;
      } else if (targetSession.id == fallbackLiveSession.id) {
        sessionMatches = _buildFallbackLiveMatches(targetSession.id, clubMembers);
      } else {
        sessionMatches = const [];
      }
    }

    final bool isCompletedView = _isCompletedViewOverride ?? targetSession.isCompleted;
    final MatchFormat activeFormat = _formatPreviewOverride ?? targetSession.matchFormat;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // 1. 상단 헤더 + [웹 링크 복사] & [결과 요약 텍스트 복사] 액션 바
            SliverToBoxAdapter(
              child: _buildTopHeaderAndShareBar(
                clubName: currentClub.clubName,
                targetSession: targetSession,
                allAvailableSessions: allAvailableSessions,
                sessionMatches: sessionMatches,
                clubMembers: clubMembers,
                activeFormat: activeFormat,
                isCompletedView: isCompletedView,
              ),
            ),

            // 2. 모임 진행 중 vs 모임 완료 후 분기 콘텐츠
            if (!isCompletedView)
              SliverToBoxAdapter(
                child: _buildLiveScoreboardBody(
                  session: targetSession,
                  matches: sessionMatches,
                  members: clubMembers,
                ),
              )
            else
              SliverToBoxAdapter(
                child: _buildCompletedReportBody(
                  session: targetSession,
                  matches: sessionMatches,
                  members: clubMembers,
                  activeFormat: activeFormat,
                  archivedSessions: archivedSessions,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  /// 1. 상단 헤더, 모임 선택/전환 바, 그리고 [웹 링크 복사] / [결과 요약 텍스트 복사] 버튼
  Widget _buildTopHeaderAndShareBar({
    required String clubName,
    required GameSession targetSession,
    required List<GameSession> allAvailableSessions,
    required List<GameMatch> sessionMatches,
    required List<Member> clubMembers,
    required MatchFormat activeFormat,
    required bool isCompletedView,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 클럽명 & 라이브/완료 상태 헤더
          Row(
            children: [
              IconButton(
                onPressed: () => AppTheme.openDrawer(context),
                tooltip: '메뉴 열기',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.menu_rounded, color: AppTheme.textDark, size: 22),
              ),
              const SizedBox(width: 10),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isCompletedView ? AppTheme.pastelPeriwinkle : AppTheme.pastelMint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    isCompletedView ? Icons.emoji_events_rounded : Icons.live_tv_rounded,
                    color: isCompletedView ? AppTheme.pastelPeriwinkleDark : AppTheme.pastelMintDark,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            clubName,
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCompletedView ? AppTheme.pastelPeriwinkle : AppTheme.pastelMint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isCompletedView ? '모임 완료 리포트' : 'LIVE 전광판',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: isCompletedView
                                  ? AppTheme.pastelPeriwinkleDark
                                  : AppTheme.pastelMintDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${targetSession.title} (${targetSession.sessionDate})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. 공유 및 편의 기능 버튼 바: [웹 링크 복사] & [결과 요약 텍스트 복사]
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyWebViewerLink(targetSession),
                  icon: const Icon(Icons.link_rounded, size: 17, color: AppTheme.primaryDark),
                  label: const Text(
                    '웹 링크 복사',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _copyResultSummaryText(
                    session: targetSession,
                    matches: sessionMatches,
                    members: clubMembers,
                    activeFormat: activeFormat,
                    isCompletedView: isCompletedView,
                  ),
                  icon: const Icon(Icons.content_copy_rounded, size: 16, color: Colors.white),
                  label: const Text(
                    '결과 요약 텍스트 복사',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 진행 중 [실시간 코트 전광판] ↔ 모임 완료 [종합 순위 & 리포트 / 라운드별 스코어] 전환 및 모임 선택 바
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상태 모드 전환 토글: [실시간 코트 전광판] vs [모임 완료(종료) 후 리포트]
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            // 진행 중 세션이 있으면 해당 세션으로, 없으면 현재 세션에서 전광판 뷰로 전환
                            final ongoing = allAvailableSessions.where((s) => !s.isCompleted).toList();
                            if (ongoing.isNotEmpty && targetSession.isCompleted) {
                              _selectedSessionId = ongoing.first.id;
                            }
                            _isCompletedViewOverride = false;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: !isCompletedView ? AppTheme.primaryMint : AppTheme.surfaceGrey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 16,
                                color: !isCompletedView ? Colors.white : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '실시간 코트 전광판',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: !isCompletedView ? Colors.white : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            // 완료된 모임이 있으면 가장 최근 완료 모임을 자동 선택
                            final completedList =
                                allAvailableSessions.where((s) => s.isCompleted).toList();
                            if (completedList.isNotEmpty && !targetSession.isCompleted) {
                              _selectedSessionId = completedList.first.id;
                            }
                            _isCompletedViewOverride = true;
                            _formatPreviewOverride = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isCompletedView ? AppTheme.primaryDark : AppTheme.surfaceGrey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.assessment_rounded,
                                size: 16,
                                color: isCompletedView ? Colors.white : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '모임 완료 결과 리포트',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isCompletedView ? Colors.white : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // 클럽 내 모임 선택 칩 (진행 모임 & 지난 완료 모임 빠른 전환)
                if (allAvailableSessions.length > 1) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: allAvailableSessions.map((s) {
                        final isSelected = s.id == targetSession.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              '${s.isCompleted ? "[완료]" : "[LIVE]"} ${s.title} (${s.matchFormat.label})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryDark,
                            backgroundColor: AppTheme.surfaceGrey,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) {
                              setState(() {
                                _selectedSessionId = s.id;
                                _isCompletedViewOverride = s.isCompleted;
                                _formatPreviewOverride = null;
                                _scoreFilterRound = null;
                                _liveSelectedRound = null;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. 모임 진행 중: [실시간 코트 전광판]
  // ===========================================================================
  Widget _buildLiveScoreboardBody({
    required GameSession session,
    required List<GameMatch> matches,
    required List<Member> members,
  }) {
    final memberMap = {for (final m in members) m.id: m};
    final rounds = matches.map((m) => m.round).toSet().toList()..sort();
    if (rounds.isEmpty) rounds.add(session.currentRound);

    final activeRound = (_liveSelectedRound != null && rounds.contains(_liveSelectedRound))
        ? _liveSelectedRound!
        : rounds.last;

    final currentRoundMatches = matches.where((m) => m.round == activeRound).toList()
      ..sort((a, b) => a.courtNumber.compareTo(b.courtNumber));

    // 현재 라운드 출전 선수 ID 집합
    final playingPlayerIds = currentRoundMatches.expand((m) => m.allPlayerIds).toSet();

    // 선수별 누적 출전 경기 수 계산
    final matchCounts = <String, int>{};
    for (final id in session.attendees) {
      matchCounts[id] = 0;
    }
    for (final m in matches) {
      for (final pid in m.allPlayerIds) {
        matchCounts[pid] = (matchCounts[pid] ?? 0) + 1;
      }
    }

    // 다음 라운드 대기자 (현재 코트에 배정되지 않은 active 참석자, 출전 수 오름차순 정렬)
    final waitingMembers = session.attendees
        .where((id) =>
            !playingPlayerIds.contains(id) &&
            session.getAttendeeStatus(id) == AttendanceStatus.active &&
            memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList()
      ..sort((a, b) {
        final countCmp = (matchCounts[a.id] ?? 0).compareTo(matchCounts[b.id] ?? 0);
        if (countCmp != 0) return countCmp;
        return a.name.compareTo(b.name);
      });

    // 휴식자 명단 (AttendanceStatus.resting 또는 withdrawn)
    final restingMembers = session.attendees
        .where((id) =>
            !playingPlayerIds.contains(id) &&
            session.getAttendeeStatus(id) != AttendanceStatus.active &&
            memberMap.containsKey(id))
        .map((id) => memberMap[id]!)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),

          // 내 이름 / 초성 검색바 + 라운드 선택 칩
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: '내 이름/초성 검색 (출전 코트·대기 순번 강조)',
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppTheme.textMuted),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 17),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 실시간 코트 전광판 섹션 타이틀 & 라운드 칩
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '실시간 코트 전광판',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '총 ${currentRoundMatches.length}코트 가동 중',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              if (rounds.length > 1)
                Row(
                  children: rounds.map((r) {
                    final selected = r == activeRound;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        onTap: () => setState(() => _liveSelectedRound = r),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primaryMint : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? AppTheme.primaryMint : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            '${r}R',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: selected ? Colors.white : AppTheme.textDark,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 코트별 대형 전광판 카드 리스트
          if (currentRoundMatches.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.softShadow,
              ),
              child: const Center(
                child: Text(
                  '현재 라운드에 배정된 코트 경기가 없습니다.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ),
            )
          else
            ...currentRoundMatches.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildScoreboardMatchCard(
                  match: match,
                  memberMap: memberMap,
                  isLiveScoreboard: true,
                ),
              ),
            ),

          const SizedBox(height: 8),

          // 코트 하단: 다음 라운드 대기자 / 휴식자 명단 섹션
          _buildWaitingAndRestingSection(
            waitingMembers: waitingMembers,
            restingMembers: restingMembers,
            matchCounts: matchCounts,
          ),
        ],
      ),
    );
  }

  /// 코트별 경기 전광판 / 스코어 결과 카드 (실시간 전광판 & 라운드별 스코어 공용)
  Widget _buildScoreboardMatchCard({
    required GameMatch match,
    required Map<String, Member> memberMap,
    required bool isLiveScoreboard,
  }) {
    final teamAMembers = match.teamA.map((id) => memberMap[id]).toList();
    final teamBMembers = match.teamB.map((id) => memberMap[id]).toList();

    final allNames = [
      ...match.teamA.map((id) => memberMap[id]?.name ?? id),
      ...match.teamB.map((id) => memberMap[id]?.name ?? id),
    ];

    final isHighlighted = _searchQuery.isNotEmpty &&
        allNames.any((name) => KoreanSearchUtil.matches(name, _searchQuery));

    final bool isTeamAWinner =
        (match.isFinished || !isLiveScoreboard) && (match.scoreA > match.scoreB);
    final bool isTeamBWinner =
        (match.isFinished || !isLiveScoreboard) && (match.scoreB > match.scoreA);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isHighlighted
              ? AppTheme.primaryMint
              : (match.isPlaying ? AppTheme.primaryMint.withValues(alpha: 0.4) : Colors.grey.shade200),
          width: isHighlighted ? 2.2 : 1.2,
        ),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          // 상단: 코트 번호 + 라운드 + 경기 상태 뱃지
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '코트 ${match.courtNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${match.round}R',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              _buildStatusBadge(match.status),
            ],
          ),
          const SizedBox(height: 14),

          // 중단: TEAM A vs 대형 점수판 vs TEAM B
          Row(
            children: [
              // TEAM A 영역
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isTeamAWinner
                        ? AppTheme.pastelMint.withValues(alpha: 0.55)
                        : AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isTeamAWinner ? AppTheme.primaryMint : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'TEAM A',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          if (isTeamAWinner) ...[
                            const SizedBox(width: 6),
                            _buildWinBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(match.teamA.length, (idx) {
                        final id = match.teamA[idx];
                        final member = teamAMembers[idx];
                        final name = member?.name ?? id;
                        final tier = member?.tier ?? Tier.c;
                        final isPlayerSearched = _searchQuery.isNotEmpty &&
                            KoreanSearchUtil.matches(name, _searchQuery);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: isPlayerSearched
                                        ? AppTheme.primaryMint
                                        : AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 5),
                              _buildTierMiniBadge(tier),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // 중앙 대형 점수판 (큰 폰트 직관적 스코어)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${match.scoreA} : ${match.scoreB}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLiveScoreboard ? 'LIVE SCORE' : 'FINAL',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // TEAM B 영역
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isTeamBWinner
                        ? AppTheme.pastelMint.withValues(alpha: 0.55)
                        : AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isTeamBWinner ? AppTheme.primaryMint : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isTeamBWinner) ...[
                            _buildWinBadge(),
                            const SizedBox(width: 6),
                          ],
                          const Text(
                            'TEAM B',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(match.teamB.length, (idx) {
                        final id = match.teamB[idx];
                        final member = teamBMembers[idx];
                        final name = member?.name ?? id;
                        final tier = member?.tier ?? Tier.c;
                        final isPlayerSearched = _searchQuery.isNotEmpty &&
                            KoreanSearchUtil.matches(name, _searchQuery);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _buildTierMiniBadge(tier),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: isPlayerSearched
                                        ? AppTheme.primaryMint
                                        : AppTheme.textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 승리팀 WIN 강조 뱃지
  Widget _buildWinBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryMint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'WIN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// 급수 뱃지 (A조, B조, C조, D조, 초심)
  Widget _buildTierMiniBadge(Tier tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        tier.label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.textDark,
        ),
      ),
    );
  }

  /// 코트 하단: 다음 라운드 대기자 / 휴식자 명단 섹션
  Widget _buildWaitingAndRestingSection({
    required List<Member> waitingMembers,
    required List<Member> restingMembers,
    required Map<String, int> matchCounts,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18, color: AppTheme.primaryMint),
              const SizedBox(width: 6),
              const Text(
                '다음 라운드 대기자 / 휴식자 명단',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '대기 ${waitingMembers.length}명 · 휴식 ${restingMembers.length}명',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '출전 경기 수가 적은 순서대로 다음 라운드에 우선 배정됩니다.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),

          // 1) 다음 라운드 우선 출전 대기자
          const Text(
            '다음 라운드 대기 순번',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          if (waitingMembers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '현재 대기 중인 인원이 없습니다 (전원 코트 출전 중)',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(waitingMembers.length, (idx) {
                final m = waitingMembers[idx];
                final games = matchCounts[m.id] ?? 0;
                final isSearched = _searchQuery.isNotEmpty &&
                    KoreanSearchUtil.matches(m.name, _searchQuery);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSearched ? AppTheme.pastelMint : AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSearched ? AppTheme.primaryMint : Colors.grey.shade300,
                      width: isSearched ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${idx + 1}순위',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildTierMiniBadge(m.tier),
                      const SizedBox(width: 4),
                      Text(
                        '($games경기)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),

          // 2) 휴식자 명단
          if (restingMembers.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '휴식 / 대기 제외 인원',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: restingMembers.map((m) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelYellow.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.pause_circle_outline_rounded,
                        size: 14,
                        color: AppTheme.pastelYellowDark,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${m.name} (${m.tier.label})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.pastelYellowDark,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. 모임 완료(종료) 후: 2개 서브 탭 ([종합 순위 & 리포트] / [라운드별 스코어])
  // ===========================================================================
  Widget _buildCompletedReportBody({
    required GameSession session,
    required List<GameMatch> matches,
    required List<Member> members,
    required MatchFormat activeFormat,
    required List<GameSession> archivedSessions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),

          // 2개 서브 탭 바: [종합 순위 & 리포트] / [라운드별 스코어]
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.softShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _completedSubTabIndex = 0),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _completedSubTabIndex == 0
                            ? AppTheme.primaryDark
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '종합 순위 & 리포트',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: _completedSubTabIndex == 0
                                ? Colors.white
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _completedSubTabIndex = 1),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _completedSubTabIndex == 1
                            ? AppTheme.primaryDark
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '라운드별 스코어',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: _completedSubTabIndex == 1
                                ? Colors.white
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 서브 탭 콘텐츠 렌더링
          if (_completedSubTabIndex == 0)
            _buildComprehensiveRankingTab(
              session: session,
              matches: matches,
              members: members,
              activeFormat: activeFormat,
              archivedSessions: archivedSessions,
            )
          else
            _buildRoundByRoundScoreTab(
              session: session,
              matches: matches,
              members: members,
            ),
        ],
      ),
    );
  }

  /// ② [종합 순위 & 리포트] 탭 (경기 방식별 자동 분기 처리 + 하단 [순위 결정 기준 안내] 정보 박스 상시 노출)
  Widget _buildComprehensiveRankingTab({
    required GameSession session,
    required List<GameMatch> matches,
    required List<Member> members,
    required MatchFormat activeFormat,
    required List<GameSession> archivedSessions,
  }) {
    final generator = ref.read(matchGeneratorServiceProvider);

    // 완료된 경기 우선 사용, 만약 진행 중 모임을 미리보기로 본 경우 전체 경기를 완료 기준으로 산출
    final finishedMatches = matches.where((m) => m.isFinished).toList();
    final effectiveMatches = finishedMatches.isNotEmpty
        ? finishedMatches
        : matches.map((m) => m.copyWith(status: MatchStatus.finished)).toList();

    // 참석자 명단 필터링
    final sessionMembers = session.attendees.isNotEmpty
        ? members.where((m) => session.attendees.contains(m.id)).toList()
        : members;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 경기 방식 표시 및 경기 방식별 리포트 전환 칩
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_graph_rounded, size: 18, color: AppTheme.primaryMint),
              const SizedBox(width: 6),
              const Text(
                '경기 방식:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFormatSwitchChip(
                        format: MatchFormat.regular,
                        label: '정기 로테이션 (개인 기준)',
                        activeFormat: activeFormat,
                        archivedSessions: archivedSessions,
                      ),
                      const SizedBox(width: 6),
                      _buildFormatSwitchChip(
                        format: MatchFormat.league,
                        label: '풀리그전 (팀 기준)',
                        activeFormat: activeFormat,
                        archivedSessions: archivedSessions,
                      ),
                      const SizedBox(width: 6),
                      _buildFormatSwitchChip(
                        format: MatchFormat.tournament,
                        label: '토너먼트',
                        activeFormat: activeFormat,
                        archivedSessions: archivedSessions,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 경기 방식별 자동 분기 렌더링
        if (activeFormat == MatchFormat.tournament)
          _buildTournamentFinalTreeView(
            tree: generator.buildTournamentResultTree(
              matches: effectiveMatches,
              members: members,
            ),
            memberMap: {for (final m in members) m.id: m},
          )
        else if (activeFormat == MatchFormat.league)
          _buildLeagueTeamStandingsView(
            teamStandings: generator.calculateLeagueTeamRankings(
              finishedMatches: effectiveMatches,
              members: members,
            ),
          )
        else
          _buildRegularIndividualStandingsView(
            playerStandings: generator.calculateRegularRotationRankings(
              finishedMatches: effectiveMatches,
              members: sessionMembers.isNotEmpty ? sessionMembers : members,
              onlyPlayedPlayers: true,
            ),
          ),

        const SizedBox(height: 16),

        // 순위표 하단: 해당 모드의 [순위 결정 기준 안내] 정보 박스 상시 노출
        _buildRankingCriteriaInfoBox(activeFormat),
      ],
    );
  }

  Widget _buildFormatSwitchChip({
    required MatchFormat format,
    required String label,
    required MatchFormat activeFormat,
    required List<GameSession> archivedSessions,
  }) {
    final isSelected = activeFormat == format;
    return InkWell(
      onTap: () {
        setState(() {
          // 해당 경기 방식의 완료된 아카이브 모임이 있으면 함께 선택하여 실제 데이터 표시
          final matchingArchived =
              archivedSessions.where((s) => s.matchFormat == format).toList();
          if (matchingArchived.isNotEmpty) {
            _selectedSessionId = matchingArchived.first.id;
            _isCompletedViewOverride = true;
            _formatPreviewOverride = null;
          } else {
            _formatPreviewOverride = format;
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryMint : AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : AppTheme.textDark,
          ),
        ),
      ),
    );
  }

  /// [토너먼트] 전용 화면: 개인별 순위표 대신 '최종 트리(우승, 준우승, 4강 등 진출 단계 기준)' 표시
  Widget _buildTournamentFinalTreeView({
    required TournamentResultTree tree,
    required Map<String, Member> memberMap,
  }) {
    if (tree.stagePlacements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: Text(
            '집계된 토너먼트 경기 결과가 없습니다.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
        ),
      );
    }

    final rounds = tree.matchesByRound.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) 진출 단계별 입상 카드 트리 (우승, 준우승, 4강 등)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  const Text(
                    '토너먼트 최종 트리 (진출 단계 기준)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...tree.stagePlacements.map((stage) {
                final isChampion = stage.stageTitle.contains('우승') &&
                    !stage.stageTitle.contains('준우승');
                final isRunnerUp = stage.stageTitle.contains('준우승');

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isChampion
                        ? AppTheme.pastelYellow.withValues(alpha: 0.5)
                        : (isRunnerUp
                            ? AppTheme.pastelPeriwinkle.withValues(alpha: 0.45)
                            : AppTheme.surfaceGrey),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isChampion
                          ? AppTheme.pastelYellowDark.withValues(alpha: 0.4)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(stage.badgeEmoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(
                            stage.stageTitle,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: isChampion
                                  ? AppTheme.pastelYellowDark
                                  : AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: stage.teams.map((team) {
                          final diffStr = team.pointDifference >= 0
                              ? '+${team.pointDifference}'
                              : '${team.pointDifference}';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  team.teamName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${team.wins}승 ${team.losses}패 · 득실 $diffStr)',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2) 라운드별 대진 브래킷 트리 시각화 (4강 -> 결승 등)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '라운드별 토너먼트 브래킷 대진표',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              ...rounds.map((r) {
                final rMatches = tree.matchesByRound[r] ?? [];
                final isFinal = r == rounds.last && rMatches.length == 1;
                final stageLabel = isFinal
                    ? '${r}R 결승전 (FINAL)'
                    : (r == rounds.last - 1 ? '${r}R 준결승 (4강)' : '${r}R 토너먼트');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isFinal ? AppTheme.primaryDark : AppTheme.pastelMint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          stageLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: isFinal ? Colors.white : AppTheme.pastelMintDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...rMatches.map((m) {
                        final namesA =
                            m.teamA.map((id) => memberMap[id]?.name ?? id).join(' & ');
                        final namesB =
                            m.teamB.map((id) => memberMap[id]?.name ?? id).join(' & ');
                        final aWon = m.scoreA > m.scoreB;
                        final bWon = m.scoreB > m.scoreA;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceGrey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '코트 ${m.courtNumber}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        namesA,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              aWon ? FontWeight.w900 : FontWeight.w600,
                                          color: AppTheme.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (aWon) ...[
                                      const SizedBox(width: 4),
                                      _buildWinBadge(),
                                    ],
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${m.scoreA} : ${m.scoreB}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryDark,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (bWon) ...[
                                      _buildWinBadge(),
                                      const SizedBox(width: 4),
                                    ],
                                    Flexible(
                                      child: Text(
                                        namesB,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              bWon ? FontWeight.w900 : FontWeight.w600,
                                          color: AppTheme.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
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
          ),
        ),
      ],
    );
  }

  /// [풀리그전 (팀 기준)] 전용 화면: 팀별 순위표 제공
  /// (타이브레이커: 1순위 다승 -> 2순위 승자승 -> 3순위 득실차 -> 4순위 다득점)
  Widget _buildLeagueTeamStandingsView({
    required List<TeamStanding> teamStandings,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, size: 20, color: AppTheme.primaryMint),
              const SizedBox(width: 8),
              const Text(
                '풀리그전 팀별 순위표 (팀 기준)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '총 ${teamStandings.length}팀',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 테이블 컬럼 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    '순위',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '팀 (복식 페어)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '다승(전적)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '득실차',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '다득점',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (teamStandings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  '집계된 팀 경기 기록이 없습니다.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ),
            )
          else
            ...teamStandings.map((team) {
              final isTop3 = team.rank <= 3;
              final diffStr = team.pointDifference >= 0
                  ? '+${team.pointDifference}'
                  : '${team.pointDifference}';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: team.rank == 1
                      ? AppTheme.pastelYellow.withValues(alpha: 0.38)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isTop3 ? AppTheme.primaryMint.withValues(alpha: 0.35) : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: _buildRankBadge(team.rank),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.teamName,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                          ),
                          if (team.playerTiers.isNotEmpty)
                            Text(
                              team.playerTiers.map((t) => t.label).join(' · '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${team.wins}승 ${team.losses}패',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        diffStr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: team.pointDifference >= 0
                              ? AppTheme.primaryMint
                              : AppTheme.coralRed,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${team.pointsFor}점',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// [정기 로테이션 (개인 기준)] 전용 화면: 개인별 순위표 제공 (개인별 경기 수 편차 반영)
  /// (타이브레이커: 1순위 승률 -> 2순위 득실차 -> 3순위 다승 -> 4순위 다득점 / 승자승 제외)
  Widget _buildRegularIndividualStandingsView({
    required List<PlayerStanding> playerStandings,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_rounded, size: 20, color: AppTheme.primaryMint),
              const SizedBox(width: 8),
              const Text(
                '정기 로테이션 개인별 순위표 (개인 기준)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '총 ${playerStandings.length}명',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 테이블 컬럼 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '순위',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '선수명 (급수)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '승률',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '득실차',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '다승(전적)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '다득점',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (playerStandings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  '집계된 개인 경기 기록이 없습니다.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ),
            )
          else
            ...playerStandings.map((p) {
              final diffStr = p.pointDifference >= 0
                  ? '+${p.pointDifference}'
                  : '${p.pointDifference}';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: p.rank == 1
                      ? AppTheme.pastelYellow.withValues(alpha: 0.38)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: p.rank <= 3
                        ? AppTheme.primaryMint.withValues(alpha: 0.35)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: _buildRankBadge(p.rank),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.memberName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (p.tier != null) ...[
                            const SizedBox(width: 4),
                            _buildTierMiniBadge(p.tier!),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${p.winRate.toStringAsFixed(0)}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        diffStr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: p.pointDifference >= 0
                              ? AppTheme.primaryMint
                              : AppTheme.coralRed,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${p.wins}승${p.losses}패',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${p.pointsFor}점',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) {
      return const Text('🥇 1', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900));
    } else if (rank == 2) {
      return const Text('🥈 2', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900));
    } else if (rank == 3) {
      return const Text('🥉 3', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900));
    }
    return Text(
      '$rank위',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppTheme.textMuted,
      ),
    );
  }

  /// 순위표 하단 상시 노출: 해당 모드의 [순위 결정 기준 안내] 정보 박스
  Widget _buildRankingCriteriaInfoBox(MatchFormat format) {
    String modeLabel;
    String criteriaDescription;
    String detailRule;

    switch (format) {
      case MatchFormat.tournament:
        modeLabel = '토너먼트 (고정 페어 단두대 방식)';
        criteriaDescription = '최종 트리: 우승 🏆 ➔ 준우승 🥈 ➔ 4강 🥉 ➔ 8강 진출 단계 기준';
        detailRule =
            '• 토너먼트는 개인별 순위표 대신 라운드별 승자 진출에 따른 최종 브래킷 트리(우승·준우승·4강 등 진출 단계)로 최종 성적을 산정합니다.';
        break;
      case MatchFormat.league:
        modeLabel = '풀리그전 (팀 기준)';
        criteriaDescription =
            '타이브레이커: 1순위 다승 ➔ 2순위 승자승 ➔ 3순위 득실차 ➔ 4순위 다득점';
        detailRule =
            '• 결성된 복식 팀(페어) 단위로 성적을 집계하며, 동률 발생 시 두 팀 간 맞대결 결과(승자승)를 득실차보다 우선 적용합니다.';
        break;
      case MatchFormat.regular:
        modeLabel = '정기 로테이션 (개인 기준)';
        criteriaDescription =
            '타이브레이커: 1순위 승률 ➔ 2순위 득실차 ➔ 3순위 다승 ➔ 4순위 다득점 (승자승 제외)';
        detailRule =
            '• 파트너가 매 라운드 바뀌고 개인별 출전 경기 수 편차가 발생할 수 있으므로 승률(%)을 1순위로 적용하며, 개인전 특성상 승자승은 제외합니다.';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pastelPeriwinkle.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppTheme.pastelPeriwinkleDark,
              ),
              const SizedBox(width: 6),
              Text(
                '순위 결정 기준 안내 ($modeLabel)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.pastelPeriwinkleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              criteriaDescription,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detailRule,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.textDark,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// ① [라운드별 스코어] 탭 (모든 경기 상세 기록 + 상단 라운드 필터 칩 전체, 1R, 2R, 3R...)
  Widget _buildRoundByRoundScoreTab({
    required GameSession session,
    required List<GameMatch> matches,
    required List<Member> members,
  }) {
    final memberMap = {for (final m in members) m.id: m};
    final rounds = matches.map((m) => m.round).toSet().toList()..sort();

    final filteredMatches = matches
        .where((m) => _scoreFilterRound == null || m.round == _scoreFilterRound)
        .toList()
      ..sort((a, b) {
        final rCmp = a.round.compareTo(b.round);
        return rCmp != 0 ? rCmp : a.courtNumber.compareTo(b.courtNumber);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 상단 라운드 필터 칩 (전체, 1R, 2R, 3R...)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildRoundFilterChip(
                label: '전체',
                isSelected: _scoreFilterRound == null,
                onTap: () => setState(() => _scoreFilterRound = null),
              ),
              ...rounds.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildRoundFilterChip(
                    label: '${r}R',
                    isSelected: _scoreFilterRound == r,
                    onTap: () => setState(() => _scoreFilterRound = r),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (filteredMatches.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text(
                '기록된 경기 스코어가 없습니다.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            ),
          )
        else
          ...filteredMatches.map(
            (match) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildScoreboardMatchCard(
                match: match,
                memberMap: memberMap,
                isLiveScoreboard: false,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoundFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: isSelected ? Colors.white : AppTheme.textDark,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(MatchStatus status) {
    Color color;
    switch (status) {
      case MatchStatus.pending:
        color = AppTheme.statusPending;
        break;
      case MatchStatus.playing:
        color = AppTheme.statusPlaying;
        break;
      case MatchStatus.finished:
        color = AppTheme.statusFinished;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
