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
  // [시범 적용] 5개 핵심 페이지별 포인트 컬러(Accent Color) 시스템
  // - 추후 언제든 단일 톤으로 즉시 롤백할 수 있도록 스위치 플래그 및 팔레트 객체로 분리
  // ===========================================================================
  static bool usePageSpecificAccentThemes = true;

  /// 단일 톤 롤백 시 사용되는 기본 팔레트
  static const PageAccentPalette unifiedDefaultPalette = PageAccentPalette(
    pageIndex: 0,
    pageName: '콕매치',
    toneLabel: '기본 라벤더 톤',
    primary: primaryDark,
    secondary: primaryMint,
    softTint: pastelPeriwinkle,
    borderTint: Color(0xFFD2CCFA),
  );

  /// 5개 핵심 페이지별 포인트 테마 팔레트 매핑 (HEX)
  /// 0: 회원 명단 - TEAL/GRAY 계열 (#455A64, 보조 #80CBC4)
  /// 1: 출석부 - SAGE 그린 계열 (#527F5B, 보조 #A3C9A8)
  /// 2: 대진표 운영 - LAVENDER 퍼플 계열 (#5E4B8B, 보조 #7D6CC4)
  /// 3: 실시간 웹뷰어(전광판) - ARCTIC 블루 계열 (#1E88E5, 보조 #64B5F6)
  /// 4: 월회비 관리(PRO) - MUSTARD 골드 계열 (#D4A017, 보조 #F0C94C)
  static const List<PageAccentPalette> pagePalettes = [
    PageAccentPalette(
      pageIndex: 0,
      pageName: '회원 명단',
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
      pageName: '대진표 운영',
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

  /// 현재 페이지 인덱스(0~4)에 맞는 포인트 컬러 팔레트 반환
  /// `usePageSpecificAccentThemes == false` 설정 시 즉시 단일 톤으로 롤백됨
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

  /// 현재 페이지 인덱스(0~4)의 텍스트형 도트 문자열 반환 (예: "● ○ ○ ○ ○")
  static String buildDotIndicatorString(int currentIndex) {
    final safeIndex = currentIndex.clamp(0, 4);
    return List.generate(5, (i) => i == safeIndex ? '●' : '○').join(' ');
  }

  /// 상단 헤더 영역에 배치되는 슬림한 페이지 위치 인디케이터 (`● ○ ○ ○ ○`)
  static Widget buildSlimPageIndicator({
    required int currentIndex,
    ValueChanged<int>? onPageTap,
  }) {
    final palette = getPagePalette(currentIndex);
    final dotText = buildDotIndicatorString(currentIndex);

    return Container(
      key: Key('top_page_dot_indicator_$currentIndex'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: palette.softTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dotText,
            key: const Key('slim_page_dots_text'),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: palette.primary,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${currentIndex.clamp(0, 4) + 1}/5 ${palette.pageName}',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: palette.primary,
              height: 1.0,
            ),
          ),
        ],
      ),
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

