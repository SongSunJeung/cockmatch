import 'package:flutter/material.dart';
import '../constants/enums.dart';

/// 콕매치(CockMatch) 파스텔 벤토 그리드 테마 및 디자인 시스템
/// (참조 이미지: 소프트 파스텔 코랄, 페리윙클, 민트, 버터옐로우 & 둥근 카드)
class AppTheme {
  AppTheme._();

  // 배경 및 메인 서피스 (클린 화이트 & 에어리 쿨 라벤더 베이스)
  static const Color background = Color(0xFFF6F7FC); // 매우 깨끗한 쿨 라벤더 오프화이트
  static const Color surfaceGrey = Color(0xFFEEF0F8); // 카드 내부 및 비활성 필 서피스
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF22263A); // 딥 인디고 차콜 타이포그래피
  static const Color textMuted = Color(0xFF8E94AA); // 차분한 쿨 슬레이트 그레이
  static const Color textPrimary = textDark;
  static const Color textSecondary = textMuted;

  // 통일된 3톤 파스텔 팔레트 (소프트 라벤더 · 스카이 아쿠아 · 소프트 살몬 코랄)
  static const Color pastelCoral = Color(0xFFFFF0EE); // 소프트 살몬 코랄 (경고/미납/포인트)
  static const Color pastelCoralDark = Color(0xFFE2665A);
  static const Color coralRed = Color(0xFFE2665A);
  static const Color errorRed = pastelCoralDark;

  static const Color pastelPeriwinkle = Color(0xFFEEEBFF); // 시그니처 소프트 라벤더 필 (Insight/Journal 톤)
  static const Color pastelPeriwinkleDark = Color(0xFF5A4AD1);

  static const Color pastelMint = Color(0xFFE6F7FA); // 소프트 스카이 아쿠아 (출전/완납/긍정 상태)
  static const Color pastelMintDark = Color(0xFF2490A6);
  static const Color pastelBlue = Color(0xFFE6F7FA);
  static const Color pastelBlueDark = Color(0xFF2490A6);
  static const Color accentBlue = pastelBlueDark;

  // 기존 노란색/핫핑크 난립을 막기 위해 소프트 라벤더 및 소프트 코랄로 톤앤매너 단일화
  static const Color pastelYellow = Color(0xFFEEEBFF); // 코트 뱃지·휴식 뱃지도 차분한 라벤더 필로 통일
  static const Color pastelYellowDark = Color(0xFF6353D6);

  static const Color pastelRose = Color(0xFFFFF0EE); // 소프트 코랄과 단일화하여 색상 충돌 제거
  static const Color pastelRoseDark = Color(0xFFE2665A);

  // 메인 브랜드 컬러 (참조 이미지의 시그니처 소프트 바이올렛-인디고)
  static const Color primaryMint = Color(0xFF7565E8); // 메인 퍼플-인디고 (Add Drink / Add Meal / + 버튼 톤)
  static const Color primaryGreen = primaryMint; // 하위 호환
  static const Color primaryDark = Color(0xFF5A4AD1); // 딥 바이올렛-인디고 (검정색 대신 부드러운 딥 인디고)

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF5A4AD1).withValues(alpha: 0.055),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ];

  static Color getTierColor(Tier tier) => getTierTextColor(tier);

  // 급수별 톤앤매너 통일 컬러 (무지개색 충돌을 없애고 바이올렛 -> 페리윙클 -> 스카이 -> 아쿠아 -> 슬레이트 그라데이션 적용)
  static Color getTierBgColor(Tier tier) {
    switch (tier) {
      case Tier.a:
        return const Color(0xFFE5E0FF); // 딥 라벤더
      case Tier.b:
        return const Color(0xFFEEEBFF); // 소프트 페리윙클
      case Tier.c:
        return const Color(0xFFE6F1FE); // 소프트 스카이 블루
      case Tier.d:
        return const Color(0xFFE5F7FA); // 소프트 스카이 아쿠아
      case Tier.novice:
        return const Color(0xFFEEF0F8); // 클린 쿨 슬레이트
    }
  }

  static Color getTierTextColor(Tier tier) {
    switch (tier) {
      case Tier.a:
        return const Color(0xFF4B3BC2);
      case Tier.b:
        return const Color(0xFF6857E0);
      case Tier.c:
        return const Color(0xFF3972C2);
      case Tier.d:
        return const Color(0xFF2490A6);
      case Tier.novice:
        return const Color(0xFF646B84);
    }
  }

  // 전역 루트 Scaffold Key (좌측 사이드바 Drawer 제어용)
  static final GlobalKey<ScaffoldState> rootScaffoldKey = GlobalKey<ScaffoldState>();

  /// 어느 화면에서나 좌측 사이드바(Drawer)를 여는 헬퍼
  static void openDrawer([BuildContext? context]) {
    final rootState = rootScaffoldKey.currentState;
    if (rootState != null) {
      rootState.openDrawer();
      return;
    }
    if (context != null) {
      Scaffold.maybeOf(context)?.openDrawer();
    }
  }

  // 성별 카드 구분 컬러 (화이트 베이스 위에 아주 은은한 라벤더 블루 vs 살몬 피치 보더 & 좌측 포인트 바)
  static const Color maleCardBg = Color(0xFFFAF9FF);
  static const Color maleCardBorder = Color(0xFFE6E8F8);
  static const Color maleCardAccent = Color(0xFF7565E8);

  static const Color femaleCardBg = Color(0xFFFFFBFB);
  static const Color femaleCardBorder = Color(0xFFF8E6E6);
  static const Color femaleCardAccent = Color(0xFFF0857B);

  static Color getGenderCardBg(Gender gender, {bool isDimmed = false}) {
    if (isDimmed) {
      return const Color(0xFFF7F8FC);
    }
    return gender == Gender.male ? maleCardBg : femaleCardBg;
  }

  static Color getGenderCardBorder(
    Gender gender, {
    bool isSelected = false,
    bool isDimmed = false,
  }) {
    if (isSelected) {
      return gender == Gender.male ? maleCardAccent : femaleCardAccent;
    }
    if (isDimmed) {
      return const Color(0xFFE8EAF2);
    }
    return gender == Gender.male ? maleCardBorder : femaleCardBorder;
  }

  static Color getGenderAccentColor(Gender gender) {
    return gender == Gender.male ? maleCardAccent : femaleCardAccent;
  }

  // 상태별 컬러 (라벤더/아쿠아 테마 조화)
  static const Color statusPending = Color(0xFF8E94AA);
  static const Color statusPlaying = Color(0xFF7565E8);
  static const Color statusFinished = Color(0xFF38B6C8);

  // ===========================================================================
  // 단일 톤(Single-Tone) 시그니처 퍼플/라벤더 테마 설정
  // ===========================================================================
  static bool usePageSpecificAccentThemes = false;

  /// 단일 톤 기본 팔레트 (시그니처 퍼플/라벤더)
  static const PageAccentPalette unifiedDefaultPalette = PageAccentPalette(
    pageIndex: 0,
    pageName: '콕매치',
    toneLabel: '기본 라벤더 톤',
    primary: primaryDark,
    secondary: primaryMint,
    softTint: pastelPeriwinkle,
    borderTint: Color(0xFFD2CCFA),
  );

  /// 5개 페이지 팔레트 정의 (단일 톤 기본값으로 동작하며 필요 시 참조용 유지)
  static const List<PageAccentPalette> pagePalettes = [
    PageAccentPalette(
      pageIndex: 0,
      pageName: '회원 명부',
      toneLabel: 'TEAL/GRAY 명부 톤',
      primary: Color(0xFF455A64),
      secondary: Color(0xFF80CBC4),
      softTint: Color(0xFFE4F2F0),
      borderTint: Color(0xFF80CBC4),
    ),
    PageAccentPalette(
      pageIndex: 1,
      pageName: '출석부',
      toneLabel: 'SAGE 그린 활동 톤',
      primary: Color(0xFF527F5B),
      secondary: Color(0xFFA3C9A8),
      softTint: Color(0xFFEAF3EC),
      borderTint: Color(0xFFA3C9A8),
    ),
    PageAccentPalette(
      pageIndex: 2,
      pageName: '대진표',
      toneLabel: 'LAVENDER 코트 운영 톤',
      primary: Color(0xFF5E4B8B),
      secondary: Color(0xFF7D6CC4),
      softTint: Color(0xFFEDE9F8),
      borderTint: Color(0xFF7D6CC4),
    ),
    PageAccentPalette(
      pageIndex: 3,
      pageName: '실시간 웹뷰어',
      toneLabel: 'ARCTIC 스포츠 블루 톤',
      primary: Color(0xFF1E88E5),
      secondary: Color(0xFF64B5F6),
      softTint: Color(0xFFE3F2FD),
      borderTint: Color(0xFF64B5F6),
    ),
    PageAccentPalette(
      pageIndex: 4,
      pageName: '월회비 관리(PRO)',
      toneLabel: 'MUSTARD 골드 PRO 톤',
      primary: Color(0xFFD4A017),
      secondary: Color(0xFFF0C94C),
      softTint: Color(0xFFFFF8E1),
      borderTint: Color(0xFFF0C94C),
    ),
  ];

  /// 현재 페이지 인덱스(0~4)에 맞는 팔레트 반환 (`usePageSpecificAccentThemes == false`이므로 시그니처 퍼플 단일 톤 반환)
  static PageAccentPalette getPagePalette(int pageIndex) {
    final safeIndex = pageIndex.clamp(0, pagePalettes.length - 1);
    if (!usePageSpecificAccentThemes) {
      return PageAccentPalette(
        pageIndex: safeIndex,
        pageName: pagePalettes[safeIndex].pageName,
        toneLabel: unifiedDefaultPalette.toneLabel,
        primary: unifiedDefaultPalette.primary,
        secondary: unifiedDefaultPalette.secondary,
        softTint: unifiedDefaultPalette.softTint,
        borderTint: unifiedDefaultPalette.borderTint,
      );
    }
    return pagePalettes[safeIndex];
  }

  /// 스와이프 3대 메인 페이지(0: 회원 명부, 1: 출석부, 2: 대진표)의 AppBar 좌측 페이지명 반환
  static String getMainPageTitle(int currentIndex) {
    switch (currentIndex.clamp(0, 2)) {
      case 0:
        return '회원 명부';
      case 1:
        return '출석부';
      case 2:
      default:
        return '대진표';
    }
  }

  /// 스와이프 3대 메인 페이지(0~2)의 3도트 인디케이터 문자열 반환 ("● ○ ○", "○ ● ○", "○ ○ ●")
  static String buildDotIndicatorString(int currentIndex) {
    final safeIndex = currentIndex.clamp(0, 2);
    return List.generate(3, (i) => i == safeIndex ? '●' : '○').join(' ');
  }

  /// AppBar 페이지 타이틀 바로 옆 고정 위치에 표시되는 미니멀 3도트 인디케이터 (`● ○ ○` / `○ ● ○` / `○ ○ ●`)
  static Widget buildSlimPageIndicator({
    required int currentIndex,
    ValueChanged<int>? onPageTap,
  }) {
    final safeIndex = currentIndex.clamp(0, 2);
    final dotText = buildDotIndicatorString(safeIndex);

    return Container(
      key: Key('top_page_dot_indicator_$safeIndex'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: pastelPeriwinkle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        dotText,
        key: const Key('slim_page_dots_text'),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: primaryDark,
          letterSpacing: 1.0,
          height: 1.0,
        ),
      ),
    );
  }

  /// 3개 스와이프 화면(회원 명부 · 출석부 · 대진표) 최상단 AppBar 좌측 고정 헤더
  /// - [☰ 햄버거 메뉴] + [고정 폭 페이지 타이틀] + [고정 위치 ● ○ ○ 3도트 인디케이터]
  /// - 스와이프 시 3개 화면 모두 흔들림 없이 동일한 절대 위치(x, y)를 유지하도록 규격 통일
  static Widget buildMainAppBarLeftHeader({
    required BuildContext context,
    required int currentIndex,
  }) {
    final safeIndex = currentIndex.clamp(0, 2);
    final pageTitle = getMainPageTitle(safeIndex);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
            onPressed: () => openDrawer(context),
            tooltip: '메뉴 열기',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(
              Icons.menu_rounded,
              color: textDark,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            pageTitle,
            key: Key('app_bar_page_title_$safeIndex'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: textDark,
              letterSpacing: -0.3,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
        const SizedBox(width: 6),
        buildSlimPageIndicator(currentIndex: safeIndex),
      ],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      fontFamily: 'Pretendard',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryMint,
        primary: primaryMint,
        secondary: const Color(0xFF4AC7D8),
        surface: background,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
    );
  }
}

/// 페이지별 포인트 컬러(Accent Color) 설정 모델
class PageAccentPalette {
  final int pageIndex;
  final String pageName;
  final String toneLabel;
  final Color primary;
  final Color secondary;
  final Color softTint;
  final Color borderTint;

  const PageAccentPalette({
    required this.pageIndex,
    required this.pageName,
    required this.toneLabel,
    required this.primary,
    required this.secondary,
    required this.softTint,
    required this.borderTint,
  });
}

