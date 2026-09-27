import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';
import 'views/club/club_member_pool_screen.dart';
import 'views/session/session_attendance_screen.dart';
import 'views/court/court_operation_screen.dart';
import 'views/fee/membership_fee_ledger_screen.dart';
import 'views/viewer/live_viewer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: CockMatchApp(),
    ),
  );
}

class CockMatchApp extends StatelessWidget {
  const CockMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        final uri = Uri.tryParse(name);
        if (uri != null && uri.path == '/viewer/fees') {
          final clubId = uri.queryParameters['clubId'];
          final year = int.tryParse(uri.queryParameters['year'] ?? '') ?? 2026;
          final month = int.tryParse(uri.queryParameters['month'] ?? '') ?? 9;
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => FeeStatusWebViewerScreen(
              clubId: clubId,
              initialYear: year,
              initialMonth: month,
            ),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const CockMatchShellScreen(),
        );
      },
      home: const CockMatchShellScreen(),
    );
  }
}

class CockMatchShellScreen extends ConsumerStatefulWidget {
  const CockMatchShellScreen({super.key});

  @override
  ConsumerState<CockMatchShellScreen> createState() => _CockMatchShellScreenState();
}

class _CockMatchShellScreenState extends ConsumerState<CockMatchShellScreen> {
  /// 모바일 좌우 스와이프는 [회원명부(0) ↔ 출석부(1) ↔ 대진표(2)] 3개 화면만 연결
  static const List<Widget> _swipeScreens = [
    ClubMemberPoolScreen(), // 0: 회원명부 (기본 회원 DB 관리)
    SessionAttendanceScreen(), // 1: 출석부 (오늘 모임 생성 및 출석 체크)
    CourtOperationScreen(), // 2: 대진표 (코트 배정 및 실시간 점수 기록)
  ];

  void _handleHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final currentTab = ref.read(currentTabProvider);
    if (currentTab < 0 || currentTab > 2) return;

    // 왼쪽으로 스와이프 (다음 화면: 회원명부 0 -> 출석부 1 -> 대진표 2, 전광판(3)으로는 절대 넘어가지 않음)
    if (velocity < -250 && currentTab < 2) {
      ref.read(currentTabProvider.notifier).setTab(currentTab + 1);
    }
    // 오른쪽으로 스와이프 (이전 화면: 대진표 2 -> 출석부 1 -> 회원명부 0)
    else if (velocity > 250 && currentTab > 0) {
      ref.read(currentTabProvider.notifier).setTab(currentTab - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);
    final currentClub = ref.watch(currentClubProvider);
    final activeSession = ref.watch(sessionProvider);
    final isProUser = ref.watch(isProUserProvider);

    Widget activeBody;
    if (currentTab == 3) {
      // 실시간 전광판 웹뷰어는 경기 운영 화면 스와이프에서 제외하고 독립 실행
      activeBody = const LiveViewerScreen(sessionId: 'session_mega_today');
    } else if (currentTab == 4 && isProUser) {
      // 구독자(isProUser == true) 상태에서만 회비 현황표 전체 기능 오픈
      activeBody = const MembershipFeeLedgerScreen();
    } else {
      activeBody = GestureDetector(
        key: const Key('main_three_tab_page_view'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _handleHorizontalSwipe,
        child: IndexedStack(
          index: currentTab.clamp(0, 2),
          children: _swipeScreens,
        ),
      );
    }

    return Scaffold(
      key: AppTheme.rootScaffoldKey,
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: false,
      drawer: _buildAppDrawer(
        context: context,
        ref: ref,
        currentTab: currentTab,
        clubName: currentClub.clubName,
        sessionTitle: activeSession?.title,
        isProUser: isProUser,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (currentTab == 4 && isProUser) ? 1080 : 700,
          ),
          child: activeBody,
        ),
      ),
    );
  }

  void _showProFeeFeatureGuideModal(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.pastelPeriwinkle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: AppTheme.primaryDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '클럽 총무님을 위한 연간 회비 장부 및 미납 알림 기능 안내',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.pastelMint.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '🔒 [월회비 관리]는 PRO 구독 클럽 전용 프리미엄 재정 관리 기능입니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.pastelMintDark,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• 1월~12월 연간 납부 매트릭스 장부 & [1년 일괄 완납] 원터치 처리\n'
              '• 클럽 기본 월 회비·납부 마감일·입금 계좌 및 회칙 메모 영구 보관\n'
              '• [📢 당월 미납자 알림 문구 복사] 카톡 자동 생성\n'
              '• [📸 장부 이미지 내보내기] 및 실시간 회비 웹뷰어 링크 공유',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('close_pro_guide_modal_button'),
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              '닫기',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton.icon(
            key: const Key('activate_pro_and_open_fee_ledger_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              ref.read(isProUserProvider.notifier).setProStatus(true);
              Navigator.pop(dialogCtx);
              ref.read(currentTabProvider.notifier).setTab(4);
            },
            icon: const Icon(Icons.lock_open_rounded, size: 16),
            label: const Text(
              'PRO 구독 활성화 후 열기',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppDrawer({
    required BuildContext context,
    required WidgetRef ref,
    required int currentTab,
    required String clubName,
    required String? sessionTitle,
    required bool isProUser,
  }) {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      width: 280,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 드로어 상단 클럽 헤더
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7565E8), Color(0xFF8E7FF2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7565E8).withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('🏸', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '콕매치 (CockMatch)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              clubName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (sessionTitle != null && sessionTitle.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.fiber_manual_record_rounded,
                            size: 10,
                            color: Color(0xFF6EF2FC),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '진행 모임: $sessionTitle',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(
                '메뉴 이동',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerMenuItem(
                    context: context,
                    ref: ref,
                    currentTab: currentTab,
                    index: 0,
                    icon: Icons.people_alt_rounded,
                    label: '회원명부',
                    subtitle: '회원정보 및 급수·회비 관리',
                  ),
                  _buildDrawerMenuItem(
                    context: context,
                    ref: ref,
                    currentTab: currentTab,
                    index: 1,
                    icon: Icons.checklist_rtl_rounded,
                    label: '출석부',
                    subtitle: '당일 출석 체크 및 회비 수납',
                  ),
                  _buildDrawerMenuItem(
                    context: context,
                    ref: ref,
                    currentTab: currentTab,
                    index: 2,
                    icon: Icons.sports_tennis_rounded,
                    label: '대진표',
                    subtitle: '코트 배정 및 실시간 점수 기록',
                  ),
                  _buildDrawerMenuItem(
                    context: context,
                    ref: ref,
                    currentTab: currentTab,
                    index: 3,
                    icon: Icons.live_tv_rounded,
                    label: '웹뷰어',
                    subtitle: '실시간 전광판 웹뷰어 및 종합 리포트',
                  ),
                  _buildDrawerMenuItem(
                    context: context,
                    ref: ref,
                    currentTab: currentTab,
                    index: 4,
                    icon: Icons.account_balance_wallet_rounded,
                    label: '월회비 관리 🔒',
                    subtitle: isProUser
                        ? 'PRO 활성화됨 · 연간/월별 회비 현황표'
                        : 'PRO 전용 · 연간 회비 장부 및 미납 알림',
                    onCustomTap: () {
                      final rootContext = AppTheme.rootScaffoldKey.currentContext ?? context;
                      Navigator.of(context).pop();
                      if (!ref.read(isProUserProvider)) {
                        _showProFeeFeatureGuideModal(rootContext, ref);
                      } else {
                        ref.read(currentTabProvider.notifier).setTab(4);
                      }
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isProUser ? Icons.verified_rounded : Icons.lock_outline_rounded,
                    size: 16,
                    color: isProUser ? AppTheme.primaryMint : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isProUser ? 'PRO 플랜 구독 중 (회비 장부 열림)' : '무료 플랜 (PRO 잠금 테스트)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Switch(
                    key: const Key('drawer_pro_status_switch'),
                    value: isProUser,
                    activeThumbColor: AppTheme.primaryMint,
                    onChanged: (val) {
                      ref.read(isProUserProvider.notifier).setProStatus(val);
                      if (!val && ref.read(currentTabProvider) == 4) {
                        ref.read(currentTabProvider.notifier).setTab(1);
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_rounded, size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '좌우 스와이프: 회원명부 ↔ 출석부 ↔ 대진표 전환',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerMenuItem({
    required BuildContext context,
    required WidgetRef ref,
    required int currentTab,
    required int index,
    required IconData icon,
    required String label,
    required String subtitle,
    VoidCallback? onCustomTap,
  }) {
    final isSelected = currentTab == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: InkWell(
        key: Key('drawer_menu_item_$index'),
        borderRadius: BorderRadius.circular(16),
        onTap: onCustomTap ??
            () {
              ref.read(currentTabProvider.notifier).setTab(index);
              Navigator.of(context).pop();
            },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.pastelPeriwinkle : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryMint : AppTheme.surfaceGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.primaryDark,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
