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
        if (uri != null && (uri.path.startsWith('/viewer') || uri.path.startsWith('/live'))) {
          final segments = uri.pathSegments;
          final sessionId = segments.length >= 2 ? segments.last : 'session_mega_today';
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => LiveViewerScreen(
              sessionId: sessionId == 'viewer' || sessionId == 'live' ? 'session_mega_today' : sessionId,
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

    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(bottom: 0),
        viewPadding: mq.viewPadding.copyWith(bottom: 0),
      ),
      child: Scaffold(
        key: AppTheme.rootScaffoldKey,
        backgroundColor: AppTheme.background,
        resizeToAvoidBottomInset: false,
        drawer: _buildAppDrawer(
          context: context,
          ref: ref,
          currentTab: currentTab,
          clubName: currentClub.clubName,
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
      ),
    );
  }

  void _showProFeeFeatureGuideModal(BuildContext context, WidgetRef ref) {
    final feePalette = AppTheme.getPagePalette(4);
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
                color: feePalette.softTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                color: feePalette.primary,
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
                color: feePalette.softTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '🔒 [금전출납부]는 PRO 구독 클럽 전용 프리미엄 재정 관리 기능입니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: feePalette.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '• 1월~12월 연간 납부 매트릭스 장부 & [1년 일괄 완납] 원터치 처리\n'
              '• 일상 지출(대관료·셔틀콕·비품) 및 일반 수입(가입비·찬조금) 통합 기록\n'
              '• 행사/모임별 참가비·지출 정산 및 영수증 증빙 사진 첨부\n'
              '• [📢 당월 미납자 알림 문구 복사], [📸 장부 이미지 내보내기], 실시간 웹뷰어 공유',
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
              backgroundColor: feePalette.primary,
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

  /// 드로어 상단 클럽 드롭다운에서 '+ 새 모임/클럽 만들기' 선택 시 열리는 생성 다이얼로그
  void _showDrawerCreateClubDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_business_rounded, color: AppTheme.primaryMint),
            SizedBox(width: 8),
            Text(
              '새 모임/클럽 만들기',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '독립된 회원 명부와 대진표, 금전출납부를 관리할 새 모임/클럽을 만듭니다.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: '클럽 / 모임 이름 (필수)',
                hintText: '예: 서초 번개콕, 일요 모닝배턴',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: '모임 일정 / 설명 (선택)',
                hintText: '예: 매주 일요일 08시 · 3코트',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMint,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final desc = descCtrl.text.trim();
              final newClub = ref.read(clubsProvider.notifier).createClub(
                    name,
                    description: desc.isNotEmpty ? desc : null,
                  );

              ref.read(currentClubIdProvider.notifier).switchClub(newClub.id);

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.primaryDark,
                  content: Text(
                    '[${newClub.clubName}] 새 모임/클럽이 생성되어 활성화되었습니다!',
                  ),
                ),
              );
            },
            child: const Text('생성 및 전환'),
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
    required bool isProUser,
  }) {
    final activePalette = AppTheme.getPagePalette(currentTab);
    final clubs = ref.watch(clubsProvider);
    final currentClubId = ref.watch(currentClubIdProvider);

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
            // 드로어 상단 클럽 헤더 (브랜드명 '쓸만한 민턴총무' + 클럽 드롭다운 선택기 '▾')
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [activePalette.primary, activePalette.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: activePalette.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
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
                          AppConstants.appName,
                          key: const Key('drawer_brand_title'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.88),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        PopupMenuButton<String>(
                          key: const Key('drawer_club_selector_button'),
                          tooltip: '클럽/모임 전환 및 생성',
                          offset: const Offset(0, 36),
                          color: Colors.white,
                          elevation: 10,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onSelected: (value) {
                            final rootContext =
                                AppTheme.rootScaffoldKey.currentContext ??
                                context;
                            if (value == '__create_new_club__') {
                              _showDrawerCreateClubDialog(rootContext, ref);
                            } else {
                              ref
                                  .read(currentClubIdProvider.notifier)
                                  .switchClub(value);
                              final selectedClub = clubs
                                  .where((c) => c.id == value)
                                  .firstOrNull;
                              if (selectedClub != null) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppTheme.primaryDark,
                                    content: Text(
                                      '[${selectedClub.clubName}] 클럽으로 전환되었습니다.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            ...clubs.map((club) {
                              final isSelected = club.id == currentClubId;
                              return PopupMenuItem<String>(
                                value: club.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppTheme.primaryMint
                                            : AppTheme.pastelPeriwinkle,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        club.clubName.isNotEmpty
                                            ? club.clubName.characters.first
                                            : '콕',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: isSelected
                                              ? Colors.white
                                              : AppTheme.pastelPeriwinkleDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            club.clubName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w900
                                                  : FontWeight.w700,
                                              color: AppTheme.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            club.description ??
                                                '회원 ${club.memberCount}명',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.textMuted,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 17,
                                        color: AppTheme.primaryMint,
                                      ),
                                  ],
                                ),
                              );
                            }),
                            const PopupMenuDivider(),
                            const PopupMenuItem<String>(
                              key: Key('drawer_create_club_menu_item'),
                              value: '__create_new_club__',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 18,
                                    color: AppTheme.primaryDark,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '+ 새 모임/클럽 만들기',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    clubName,
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  '▾',
                                  key: Key('drawer_club_dropdown_arrow'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    label: '모임/행사',
                    subtitle: '모임 출석 체크 및 참가비 수납',
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
                    label: '금전출납부',
                    subtitle: '월회비 · 일반운영비 · 행사 정산',
                    showLockBadge: !isProUser,
                    onCustomTap: () {
                      final rootContext =
                          AppTheme.rootScaffoldKey.currentContext ?? context;
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
                    isProUser
                        ? Icons.verified_rounded
                        : Icons.lock_outline_rounded,
                    size: 16,
                    color: isProUser
                        ? AppTheme.getPagePalette(4).primary
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isProUser
                          ? 'PRO 플랜 구독 중 (회비 장부 열림)'
                          : '무료 플랜 (PRO 잠금 테스트)',
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
                    activeThumbColor: AppTheme.getPagePalette(4).primary,
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
                  const Icon(
                    Icons.touch_app_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '좌우 스와이프: 회원명부 ↔ 모임/행사 ↔ 대진표 전환',
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
    bool showLockBadge = false,
    VoidCallback? onCustomTap,
  }) {
    final isSelected = currentTab == index;
    final itemPalette = AppTheme.getPagePalette(index);

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
            color: isSelected ? itemPalette.softTint : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? itemPalette.primary : itemPalette.softTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : itemPalette.primary,
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
                            label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: isSelected
                                  ? itemPalette.primary
                                  : AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showLockBadge) ...[
                          const SizedBox(width: 4),
                          const Text('🔒', style: TextStyle(fontSize: 12)),
                        ],
                      ],
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: itemPalette.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
