import 'package:flutter/material.dart';
import '../constants/enums.dart';

/// 콕매치(CockMatch) 파스텔 벤토 그리드 테마 및 디자인 시스템
/// (참조 이미지: 소프트 파스텔 코랄, 페리윙클, 민트, 버터옐로우 & 둥근 카드)
class AppTheme {
  AppTheme._();

  // 배경 및 메인 서피스
  static const Color background = Color(0xFFF8F9FE); // 매우 부드러운 오프화이트/라벤더 그레이
  static const Color surfaceGrey = Color(0xFFF3F5FA); // 카드 내부 서피스 그레이
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF1E2432); // 딥 네이비 슬레이트
  static const Color textMuted = Color(0xFF8A94A6);

  // 참조 이미지 기반 파스텔 팔레트 (Bento Card Colors)
  static const Color pastelCoral = Color(0xFFFFE5E1); // 부드러운 코랄/피치 (Breakfast/IBM 카드)
  static const Color pastelCoralDark = Color(0xFFE26D5C);
  static const Color coralRed = Color(0xFFE26D5C);

  static const Color pastelPeriwinkle = Color(0xFFE6E8FE); // 소프트 페리윙클/라벤더 (Progress 카드)
  static const Color pastelPeriwinkleDark = Color(0xFF535EC9);

  static const Color pastelMint = Color(0xFFDCF4EE); // 소프트 민트/아쿠아 (Sleep quality 카드)
  static const Color pastelMintDark = Color(0xFF2C9E86);

  static const Color pastelYellow = Color(0xFFFEF3D6); // 소프트 버터/오렌지크림 (Sport Data 카드)
  static const Color pastelYellowDark = Color(0xFFD98A17);

  static const Color pastelRose = Color(0xFFFFE8F0); // 소프트 로즈
  static const Color pastelRoseDark = Color(0xFFD9487D);

  // 기본 브랜드 컬러
  static const Color primaryMint = Color(0xFF2CB69A);
  static const Color primaryGreen = primaryMint; // 하위 호환
  static const Color primaryDark = Color(0xFF19202E);

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static Color getTierColor(Tier tier) => getTierTextColor(tier);

  // 급수별 파스텔 매칭 컬러
  static Color getTierBgColor(Tier tier) {
    switch (tier) {
      case Tier.a:
        return pastelCoral;
      case Tier.b:
        return pastelYellow;
      case Tier.c:
        return pastelPeriwinkle;
      case Tier.d:
        return pastelMint;
      case Tier.novice:
        return pastelRose;
    }
  }

  static Color getTierTextColor(Tier tier) {
    switch (tier) {
      case Tier.a:
        return pastelCoralDark;
      case Tier.b:
        return pastelYellowDark;
      case Tier.c:
        return pastelPeriwinkleDark;
      case Tier.d:
        return pastelMintDark;
      case Tier.novice:
        return pastelRoseDark;
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

  // 성별 카드 구분 컬러 (남성: 은은한 블루톤 / 여성: 은은한 핑크·코랄톤)
  static const Color maleCardBg = Color(0xFFF2F6FF);
  static const Color maleCardBorder = Color(0xFFD2E0FB);
  static const Color maleCardAccent = Color(0xFF3B6FD8);

  static const Color femaleCardBg = Color(0xFFFFF3F5);
  static const Color femaleCardBorder = Color(0xFFFAD0D9);
  static const Color femaleCardAccent = Color(0xFFDE5475);

  static Color getGenderCardBg(Gender gender, {bool isDimmed = false}) {
    if (isDimmed) {
      return gender == Gender.male
          ? const Color(0xFFF6F8FC)
          : const Color(0xFFFCF6F7);
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
      return gender == Gender.male
          ? maleCardBorder.withValues(alpha: 0.55)
          : femaleCardBorder.withValues(alpha: 0.55);
    }
    return gender == Gender.male ? maleCardBorder : femaleCardBorder;
  }

  static Color getGenderAccentColor(Gender gender) {
    return gender == Gender.male ? maleCardAccent : femaleCardAccent;
  }

  // 상태별 컬러
  static const Color statusPending = Color(0xFF94A3B8);
  static const Color statusPlaying = Color(0xFFE28B15);
  static const Color statusFinished = Color(0xFF16A34A);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      fontFamily: 'Pretendard',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryMint,
        primary: primaryDark,
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
