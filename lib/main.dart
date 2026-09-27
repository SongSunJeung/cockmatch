import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';
import 'views/club/club_member_pool_screen.dart';
import 'views/session/session_attendance_screen.dart';
import 'views/court/court_operation_screen.dart';
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
      home: const CockMatchShellScreen(),
    );
  }
}

class CockMatchShellScreen extends ConsumerWidget {
  const CockMatchShellScreen({super.key});

  static const List<Widget> _screens = [
    ClubMemberPoolScreen(), // 0: 회원명부 (기본 회원 DB 관리)
    SessionAttendanceScreen(), // 1: 출석부 (오늘 모임 생성 및 출석 체크)
    CourtOperationScreen(), // 2: 대진표 (코트 배정 및 실시간 점수 기록)
    LiveViewerScreen(sessionId: 'session_mega_today'), // 3: 웹뷰어 (외부 모니터/회원 공유용 뷰어)
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);
    final currentClub = ref.watch(currentClubProvider);
    final activeSession = ref.watch(sessionProvider);

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
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: IndexedStack(
            index: currentTab,
            children: _screens,
          ),
        ),
      ),
    );
  }

  Widget _buildAppDrawer({
    required BuildContext context,
    required WidgetRef ref,
    required int currentTab,
    required String clubName,
    required String? sessionTitle,
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
              padding: EdgeInsets.fromLTRB(24, 12, 24, 6),
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
              icon: Icons.visibility_rounded,
              label: '웹뷰어',
              subtitle: '실시간 전광판 및 종합 리포트',
            ),

            const Spacer(),
            const Divider(height: 1, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_rounded, size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '회원 카드 탭: 상세·통화·문자 / 길게 누르기: 단체 문자',
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
  }) {
    final isSelected = currentTab == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          ref.read(currentTabProvider.notifier).setTab(index);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
