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

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Stack(
            children: [
              // 메인 화면
              IndexedStack(
                index: currentTab,
                children: _screens,
              ),

              // 참조 이미지 스타일의 플로팅 알약(Pill) 네비게이션 바
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildNavPillItem(
                          ref: ref,
                          currentTab: currentTab,
                          index: 0,
                          icon: Icons.people_alt_rounded,
                          label: '회원명부',
                        ),
                        const SizedBox(width: 8),
                        _buildNavPillItem(
                          ref: ref,
                          currentTab: currentTab,
                          index: 1,
                          icon: Icons.checklist_rtl_rounded,
                          label: '출석부',
                        ),
                        const SizedBox(width: 8),
                        _buildNavPillItem(
                          ref: ref,
                          currentTab: currentTab,
                          index: 2,
                          icon: Icons.sports_tennis_rounded,
                          label: '대진표',
                        ),
                        const SizedBox(width: 8),
                        _buildNavPillItem(
                          ref: ref,
                          currentTab: currentTab,
                          index: 3,
                          icon: Icons.visibility_rounded,
                          label: '웹뷰어',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavPillItem({
    required WidgetRef ref,
    required int currentTab,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = currentTab == index;

    return InkWell(
      onTap: () {
        ref.read(currentTabProvider.notifier).setTab(index);
      },
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : AppTheme.textMuted,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
