import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/korean_search_util.dart';
import '../../models/models.dart';

/// [대회/행사 전용] 인터랙티브 토너먼트 브래킷(트리) 위젯
/// - InteractiveViewer 기반으로 상하좌우 2D 팬/스크롤 및 핀치 줌(확대/축소) 지원
/// - 4강, 8강, 16강 브래킷 자동 레이아웃 및 라운드별 연결선 제공
/// - 총무 앱의 점수 입력/경기 완료 시 승자 승급 및 실시간 스코어가 즉시 동기화 반영
class TournamentBracketTreeWidget extends StatefulWidget {
  final List<GameMatch> matches;
  final Map<String, Member> memberMap;
  final String? searchQuery;
  final bool showControls;
  final double initialScale;
  final EdgeInsets? padding;

  const TournamentBracketTreeWidget({
    super.key,
    required this.matches,
    required this.memberMap,
    this.searchQuery,
    this.showControls = true,
    this.initialScale = 1.0,
    this.padding,
  });

  @override
  State<TournamentBracketTreeWidget> createState() =>
      _TournamentBracketTreeWidgetState();
}

class _TournamentBracketTreeWidgetState
    extends State<TournamentBracketTreeWidget> {
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    if (widget.initialScale != 1.0) {
      _transformationController.value =
          Matrix4.diagonal3Values(widget.initialScale, widget.initialScale, 1.0);
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    setState(() {
      _transformationController.value = Matrix4.identity();
    });
  }

  void _zoomIn() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.25).clamp(0.4, 2.5);
    setState(() {
      _transformationController.value =
          Matrix4.diagonal3Values(newScale, newScale, 1.0);
    });
  }

  void _zoomOut() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.25).clamp(0.4, 2.5);
    setState(() {
      _transformationController.value =
          Matrix4.diagonal3Values(newScale, newScale, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.pastelYellow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.emoji_events_outlined,
                color: AppTheme.pastelYellowDark,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '토너먼트 대진표가 아직 생성되지 않았습니다.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showControls) _buildControlToolbar(),
        Expanded(
          child: InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            boundaryMargin: const EdgeInsets.symmetric(
              horizontal: 160,
              vertical: 100,
            ),
            minScale: 0.4,
            maxScale: 2.5,
            child: Padding(
              padding: widget.padding ??
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: _buildTreeLayout(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlToolbar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.pastelYellow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 13,
                  color: AppTheme.pastelYellowDark,
                ),
                SizedBox(width: 4),
                Text(
                  '핀치 줌 & 자유 이동',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.pastelYellowDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '두 손가락 확대/축소 및 상하좌우 드래그 지원',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.zoom_in_rounded, size: 18),
            tooltip: '확대 (+)',
            onPressed: _zoomIn,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.zoom_out_rounded, size: 18),
            tooltip: '축소 (-)',
            onPressed: _zoomOut,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: '100% 원래 크기로 초기화',
            onPressed: _resetZoom,
          ),
        ],
      ),
    );
  }

  Widget _buildTreeLayout() {
    // 라운드별 경기 분류
    final roundMatchesMap = <int, List<GameMatch>>{};
    for (final m in widget.matches) {
      roundMatchesMap.putIfAbsent(m.round, () => []).add(m);
    }

    final rounds = roundMatchesMap.keys.toList()..sort();
    if (rounds.isEmpty) return const SizedBox.shrink();

    // 1라운드 기준 토너먼트 전체 강수 산출 (4, 8, 16 등)
    final r1Matches = roundMatchesMap[1] ?? [];
    final initialBracketSize = r1Matches.isNotEmpty
        ? (r1Matches.first.bracketRoundSize ??
            GameMatch.inferBracketSize(r1Matches.length))
        : 8;

    // 강수 기준 총 라운드 수 계산 (16강=4R, 8강=3R, 4강=2R, 2강=1R)
    int totalRounds;
    if (initialBracketSize <= 2) {
      totalRounds = 1;
    } else if (initialBracketSize <= 4) {
      totalRounds = 2;
    } else if (initialBracketSize <= 8) {
      totalRounds = 3;
    } else {
      totalRounds = 4;
    }
    totalRounds = max(totalRounds, rounds.last);

    // 각 라운드별 슬롯 수 (16강 -> 8, 8강 -> 4, 준결승 -> 2, 결승 -> 1)
    final stageRoundSizes = <int, int>{};
    for (int r = 1; r <= totalRounds; r++) {
      final step = r - 1;
      final size = max(2, initialBracketSize ~/ pow(2, step));
      stageRoundSizes[r] = size;
    }

    // 최종 우승 팀 확인 (결승전 완료 시)
    final finalMatches = roundMatchesMap[totalRounds] ?? [];
    GameMatch? completedFinalMatch;
    for (final m in finalMatches) {
      if (m.isFinished && m.scoreA != m.scoreB) {
        completedFinalMatch = m;
        break;
      }
    }

    const double matchCardWidth = 240.0;
    const double matchCardHeight = 112.0;
    const double columnSpacing = 56.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int r = 1; r <= totalRounds; r++) ...[
          _buildStageColumn(
            round: r,
            bracketSize: stageRoundSizes[r] ?? 4,
            matches: roundMatchesMap[r] ?? [],
            cardWidth: matchCardWidth,
            cardHeight: matchCardHeight,
            totalRounds: totalRounds,
          ),
          if (r < totalRounds) ...[
            SizedBox(
              width: columnSpacing,
              child: _buildStageConnector(
                currentRound: r,
                currentMatchCount: max(1, (stageRoundSizes[r] ?? 4) ~/ 2),
                nextMatchCount: max(1, (stageRoundSizes[r + 1] ?? 2) ~/ 2),
                cardHeight: matchCardHeight,
              ),
            ),
          ],
        ],
        // 우측 끝: 최종 챔피언 트로피 카드
        const SizedBox(width: columnSpacing),
        _buildChampionColumn(
          completedFinalMatch: completedFinalMatch,
          cardWidth: matchCardWidth,
        ),
      ],
    );
  }

  Widget _buildStageColumn({
    required int round,
    required int bracketSize,
    required List<GameMatch> matches,
    required double cardWidth,
    required double cardHeight,
    required int totalRounds,
  }) {
    final expectedMatchCount = max(1, bracketSize ~/ 2);
    final sortedMatches = List<GameMatch>.from(matches)
      ..sort((a, b) => (a.bracketMatchIndex ?? a.courtNumber)
          .compareTo(b.bracketMatchIndex ?? b.courtNumber));

    final stageTitle = GameMatch.stageTitleForSize(bracketSize);
    final isFinalRound = bracketSize <= 2;

    return SizedBox(
      width: cardWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 라운드 헤더 배너
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isFinalRound ? AppTheme.primaryDark : AppTheme.primaryMint,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: (isFinalRound
                          ? AppTheme.primaryDark
                          : AppTheme.primaryMint)
                      .withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isFinalRound
                      ? Icons.emoji_events_rounded
                      : Icons.sports_tennis_rounded,
                  size: 15,
                  color: isFinalRound ? AppTheme.pastelYellow : Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  isFinalRound
                      ? '결승전 (FINAL)'
                      : (bracketSize == 4 ? '준결승 (4강)' : '$stageTitle ($round R)'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: isFinalRound ? Colors.white : Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // 해당 라운드의 매치 슬롯 리스트
          for (int slotIdx = 1; slotIdx <= expectedMatchCount; slotIdx++) ...[
            Builder(builder: (ctx) {
              final actualMatch = sortedMatches.firstWhere(
                (m) =>
                    m.bracketMatchIndex == slotIdx ||
                    (m.bracketMatchIndex == null &&
                        sortedMatches.indexOf(m) + 1 == slotIdx),
                orElse: () => GameMatch(
                  id: 'placeholder_r${round}_m$slotIdx',
                  sessionId: '',
                  round: round,
                  courtNumber: slotIdx,
                  teamA: const [],
                  teamB: const [],
                  bracketRoundSize: bracketSize,
                  bracketMatchIndex: slotIdx,
                  status: MatchStatus.pending,
                ),
              );

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _buildMatchSlotCard(
                  match: actualMatch,
                  stageTitle: stageTitle,
                  slotIndex: slotIdx,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchSlotCard({
    required GameMatch match,
    required String stageTitle,
    required int slotIndex,
    required double cardWidth,
    required double cardHeight,
  }) {
    final teamA = match.teamA;
    final teamB = match.teamB;
    final isFinished = match.isFinished;
    final isPlaying = match.isPlaying;
    final isTeamAWon = match.isTeamAWon || (isFinished && match.scoreA > match.scoreB);
    final isTeamBWon = match.isTeamBWon || (isFinished && match.scoreB > match.scoreA);

    final allMemberNames = [
      ...teamA.map((id) => widget.memberMap[id]?.name ?? id),
      ...teamB.map((id) => widget.memberMap[id]?.name ?? id),
    ];
    final isHighlighted = widget.searchQuery != null &&
        widget.searchQuery!.isNotEmpty &&
        allMemberNames.any((n) => KoreanSearchUtil.matches(n, widget.searchQuery!));

    final matchLabel = match.formatTournamentMatchLabel(
      indexInRound: slotIndex,
    );

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted
              ? AppTheme.primaryMint
              : (isFinished
                  ? AppTheme.primaryMint.withValues(alpha: 0.6)
                  : (isPlaying
                      ? AppTheme.pastelYellowDark
                      : Colors.grey.shade300)),
          width: isHighlighted ? 2.4 : (isPlaying || isFinished ? 1.8 : 1.0),
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: AppTheme.primaryMint.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : AppTheme.softShadow,
      ),
      child: Column(
        children: [
          // 매치 헤더 바: [8강 1경기] + [코트 n] + [상태]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isFinished
                  ? AppTheme.pastelMint.withValues(alpha: 0.4)
                  : (isPlaying
                      ? AppTheme.pastelYellow.withValues(alpha: 0.5)
                      : AppTheme.surfaceGrey),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      matchLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${match.courtNumber}코트',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                _buildMiniStatusBadge(match.status, isFinished: isFinished),
              ],
            ),
          ),

          // 슬롯 1 (Team A)
          Expanded(
            child: _buildTeamSlotRow(
              teamIds: teamA,
              score: match.scoreA,
              isWinner: isTeamAWon,
              isLoser: isFinished && !isTeamAWon,
              placeholderText: '이전 경기 승자 대기 (TBD)',
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          // 슬롯 2 (Team B)
          Expanded(
            child: _buildTeamSlotRow(
              teamIds: teamB,
              score: match.scoreB,
              isWinner: isTeamBWon,
              isLoser: isFinished && !isTeamBWon,
              placeholderText: '이전 경기 승자 대기 (TBD)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamSlotRow({
    required List<String> teamIds,
    required int score,
    required bool isWinner,
    required bool isLoser,
    required String placeholderText,
  }) {
    if (teamIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_empty_rounded,
              size: 13,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                placeholderText,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  fontStyle: FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Text(
              '-',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final members = teamIds.map((id) => widget.memberMap[id]).toList();
    final names = members.map((m) => m?.name ?? '선수').join('·');

    return Container(
      color: isWinner
          ? AppTheme.pastelMint.withValues(alpha: 0.3)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // 팀 급수 뱃지들
          Row(
            mainAxisSize: MainAxisSize.min,
            children: members.map((m) {
              if (m == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(right: 3),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.getTierBgColor(m.tier),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  m.tier.label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.getTierTextColor(m.tier),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 4),
          // 팀원 이름
          Expanded(
            child: Text(
              names,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isWinner ? FontWeight.w900 : FontWeight.w700,
                color: isLoser ? Colors.grey.shade500 : AppTheme.textDark,
                decoration: isLoser ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isWinner) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primaryMint,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'WIN',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          // 점수
          Text(
            '$score',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isWinner ? FontWeight.w900 : FontWeight.w700,
              color: isWinner ? AppTheme.primaryDark : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusBadge(MatchStatus status, {required bool isFinished}) {
    Color bg;
    Color fg;
    String label;

    if (isFinished) {
      bg = AppTheme.pastelMint;
      fg = AppTheme.pastelMintDark;
      label = '완료';
    } else if (status == MatchStatus.playing) {
      bg = AppTheme.pastelYellow;
      fg = AppTheme.pastelYellowDark;
      label = '진행중';
    } else {
      bg = Colors.grey.shade200;
      fg = AppTheme.textMuted;
      label = '대기';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildStageConnector({
    required int currentRound,
    required int currentMatchCount,
    required int nextMatchCount,
    required double cardHeight,
  }) {
    return CustomPaint(
      painter: _BracketConnectorPainter(
        color: AppTheme.primaryMint.withValues(alpha: 0.6),
        strokeWidth: 2.0,
      ),
      child: Container(),
    );
  }

  Widget _buildChampionColumn({
    required GameMatch? completedFinalMatch,
    required double cardWidth,
  }) {
    final bool hasChampion = completedFinalMatch != null;
    List<String> championIds = const [];
    int winningScore = 0;
    int runnerUpScore = 0;

    if (hasChampion) {
      if (completedFinalMatch.scoreA > completedFinalMatch.scoreB) {
        championIds = completedFinalMatch.teamA;
        winningScore = completedFinalMatch.scoreA;
        runnerUpScore = completedFinalMatch.scoreB;
      } else {
        championIds = completedFinalMatch.teamB;
        winningScore = completedFinalMatch.scoreB;
        runnerUpScore = completedFinalMatch.scoreA;
      }
    }

    final championMembers =
        championIds.map((id) => widget.memberMap[id]).toList();
    final championNames = championMembers.map((m) => m?.name ?? '선수').join(' & ');

    return SizedBox(
      width: cardWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasChampion
                    ? [
                        AppTheme.pastelYellow,
                        Colors.white,
                      ]
                    : [
                        Colors.white,
                        AppTheme.surfaceGrey,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasChampion
                    ? AppTheme.pastelYellowDark
                    : Colors.grey.shade300,
                width: hasChampion ? 2.4 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasChampion
                      ? AppTheme.pastelYellowDark.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: hasChampion
                        ? AppTheme.pastelYellowDark
                        : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      hasChampion ? '🏆' : '🥇',
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  hasChampion ? '최종 우승 (CHAMPION)' : '우승 대기',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: hasChampion
                        ? AppTheme.pastelYellowDark
                        : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (hasChampion) ...[
                  Text(
                    championNames,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.pastelYellowDark.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '결승 스코어 $winningScore : $runnerUpScore',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    '결승전 경기 완료 시\n우승 팀이 확정됩니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.4,
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
}

/// 브래킷 피더 매치와 상위 라운드 매치를 연결하는 2D 꺾임선 페인터
class _BracketConnectorPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _BracketConnectorPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midX = size.width / 2;

    // 좌측 상단/하단 피더 매치에서 중앙으로 모여 우측으로 나가는 수평+수직 연결선
    final path = Path()
      // 상단 피더에서 중앙으로
      ..moveTo(0, size.height * 0.25)
      ..lineTo(midX, size.height * 0.25)
      // 하단 피더에서 중앙으로
      ..moveTo(0, size.height * 0.75)
      ..lineTo(midX, size.height * 0.75)
      // 상단과 하단을 잇는 수직선
      ..moveTo(midX, size.height * 0.25)
      ..lineTo(midX, size.height * 0.75)
      // 중앙에서 다음 라운드 매치로 진출하는 수평선
      ..moveTo(midX, size.height * 0.5)
      ..lineTo(size.width, size.height * 0.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
