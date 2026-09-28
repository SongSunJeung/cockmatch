import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/korean_search_util.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/ad_banner_slot.dart';

/// [화면 5] 유료 플랜(프리미엄) 핵심 기능: '연간/월별 회비 납부 현황표' & 공유 시스템
/// 1. 클럽 기본 회비 정책 및 계좌 정보 헤더 ([기본 월 회비], [정기 납부 마감일], [회비 입금 계좌])
/// 2. [📜 클럽 회비 회칙 & 메모란] (접이식 아코디언 카드 + 총무 텍스트 에디터 영구 저장)
/// 3. 상단 대시보드 통계 & 액션 툴바:
///    - [연도 선택] 드롭다운 + 당월 수납 요약 카드 ([완납 N명], [미납 N명], [면제/휴면 N명], [당월 수납률 및 총 수납액])
///    - 공유 & 내보내기 4대 액션:
///      ① [📷 밴드 공지용 이미지 저장] ('당월 납부 현황 카드' 및 '연간 장부 전체 표' PNG 캡처/저장)
///      ② [🔗 실시간 회비 웹뷰어 링크 복사] (읽기 전용 웹뷰어 URL 복사 + 하단 배너 광고 슬롯 포함)
///      ③ [📢 미납자 카톡 독려 문구 복사] (이번 달 미납자 명단 + 입금 계좌 정중한 독려 문구)
///      ④ [📊 엑셀 다운로드] (1월~12월 연간 장부 데이터 CSV/Excel UTF-8 BOM 다운로드)
/// 4. 연간 월별 회비 매트릭스 테이블 (Table View):
///    - [회원명(직책/상태 뱃지)] | [월 회비 기준액] | [1월]~[12월] 납부 상태 셀 | [연간 납부 합계]
///    - 🟢 완납, 🔴 미납, ⚪ 면제/휴면 셀 클릭 시 빠른 상태 변경 및 입금일자/메모 입력 팝업
///    - 회원 프로필 자동 연동 (차등/할인 금액, 영구/기간 면제, 휴면 기간 자동 면제 세팅)
/// 5. 조회 필터 지원 ([전체 보기], [당월 미납자만 보기], [휴면/면제 회원만 보기])
class MembershipFeeLedgerScreen extends ConsumerStatefulWidget {
  const MembershipFeeLedgerScreen({super.key});

  @override
  ConsumerState<MembershipFeeLedgerScreen> createState() =>
      _MembershipFeeLedgerScreenState();
}

class _MembershipFeeLedgerScreenState
    extends ConsumerState<MembershipFeeLedgerScreen> {
  int _activeSubTab = 0; // 0: [📊 연간 월회비 장부], 1: [🧾 행사비/모임비 출납부]
  int _selectedYear = 2026;
  int _selectedMonth = 9; // 기준 월 (기본 9월)
  FeeLedgerFilter _selectedFilter = FeeLedgerFilter.all;
  bool _isPolicyExpanded = false; // 기본 접힌 상태(Collapsed)
  bool _isRulesAccordionExpanded = false; // 기본 접힌 상태(Collapsed)
  bool _isEditingRules = false;
  bool _sortByNameAsc = true; // 기본: 이름 가나다순 오름차순 (false면 등록순)
  bool _isGroupingEnabled = false; // 회원 그룹화(Grouping) 토글
  final Set<String> _collapsedGroups = {}; // 접힌 그룹 키들
  String? _selectedEventId; // 선택된 행사 출납부 ID
  String _eventFilterType = 'all'; // 'all', 'income', 'expense'

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _rulesController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  List<Member> _filterMembers({
    required List<Member> clubMembers,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required String clubId,
    required ClubFeePolicy policy,
  }) {
    final regularMembers = clubMembers.where((m) => !m.isGuest).toList();

    final filtered = regularMembers.where((member) {
      // 1. 검색어 필터
      if (_searchQuery.trim().isNotEmpty) {
        final matchedName = KoreanSearchUtil.matches(member.name, _searchQuery);
        final matchedRole =
            KoreanSearchUtil.matches(member.displayRoleLabel, _searchQuery);
        if (!matchedName && !matchedRole) return false;
      }

      // 2. 상단 필터 칩
      final currentMonthRec = FeeLedgerCalculator.resolveCellRecord(
        ledgerMap: ledgerMap,
        clubId: clubId,
        year: _selectedYear,
        month: _selectedMonth,
        member: member,
        policy: policy,
      );

      switch (_selectedFilter) {
        case FeeLedgerFilter.all:
          return true;
        case FeeLedgerFilter.currentMonthUnpaid:
          return currentMonthRec.status == FeeStatus.unpaid;
        case FeeLedgerFilter.exemptOrResting:
          return currentMonthRec.status == FeeStatus.exempt ||
              member.status == MemberStatus.resting ||
              member.feePolicy == FeePolicyType.exempt;
        case FeeLedgerFilter.familyDiscount:
          return FeeLedgerCalculator.isFamilyDiscountMember(member, policy);
      }
    }).toList();

    if (_sortByNameAsc) {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final currentClub = ref.watch(currentClubProvider);
    final clubMembers = ref.watch(currentClubMembersProvider);
    final policy = ref.watch(currentClubFeePolicyProvider);
    final ledgerMap = ref.watch(feeLedgerProvider);

    if (!_isEditingRules && _rulesController.text != policy.rulesAndMemo) {
      _rulesController.text = policy.rulesAndMemo;
    }

    final monthlySummary = FeeLedgerCalculator.calculateMonthlySummary(
      ledgerMap: ledgerMap,
      clubId: currentClub.id,
      year: _selectedYear,
      month: _selectedMonth,
      members: clubMembers,
      policy: policy,
    );

    final familyDiscountCount = clubMembers
        .where(
          (m) =>
              !m.isGuest &&
              FeeLedgerCalculator.isFamilyDiscountMember(m, policy),
        )
        .length;

    final filteredMembers = _filterMembers(
      clubMembers: clubMembers,
      ledgerMap: ledgerMap,
      clubId: currentClub.id,
      policy: policy,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // 0. 상단 슬림 앱바 영역 ([내보내기 📤] & [실시간 웹뷰어] 포함)
            _buildTopHeaderBar(
              context: context,
              currentClub: currentClub,
              members: clubMembers,
              ledgerMap: ledgerMap,
              policy: policy,
              summary: monthlySummary,
            ),

            // 서브 탭 선택 바 ([📊 연간 월회비 장부] vs [🧾 행사비/모임비 출납부])
            _buildSubTabSelector(),

            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (_activeSubTab == 0) ...[
                    // 1 & 2. 슬림 아코디언 바: [⚙️ 정책 및 계좌 설정 열기 ⌵] + [📜 클럽 회비 회칙 & 메모란 ⌵]
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                        child: _buildCompactPolicyAndRulesSection(
                          context,
                          currentClub,
                          policy,
                        ),
                      ),
                    ),

                    // 3 & 4. 통합 슬림 대시보드 ([통계 요약 칩] + 조회 필터 칩 + 검색창)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: _buildDashboardAndToolbarCard(
                          context: context,
                          club: currentClub,
                          members: clubMembers,
                          ledgerMap: ledgerMap,
                          policy: policy,
                          summary: monthlySummary,
                          familyDiscountCount: familyDiscountCount,
                        ),
                      ),
                    ),

                    // 5. 연간 월별 회비 매트릭스 테이블 (페이지 진입 시 통계 요약 칩 바로 아래에 즉시 노출)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: _buildAnnualMatrixTableCard(
                          context: context,
                          club: currentClub,
                          members: filteredMembers,
                          allClubMembers: clubMembers,
                          ledgerMap: ledgerMap,
                          policy: policy,
                          isReadOnly: false,
                        ),
                      ),
                    ),
                  ] else ...[
                    // [PRO 장부] 행사비/모임비 금전출납부 탭
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        child: _buildEventExpenseLedgerView(
                          context: context,
                          club: currentClub,
                          members: clubMembers,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 0. 상단 타이틀 및 [내보내기 📤] / [실시간 웹뷰어] 헤더
  Widget _buildTopHeaderBar({
    required BuildContext context,
    required Club currentClub,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required MonthlyFeeSummary summary,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => AppTheme.openDrawer(context),
            tooltip: '메뉴 열기',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: pagePalette.borderTint),
              ),
            ),
            icon: Icon(
              Icons.menu_rounded,
              color: pagePalette.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '연간/월별 회비 납부 현황표',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [pagePalette.primary, pagePalette.secondary],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'PRO 장부',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 상단 우측 [내보내기 📤] 액션 메뉴 버튼 (바텀시트 오픈)
          OutlinedButton(
            key: const Key('fee_export_menu_button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: pagePalette.primary,
              backgroundColor: pagePalette.softTint,
              side: BorderSide(
                color: pagePalette.borderTint,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            onPressed: () => _showExportActionsBottomSheet(
              context: context,
              club: currentClub,
              members: members,
              ledgerMap: ledgerMap,
              policy: policy,
              summary: summary,
            ),
            child: const Text(
              '내보내기 📤',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 5),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: pagePalette.primary,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: pagePalette.borderTint,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 13.5),
            label: const Text(
              '실시간 웹뷰어',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FeeStatusWebViewerScreen(
                    clubId: currentClub.id,
                    initialYear: _selectedYear,
                    initialMonth: _selectedMonth,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 상단 우측 [내보내기 📤] 클릭 시 열리는 공유 & 내보내기 바텀시트 메뉴
  void _showExportActionsBottomSheet({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required MonthlyFeeSummary summary,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9DDF0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('📤', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '공유 & 내보내기 툴바',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActionToolbarButton(
                      label: '📢 당월 미납자 알림 문구 복사',
                      bgColor: AppTheme.pastelCoral,
                      fgColor: AppTheme.pastelCoralDark,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showKakaoUnpaidMessageDialog(
                          context: context,
                          club: club,
                          summary: summary,
                          policy: policy,
                        );
                      },
                    ),
                    _buildActionToolbarButton(
                      label: '📸 장부 이미지 내보내기',
                      bgColor: pagePalette.primary,
                      fgColor: Colors.white,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showBandImageExportModal(
                          context: context,
                          club: club,
                          members: members,
                          ledgerMap: ledgerMap,
                          policy: policy,
                          summary: summary,
                        );
                      },
                    ),
                    _buildActionToolbarButton(
                      label: '🔗 실시간 회비 웹뷰어 링크 복사',
                      bgColor: AppTheme.pastelBlue,
                      fgColor: AppTheme.pastelBlueDark,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _copyWebViewerLinkAndShowPreview(
                          context: context,
                          club: club,
                        );
                      },
                    ),
                    _buildActionToolbarButton(
                      label: '📊 엑셀 다운로드',
                      bgColor: AppTheme.pastelMint,
                      fgColor: AppTheme.pastelMintDark,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showExcelExportDialog(
                          context: context,
                          club: club,
                          members: members,
                          ledgerMap: ledgerMap,
                          policy: policy,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 1 & 2. 슬림 아코디언 바: [⚙️ 정책 및 계좌 설정 열기 ⌵] + [📜 클럽 회비 회칙 & 메모란]
  Widget _buildCompactPolicyAndRulesSection(
    BuildContext context,
    Club currentClub,
    ClubFeePolicy policy,
  ) {
    final pagePalette = AppTheme.getPagePalette(4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // [⚙️ 정책 및 계좌 설정 열기 ⌵] 토글 버튼 (기본 Collapsed)
            Expanded(
              flex: 6,
              child: InkWell(
                key: const Key('toggle_fee_policy_button'),
                onTap: () {
                  setState(() => _isPolicyExpanded = !_isPolicyExpanded);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _isPolicyExpanded
                        ? pagePalette.softTint
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isPolicyExpanded
                          ? pagePalette.borderTint
                          : const Color(0xFFE4E7F4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isPolicyExpanded
                              ? '⚙️ 정책 및 계좌 설정 접기 ⌃'
                              : '⚙️ 정책 및 계좌 설정 열기 ⌵',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: pagePalette.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${policy.formattedDefaultFee}·${policy.formattedDueDay}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // [📜 클럽 회비 회칙 & 메모란] 토글 버튼 (기본 Collapsed)
            Expanded(
              flex: 5,
              child: InkWell(
                key: const Key('toggle_fee_rules_button'),
                onTap: () {
                  setState(
                    () =>
                        _isRulesAccordionExpanded = !_isRulesAccordionExpanded,
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _isRulesAccordionExpanded
                        ? AppTheme.pastelPeriwinkle
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isRulesAccordionExpanded
                          ? AppTheme.primaryDark.withValues(alpha: 0.4)
                          : const Color(0xFFE4E7F4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('📜', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          '클럽 회비 회칙 & 메모란',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _isRulesAccordionExpanded ? '접기 ⌃' : '⌵',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_isPolicyExpanded) ...[
          const SizedBox(height: 4),
          _buildFeePolicyHeaderCard(context, currentClub, policy),
        ],
        if (_isRulesAccordionExpanded) ...[
          const SizedBox(height: 4),
          _buildRulesAccordionCard(context, currentClub, policy),
        ],
      ],
    );
  }

  /// 1. 클럽 기본 회비 정책 및 계좌 정보 상세 패널 (펼쳤을 때 노출)
  Widget _buildFeePolicyHeaderCard(
    BuildContext context,
    Club currentClub,
    ClubFeePolicy policy,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryDark.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 15,
                color: AppTheme.primaryDark,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '클럽 기본 회비 정책 & 입금 계좌 설정',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryDark,
                  backgroundColor:
                      AppTheme.pastelPeriwinkle.withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded, size: 13),
                label: const Text(
                  '정책/계좌 수정',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                onPressed: () =>
                    _showEditFeePolicyDialog(context, currentClub, policy),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildPolicyMetricChip(
                icon: Icons.payments_outlined,
                label: '기본 월 회비',
                value: policy.formattedDefaultFee,
                subNote: '신규 회원 기본 연동',
                bgColor: AppTheme.pastelPeriwinkle.withValues(alpha: 0.45),
                accentColor: AppTheme.primaryDark,
              ),
              _buildPolicyMetricChip(
                icon: Icons.event_repeat_rounded,
                label: '정기 납부 마감일',
                value: policy.formattedDueDay,
                subNote: '월별 정기 수납 기준',
                bgColor: AppTheme.pastelBlue.withValues(alpha: 0.55),
                accentColor: AppTheme.pastelBlueDark,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E7F4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_rounded,
                  size: 14,
                  color: AppTheme.pastelBlueDark,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${policy.bankName} ${policy.accountNumber} · 예금주: ${policy.accountHolder}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final accountText =
                        '${policy.bankName} ${policy.accountNumber} (예금주: ${policy.accountHolder})';
                    await Clipboard.setData(ClipboardData(text: accountText));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.primaryDark,
                          content: Text('입금 계좌 정보가 복사되었습니다: $accountText'),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD9DDF0)),
                    ),
                    child: const Text(
                      '계좌 복사',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required String subNote,
    required Color bgColor,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 2. [📜 클럽 회비 회칙 & 메모란] 상세 패널 (펼쳤을 때 노출)
  Widget _buildRulesAccordionCard(
    BuildContext context,
    Club currentClub,
    ClubFeePolicy policy,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryDark.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _rulesController,
            maxLines: 4,
            onChanged: (_) {
              if (!_isEditingRules) {
                setState(() => _isEditingRules = true);
              }
            },
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.textDark,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText:
                  '가족 할인 기준, 휴면(휴회) 규정, 임원 면제 기준, 미납 제재 등 클럽 회칙과 총무 메모를 입력하세요.',
              filled: true,
              fillColor: AppTheme.background,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFDCE0F0)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _rulesController.text = ClubFeePolicy.defaultRulesText;
                    _isEditingRules = true;
                  });
                },
                child: const Text(
                  '표준 회칙 예시 불러오기',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.save_rounded, size: 14),
                label: const Text(
                  '회칙/메모 영구 저장',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () async {
                  final text = _rulesController.text.trim();
                  await ref
                      .read(clubFeePoliciesProvider.notifier)
                      .updateRulesAndMemo(currentClub.id, text);
                  setState(() => _isEditingRules = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppTheme.primaryDark,
                        content: Text(
                          '클럽 회비 회칙 및 메모가 영구 저장되었습니다.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 3 & 4. 통합 슬림 대시보드 ([통계 요약 칩] + 회원 상태 필터 칩 + 검색창)
  Widget _buildDashboardAndToolbarCard({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required MonthlyFeeSummary summary,
    required int familyDiscountCount,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    final ratePercent = summary.collectionRate.toStringAsFixed(1);
    final totalRegularCount = members.where((m) => !m.isGuest).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1행: [연도 선택] + [기준 월 선택] + [당월 수납률 및 수납액/미납액 요약] + [일괄 완납]
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: pagePalette.softTint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: pagePalette.borderTint),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedYear,
                        isDense: true,
                        icon: Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 16,
                          color: pagePalette.primary,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: pagePalette.primary,
                        ),
                        items: [2024, 2025, 2026, 2027].map((yr) {
                          return DropdownMenuItem<int>(
                            value: yr,
                            child: Text('$yr년 기준'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedYear = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedMonth,
                        isDense: true,
                        icon: const Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 16,
                          color: AppTheme.pastelBlueDark,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.pastelBlueDark,
                        ),
                        items: List.generate(12, (idx) => idx + 1).map((m) {
                          return DropdownMenuItem<int>(
                            value: m,
                            child: Text('$m월 요약'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedMonth = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '총 납부율 $ratePercent%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: pagePalette.primary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '당월 수납액 ${summary.formattedCollectedAmount} · 당월 미납액 ${summary.formattedUnpaidAmount}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (summary.unpaidCount > 0) ...[
                    const SizedBox(width: 6),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.pastelMintDark,
                        backgroundColor: AppTheme.pastelMint,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      icon: const Icon(Icons.done_all_rounded, size: 12),
                      label: Text(
                        '$_selectedMonth월 미납 ${summary.unpaidCount}명 일괄 완납',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: () async {
                        final todayStr = DateFormat('yyyy.MM.dd').format(
                          DateTime.now(),
                        );
                        final count = await ref
                            .read(feeLedgerProvider.notifier)
                            .markMonthAllPaid(
                              clubId: club.id,
                              year: _selectedYear,
                              month: _selectedMonth,
                              members: members,
                              policy: policy,
                              paidDate: todayStr,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.pastelMintDark,
                              content: Text(
                                '$_selectedYear년 $_selectedMonth월 미납 회원 $count명이 일괄 완납 처리되었습니다.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 2행: [통계 요약 칩] (1줄 슬림 배치)
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatBox(
                  title: '완납',
                  countText: '완납 ${summary.paidCount}명',
                  emoji: '🟢',
                  bgColor: AppTheme.pastelMint,
                  textColor: AppTheme.pastelMintDark,
                  onTap: () => setState(
                    () => _selectedFilter = FeeLedgerFilter.all,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _buildSummaryStatBox(
                  title: '미납',
                  countText: '미납 ${summary.unpaidCount}명',
                  emoji: '🔴',
                  bgColor: AppTheme.pastelCoral,
                  textColor: AppTheme.pastelCoralDark,
                  onTap: () => setState(
                    () => _selectedFilter = FeeLedgerFilter.currentMonthUnpaid,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _buildSummaryStatBox(
                  title: '면제/휴면',
                  countText: '면제/휴면 ${summary.exemptCount}명',
                  emoji: '⚪',
                  bgColor: AppTheme.pastelPeriwinkle,
                  textColor: AppTheme.pastelPeriwinkleDark,
                  onTap: () => setState(
                    () => _selectedFilter = FeeLedgerFilter.exemptOrResting,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 3행: 회원 상태 필터 탭 ([전체], [당월 미납자], [휴면·면제], [👨‍👩‍👧 가족할인 회원]) & 초성 검색
          _buildFilterAndSearchBar(
            totalCount: totalRegularCount,
            unpaidCount: summary.unpaidCount,
            exemptCount: summary.exemptCount,
            familyDiscountCount: familyDiscountCount,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatBox({
    required String title,
    required String countText,
    required String emoji,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$emoji $countText',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionToolbarButton({
    required String label,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            color: fgColor,
          ),
        ),
      ),
    );
  }

  /// 4. 조회 필터 칩 ([전체], [당월 미납자], [휴면·면제], [👨‍👩‍👧 가족할인 회원]) & 검색창
  Widget _buildFilterAndSearchBar({
    required int totalCount,
    required int unpaidCount,
    required int exemptCount,
    required int familyDiscountCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChipItem(
                filter: FeeLedgerFilter.all,
                label: '전체 ($totalCount명)',
              ),
              const SizedBox(width: 5),
              _buildFilterChipItem(
                filter: FeeLedgerFilter.currentMonthUnpaid,
                label: '당월 미납자 ($unpaidCount명)',
              ),
              const SizedBox(width: 5),
              _buildFilterChipItem(
                filter: FeeLedgerFilter.exemptOrResting,
                label: '휴면·면제 ($exemptCount명)',
              ),
              const SizedBox(width: 5),
              _buildFilterChipItem(
                filter: FeeLedgerFilter.familyDiscount,
                label: '👨‍👩‍👧 가족할인 회원 ($familyDiscountCount명)',
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 34,
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '회원 이름 또는 직책(회장/총무 등) 초성 검색...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 16,
                color: AppTheme.textMuted,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.clear_rounded, size: 15),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChipItem({
    required FeeLedgerFilter filter,
    required String label,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    final isSelected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: pagePalette.primary,
      backgroundColor: AppTheme.background,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: isSelected ? Colors.white : AppTheme.textDark,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? pagePalette.primary : const Color(0xFFDCE0F0),
        ),
      ),
      onSelected: (_) {
        setState(() => _selectedFilter = filter);
      },
    );
  }

  /// 5. 연간 월별 회비 매트릭스 테이블 (Table View)
  Widget _buildAnnualMatrixTableCard({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required List<Member> allClubMembers,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required bool isReadOnly,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 테이블 안내 헤더 + [가나다순 / 등록순 정렬] 토글 옵션
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_rounded,
                  size: 16,
                  color: pagePalette.primary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '$_selectedYear년 월별 회비 매트릭스 (${members.length}명)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // [가나다순 / 등록순 정렬] 토글 버튼 (기본: 이름 가나다순 오름차순)
                InkWell(
                  key: const Key('toggle_fee_matrix_sort_button'),
                  onTap: () {
                    setState(() => _sortByNameAsc = !_sortByNameAsc);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pagePalette.softTint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: pagePalette.borderTint,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.swap_vert_rounded,
                          size: 13,
                          color: pagePalette.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _sortByNameAsc ? '가나다순 정렬' : '등록순 정렬',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: pagePalette.primary,
                          ),
                        ),
                        Text(
                          _sortByNameAsc ? ' (등록순)' : ' (가나다순)',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                // [그룹화 보기 ⌵] 토글 버튼
                InkWell(
                  key: const Key('toggle_fee_matrix_grouping_button'),
                  onTap: () {
                    setState(() => _isGroupingEnabled = !_isGroupingEnabled);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _isGroupingEnabled
                          ? pagePalette.primary
                          : pagePalette.softTint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: pagePalette.borderTint,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_shared_outlined,
                          size: 13,
                          color: _isGroupingEnabled
                              ? Colors.white
                              : pagePalette.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _isGroupingEnabled ? '그룹화 켜짐' : '그룹화 보기 ⌵',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: _isGroupingEnabled
                                ? Colors.white
                                : pagePalette.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFECEFF8)),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Center(
                child: Text(
                  '조건에 해당하는 회원이 없습니다.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildMatrixTableContent(
                context: context,
                club: club,
                members: members,
                allClubMembers: allClubMembers,
                ledgerMap: ledgerMap,
                policy: policy,
                isReadOnly: isReadOnly,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMatrixTableContent({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required List<Member> allClubMembers,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required bool isReadOnly,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    const double memberColWidth = 145;
    const double baseFeeColWidth = 98;
    const double monthColWidth = 68;
    const double totalColWidth = 106;

    final grandTotalAnnual = members.fold<int>(
      0,
      (sum, m) =>
          sum +
          FeeLedgerCalculator.calculateMemberAnnualTotal(
            ledgerMap: ledgerMap,
            clubId: club.id,
            year: _selectedYear,
            member: m,
            policy: policy,
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) 테이블 컬럼 헤더
        Container(
          color: const Color(0xFFF3F4FB),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              _buildHeaderCell('회원명 (직책/상태)', memberColWidth, alignLeft: true),
              _buildHeaderCell('월 회비 기준액', baseFeeColWidth),
              for (int m = 1; m <= 12; m++)
                _buildHeaderCell(
                  '$m월',
                  monthColWidth,
                  isHighlighted: m == _selectedMonth,
                ),
              _buildHeaderCell('연간 납부 합계', totalColWidth),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E6F3)),

        // 2) [상단 고정 Pinning] 월별 수납 요약 행 (헤더 바로 아래에 배치되어 스크롤 없이 즉시 확인 가능)
        Container(
          key: const Key('pinned_monthly_summary_row'),
          color: const Color(0xFFEDF2FB),
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: memberColWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: pagePalette.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '고정',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          '월별 수납 요약',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: baseFeeColWidth,
                child: Center(
                  child: Text(
                    '기본 ${policy.formattedDefaultFee}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
              for (int m = 1; m <= 12; m++)
                Builder(
                  builder: (_) {
                    final mSum = FeeLedgerCalculator.calculateMonthlySummary(
                      ledgerMap: ledgerMap,
                      clubId: club.id,
                      year: _selectedYear,
                      month: m,
                      members: allClubMembers,
                      policy: policy,
                    );
                    return SizedBox(
                      width: monthColWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${mSum.paidCount}명 완납',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.pastelMintDark,
                            ),
                          ),
                          Text(
                            '${(mSum.totalCollectedAmount / 10000).toStringAsFixed(0)}만원',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              SizedBox(
                width: totalColWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      FeeLedgerCalculator.formatWon(grandTotalAnnual),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    const Text(
                      '조회 회원 총계',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFD6DBED)),

        // 3) 회원별 행 (일반 평면 목록 또는 그룹별 아코디언)
        if (!_isGroupingEnabled)
          ...members.asMap().entries.map((entry) {
            return _buildMemberRow(
              context: context,
              club: club,
              member: entry.value,
              index: entry.key,
              policy: policy,
              ledgerMap: ledgerMap,
              isReadOnly: isReadOnly,
              memberColWidth: memberColWidth,
              baseFeeColWidth: baseFeeColWidth,
              monthColWidth: monthColWidth,
              totalColWidth: totalColWidth,
            );
          })
        else
          ..._buildGroupedMatrixRows(
            context: context,
            club: club,
            members: members,
            policy: policy,
            ledgerMap: ledgerMap,
            isReadOnly: isReadOnly,
            memberColWidth: memberColWidth,
            baseFeeColWidth: baseFeeColWidth,
            monthColWidth: monthColWidth,
            totalColWidth: totalColWidth,
            totalTableWidth:
                memberColWidth + baseFeeColWidth + monthColWidth * 12 + totalColWidth,
          ),
      ],
    );
  }

  /// 개별 회원 행 렌더링 (회원명 탭 시 상세 팝업 호출 포함)
  Widget _buildMemberRow({
    required BuildContext context,
    required Club club,
    required Member member,
    required int index,
    required ClubFeePolicy policy,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required bool isReadOnly,
    required double memberColWidth,
    required double baseFeeColWidth,
    required double monthColWidth,
    required double totalColWidth,
  }) {
    final standardFee =
        FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);
    final policySubLabel =
        FeeLedgerCalculator.getMemberFeePolicySubLabel(member, policy);
    final annualTotal = FeeLedgerCalculator.calculateMemberAnnualTotal(
      ledgerMap: ledgerMap,
      clubId: club.id,
      year: _selectedYear,
      member: member,
      policy: policy,
    );
    final paidMonths = FeeLedgerCalculator.calculateMemberPaidMonthsCount(
      ledgerMap: ledgerMap,
      clubId: club.id,
      year: _selectedYear,
      member: member,
      policy: policy,
    );

    return Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFFAFBFD),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFECEFF8), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // [회원명 (직책/상태 뱃지)] - 탭 시 회원 상세 팝업 호출 (전화 걸기/문자 발송)
          SizedBox(
            width: memberColWidth,
            child: InkWell(
              key: Key('member_detail_trigger_${member.id}'),
              onTap: () => _showMemberDetailPopup(context, ref, member),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: member.isExecutive
                                ? AppTheme.pastelPeriwinkle
                                : const Color(0xFFEEF1F8),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            member.displayRoleLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: member.isExecutive
                                  ? AppTheme.primaryDark
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: member.status == MemberStatus.resting
                                ? AppTheme.pastelYellow
                                : AppTheme.pastelMint.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            member.status == MemberStatus.resting
                                ? '휴면(${member.restingReason ?? "휴회"})'
                                : '${member.tier.label} · 활동',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: member.status == MemberStatus.resting
                                  ? AppTheme.pastelYellowDark
                                  : AppTheme.pastelMintDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // [월 회비 기준액]
          SizedBox(
            width: baseFeeColWidth,
            child: Column(
              children: [
                Text(
                  FeeLedgerCalculator.formatWon(standardFee),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: member.feePolicy == FeePolicyType.discounted
                        ? AppTheme.pastelBlueDark
                        : (standardFee == 0
                              ? AppTheme.textMuted
                              : AppTheme.textDark),
                  ),
                ),
                const SizedBox(height: 1),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: member.feePolicy == FeePolicyType.discounted
                        ? AppTheme.pastelBlue
                        : (member.feePolicy == FeePolicyType.exempt ||
                                  member.status == MemberStatus.resting
                              ? AppTheme.pastelPeriwinkle
                              : const Color(0xFFF2F4FA)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    policySubLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: member.feePolicy == FeePolicyType.discounted
                          ? AppTheme.pastelBlueDark
                          : (member.feePolicy == FeePolicyType.exempt ||
                                    member.status == MemberStatus.resting
                                ? AppTheme.primaryDark
                                : AppTheme.textMuted),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // [1월] ~ [12월] 납부 상태 셀
          for (int m = 1; m <= 12; m++)
            _buildMonthStatusCell(
              context: context,
              club: club,
              member: member,
              month: m,
              width: monthColWidth,
              ledgerMap: ledgerMap,
              policy: policy,
              isReadOnly: isReadOnly,
            ),

          // [연간 납부 합계 & 1년 일괄 완납 간편 액션]
          SizedBox(
            width: totalColWidth,
            child: Column(
              children: [
                Text(
                  FeeLedgerCalculator.formatWon(annualTotal),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryDark,
                  ),
                ),
                Text(
                  '$paidMonths개월 완납',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
                if (!isReadOnly && paidMonths < 12) ...[
                  const SizedBox(height: 3),
                  InkWell(
                    key: Key('annual_all_paid_btn_${member.id}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () async {
                      await ref
                          .read(feeLedgerProvider.notifier)
                          .markMemberPeriodAllPaid(
                            clubId: club.id,
                            year: _selectedYear,
                            member: member,
                            policy: policy,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.primaryDark,
                            content: Text(
                              '✅ ${member.name} 회원의 $_selectedYear년 1~12월 회비가 [1년 일괄 완납] 처리되었습니다.',
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelMint,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.pastelMintDark.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        '1년 일괄 완납',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.pastelMintDark,
                        ),
                      ),
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

  /// 회원 그룹화(Grouping) 아코디언 행 목록 빌더
  List<Widget> _buildGroupedMatrixRows({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required ClubFeePolicy policy,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required bool isReadOnly,
    required double memberColWidth,
    required double baseFeeColWidth,
    required double monthColWidth,
    required double totalColWidth,
    required double totalTableWidth,
  }) {
    // 5개 그룹 분리: '운영진 그룹', '가족회원 그룹', '일반 정회원', '준회원', '휴면·면제'
    final execMembers = <Member>[];
    final familyMembers = <Member>[];
    final regularMembers = <Member>[];
    final associateMembers = <Member>[];
    final restingExemptMembers = <Member>[];

    for (final m in members) {
      if (m.isExecutive || m.role.isExecutive) {
        execMembers.add(m);
      } else if (m.status == MemberStatus.resting ||
          m.feePolicy == FeePolicyType.exempt) {
        restingExemptMembers.add(m);
      } else if (FeeLedgerCalculator.isFamilyDiscountMember(m, policy)) {
        familyMembers.add(m);
      } else if (m.role == MemberRole.associate) {
        associateMembers.add(m);
      } else {
        regularMembers.add(m);
      }
    }

    final groups = [
      (
        key: 'exec',
        title: '운영진 그룹',
        icon: Icons.military_tech_rounded,
        color: AppTheme.pastelPeriwinkleDark,
        list: execMembers,
      ),
      (
        key: 'family',
        title: '가족회원 그룹',
        icon: Icons.diversity_3_rounded,
        color: AppTheme.pastelCoralDark,
        list: familyMembers,
      ),
      (
        key: 'regular',
        title: '일반 정회원',
        icon: Icons.person_rounded,
        color: AppTheme.primaryDark,
        list: regularMembers,
      ),
      (
        key: 'associate',
        title: '준회원',
        icon: Icons.person_outline_rounded,
        color: const Color(0xFF5E657E),
        list: associateMembers,
      ),
      (
        key: 'resting_exempt',
        title: '휴면·면제',
        icon: Icons.pause_circle_filled_rounded,
        color: AppTheme.pastelYellowDark,
        list: restingExemptMembers,
      ),
    ];

    final widgets = <Widget>[];

    for (final g in groups) {
      if (g.list.isEmpty) continue;

      final isCollapsed = _collapsedGroups.contains(g.key);
      final groupPaidCount = g.list.where((m) {
        final rec = FeeLedgerCalculator.resolveCellRecord(
          ledgerMap: ledgerMap,
          clubId: club.id,
          year: _selectedYear,
          month: _selectedMonth,
          member: m,
          policy: policy,
        );
        return rec.status == FeeStatus.paid;
      }).length;

      final groupAnnualTotal = g.list.fold<int>(
        0,
        (sum, m) =>
            sum +
            FeeLedgerCalculator.calculateMemberAnnualTotal(
              ledgerMap: ledgerMap,
              clubId: club.id,
              year: _selectedYear,
              member: m,
              policy: policy,
            ),
      );

      // 그룹 아코디언 헤더 행
      widgets.add(
        InkWell(
          key: Key('group_header_${g.key}'),
          onTap: () {
            setState(() {
              if (isCollapsed) {
                _collapsedGroups.remove(g.key);
              } else {
                _collapsedGroups.add(g.key);
              }
            });
          },
          child: Container(
            width: totalTableWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F9),
              border: Border(
                top: const BorderSide(color: Color(0xFFD6DBED), width: 1),
                bottom: BorderSide(
                  color: isCollapsed
                      ? const Color(0xFFD6DBED)
                      : const Color(0xFFE2E6F2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(g.icon, size: 15, color: g.color),
                const SizedBox(width: 6),
                Text(
                  '${g.title} (${g.list.length}명)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: g.color,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFDCE0F0)),
                  ),
                  child: Text(
                    '$_selectedMonth월 완납 $groupPaidCount명 · 연간 합계 ${FeeLedgerCalculator.formatWon(groupAnnualTotal)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  isCollapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      );

      // 그룹 회원 목록 (접힌 상태가 아닐 때만 렌더링)
      if (!isCollapsed) {
        for (int i = 0; i < g.list.length; i++) {
          widgets.add(
            _buildMemberRow(
              context: context,
              club: club,
              member: g.list[i],
              index: i,
              policy: policy,
              ledgerMap: ledgerMap,
              isReadOnly: isReadOnly,
              memberColWidth: memberColWidth,
              baseFeeColWidth: baseFeeColWidth,
              monthColWidth: monthColWidth,
              totalColWidth: totalColWidth,
            ),
          );
        }
      }
    }

    return widgets;
  }

  /// 1. 회원 카드 상세 정보 팝업 (전화 걸기 / 문자 발송 액션 포함)
  void _showMemberDetailPopup(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) {
    final hasPhone =
        member.phoneNumber != null && member.phoneNumber!.trim().isNotEmpty;
    final restingBadge = member.restingBadgeText;
    final feePolicyBadge = member.feePolicyBadgeText;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        title: Row(
          children: [
            Container(
              width: 10,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.getGenderAccentColor(member.gender),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                member.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.getTierBgColor(member.tier),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                member.tier.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.getTierTextColor(member.tier),
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(dialogCtx),
              icon: const Icon(
                Icons.close_rounded,
                size: 20,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.getGenderCardBg(member.gender),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.getGenderCardBorder(member.gender),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '구분: ${member.gender.label} · ${member.displayRoleLabel}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '연락처: ${hasPhone ? member.phoneNumber! : "연락처 미등록"}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (restingBadge != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '활동 상태: $restingBadge${member.restingReason != null ? " (${member.restingReason})" : ""}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.pastelYellowDark,
                      ),
                    ),
                  ],
                  if (feePolicyBadge != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '회비 정책: $feePolicyBadge',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.pastelPeriwinkleDark,
                      ),
                    ),
                  ],
                  if (member.memo != null && member.memo!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '메모: ${member.memo!}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryMint,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.call_rounded, size: 17),
                    label: const Text(
                      '전화 걸기',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _callMember(context, member);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.sms_rounded, size: 17),
                    label: const Text(
                      '문자 보내기',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _sendMemberSms(context, member);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 개별 회원 전화 걸기 (tel:)
  Future<void> _callMember(BuildContext context, Member member) async {
    final rawPhone = (member.phoneNumber ?? '').trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.pastelRoseDark,
          content: Text('${member.name} 님의 등록된 전화번호가 없습니다.'),
        ),
      );
      return;
    }
    final cleanPhone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final telUri = Uri.parse('tel:$cleanPhone');
    try {
      final launched =
          await launchUrl(telUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: rawPhone));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member.name} 님 번호($rawPhone)로 전화 연결을 시도했습니다.'),
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: rawPhone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.name} 님의 번호($rawPhone)를 복사했습니다.'),
          ),
        );
      }
    }
  }

  /// 개별 회원 문자 보내기 (sms:)
  Future<void> _sendMemberSms(BuildContext context, Member member) async {
    final rawPhone = (member.phoneNumber ?? '').trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.pastelRoseDark,
          content: Text('${member.name} 님의 등록된 전화번호가 없습니다.'),
        ),
      );
      return;
    }
    final cleanPhone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final smsUri = Uri.parse('sms:$cleanPhone');
    try {
      final launched =
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: rawPhone));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member.name} 님 번호($rawPhone)로 문자 앱 연결을 요청했습니다.'),
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: rawPhone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.name} 님의 번호($rawPhone)를 복사했습니다.'),
          ),
        );
      }
    }
  }

  /// 상단 서브 탭 선택 바 ([📊 연간 월회비 장부] vs [🧾 행사비/모임비 출납부])
  Widget _buildSubTabSelector() {
    final palette = AppTheme.getPagePalette(4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2FA),
          borderRadius: BorderRadius.circular(11),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: const Key('subtab_annual_fee_ledger'),
                onTap: () => setState(() => _activeSubTab = 0),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  decoration: BoxDecoration(
                    color: _activeSubTab == 0 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: _activeSubTab == 0
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.table_chart_rounded,
                        size: 14,
                        color: _activeSubTab == 0
                            ? palette.primary
                            : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '연간 월회비 장부',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _activeSubTab == 0
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: _activeSubTab == 0
                              ? palette.primary
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                key: const Key('subtab_event_expense_ledger'),
                onTap: () => setState(() => _activeSubTab = 1),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  decoration: BoxDecoration(
                    color: _activeSubTab == 1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: _activeSubTab == 1
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 14,
                        color: _activeSubTab == 1
                            ? palette.primary
                            : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '행사비/모임비 출납부',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _activeSubTab == 1
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: _activeSubTab == 1
                              ? palette.primary
                              : AppTheme.textMuted,
                        ),
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

  /// 2. [PRO 장부] 행사비/모임비 금전출납부 탭 뷰
  Widget _buildEventExpenseLedgerView({
    required BuildContext context,
    required Club club,
    required List<Member> members,
  }) {
    final pagePalette = AppTheme.getPagePalette(4);
    final events = ref.watch(currentClubEventsProvider);

    if (_selectedEventId == null ||
        !events.any((e) => e.id == _selectedEventId)) {
      _selectedEventId = events.isNotEmpty ? events.first.id : null;
    }
    final currentEvent =
        events.where((e) => e.id == _selectedEventId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) 행사 선택 및 상단 등록/연동 바
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E7F4)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_note_rounded,
                    size: 17,
                    color: pagePalette.primary,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '행사비 / 모임비 정산 선택',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  // [+ 새 행사 등록] 버튼
                  InkWell(
                    key: const Key('create_club_event_button'),
                    onTap: () => _showCreateEventDialog(context, club),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 13, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            '새 행사 등록',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // [📥 출석부 모임 불러오기] 버튼
                  InkWell(
                    key: const Key('import_session_event_button'),
                    onTap: () =>
                        _showImportFromSessionDialog(context, club, members),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: pagePalette.softTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: pagePalette.borderTint),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.download_rounded,
                            size: 13,
                            color: pagePalette.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '출석부 불러오기',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: pagePalette.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (events.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: events.map((ev) {
                      final isSel = ev.id == _selectedEventId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key('event_chip_${ev.id}'),
                          selected: isSel,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (ev.linkedSessionId != null) ...[
                                const Icon(Icons.link_rounded, size: 12),
                                const SizedBox(width: 3),
                              ],
                              Text(ev.title),
                              const SizedBox(width: 4),
                              Text(
                                ev.eventDate,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isSel
                                      ? Colors.white70
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          selectedColor: pagePalette.primary,
                          backgroundColor: const Color(0xFFF0F2FA),
                          labelStyle: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                isSel ? FontWeight.w900 : FontWeight.w700,
                            color: isSel ? Colors.white : AppTheme.textDark,
                          ),
                          side: BorderSide(
                            color: isSel
                                ? pagePalette.primary
                                : const Color(0xFFE2E6F2),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedEventId = ev.id);
                            }
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
        const SizedBox(height: 10),

        if (currentEvent == null)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4E7F4)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            child: Column(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 40,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(height: 10),
                const Text(
                  '등록된 행사비/모임비 출납부가 없습니다.',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '새 행사를 직접 등록하거나, 일반 모드 [출석부]에서 진행한 모임 데이터를\n원클릭으로 불러와 수입/지출 및 영수증을 스마트하게 정산해 보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text(
                        '새 행사 직접 등록',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () => _showCreateEventDialog(context, club),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pagePalette.primary,
                        side: BorderSide(color: pagePalette.borderTint),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        '출석부 모임 불러오기',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: () =>
                          _showImportFromSessionDialog(context, club, members),
                    ),
                  ],
                ),
              ],
            ),
          )
        else ...[
          // 2) 행사 정산 요약 카드 (총 수입, 총 지출, 최종 잔액)
          _buildEventSummaryCard(context, club, currentEvent),
          const SizedBox(height: 10),

          // 3) 수입/지출 상세 명세 목록 카드
          _buildEventTransactionListCard(context, club, currentEvent),
        ],
      ],
    );
  }

  /// 행사 정산 재정 요약 카드
  Widget _buildEventSummaryCard(
    BuildContext context,
    Club club,
    ClubEvent event,
  ) {
    final pagePalette = AppTheme.getPagePalette(4);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7F4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (event.linkedSessionId != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelMint,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.pastelMintDark
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 10,
                                  color: AppTheme.pastelMintDark,
                                ),
                                SizedBox(width: 2),
                                Text(
                                  '출석부 연동',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.pastelMintDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '일자: ${event.eventDate}${event.memo != null && event.memo!.isNotEmpty ? " · ${event.memo}" : ""}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Colors.red,
                ),
                tooltip: '행사 삭제',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDeleteEvent(context, event),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 3-Metric Boxes
          Row(
            children: [
              // 총 수입
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelMint.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          AppTheme.pastelMintDark.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '총 수입',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.pastelMintDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '+${FeeLedgerCalculator.formatWon(event.totalIncome)}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.pastelMintDark,
                          ),
                        ),
                      ),
                      Text(
                        '${event.incomeCount}건',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 총 지출
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelRose.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          AppTheme.pastelRoseDark.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '총 지출',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.pastelRoseDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '-${FeeLedgerCalculator.formatWon(event.totalExpense)}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.pastelRoseDark,
                          ),
                        ),
                      ),
                      Text(
                        '${event.expenseCount}건',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 최종 잔액
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  decoration: BoxDecoration(
                    color: event.balance >= 0
                        ? AppTheme.pastelPeriwinkle.withValues(alpha: 0.5)
                        : AppTheme.pastelCoral.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: event.balance >= 0
                          ? AppTheme.primaryDark.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '최종 잔액',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: event.balance >= 0
                              ? AppTheme.primaryDark
                              : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${event.balance >= 0 ? "+" : ""}${FeeLedgerCalculator.formatWon(event.balance)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: event.balance >= 0
                                ? AppTheme.primaryDark
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                      Text(
                        event.balance >= 0 ? '정산 흑자' : '정산 적자',
                        style: TextStyle(
                          fontSize: 9,
                          color: event.balance >= 0
                              ? AppTheme.primaryDark
                              : Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Action Buttons: [+ 내역 추가] and [📊 엑셀 다운로드 (CSV)]
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('add_event_expense_item_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                  label: const Text(
                    '수입/지출 내역 추가',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                  onPressed: () =>
                      _showAddEditExpenseItemDialog(context, event),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('export_event_expense_csv_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: pagePalette.primary,
                  side: BorderSide(color: pagePalette.borderTint),
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 15),
                label: const Text(
                  '엑셀 다운로드 (CSV)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
                onPressed: () => _exportEventCsv(context, club, event),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 행사 수입/지출 내역 목록 카드
  Widget _buildEventTransactionListCard(
    BuildContext context,
    Club club,
    ClubEvent event,
  ) {
    final filteredItems = event.items.where((i) {
      if (_eventFilterType == 'income') return i.isIncome;
      if (_eventFilterType == 'expense') return !i.isIncome;
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7F4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter bar
          Row(
            children: [
              const Text(
                '입출금 상세 내역',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const Spacer(),
              // Filter chips: 전체, 수입, 지출
              Wrap(
                spacing: 4,
                children: [
                  _buildSmallFilterChip('전체', 'all', event.items.length),
                  _buildSmallFilterChip('수입', 'income', event.incomeCount),
                  _buildSmallFilterChip('지출', 'expense', event.expenseCount),
                ],
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFECEFF8)),
          if (filteredItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '기록된 수입/지출 내역이 없습니다.\n[+ 수입/지출 내역 추가]를 눌러 첫 내역을 기록해 보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredItems.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFF1F3F8)),
              itemBuilder: (ctx, idx) {
                final item = filteredItems[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: item.isIncome
                              ? AppTheme.pastelMint
                              : AppTheme.pastelRose,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.isIncome ? '수입' : '지출',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: item.isIncome
                                ? AppTheme.pastelMintDark
                                : AppTheme.pastelRoseDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Title, Date, Memo
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  item.date,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                if (item.memo != null &&
                                    item.memo!.isNotEmpty) ...[
                                  const Text(
                                    ' · ',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      item.memo!,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppTheme.textMuted,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Amount
                      Text(
                        '${item.isIncome ? "+" : "-"}${FeeLedgerCalculator.formatWon(item.amount)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: item.isIncome
                              ? AppTheme.pastelMintDark
                              : AppTheme.pastelRoseDark,
                        ),
                      ),
                      // Receipt icon button (if has receipt)
                      if (item.hasReceipt) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          key: Key('receipt_btn_${item.id}'),
                          tooltip: '영수증 증빙 보기',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.receipt_long_rounded,
                            size: 18,
                            color: AppTheme.pastelPeriwinkleDark,
                          ),
                          onPressed: () =>
                              _showReceiptPreviewDialog(context, item),
                        ),
                      ],
                      // Edit / Delete popup
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                        padding: EdgeInsets.zero,
                        onSelected: (val) {
                          if (val == 'edit') {
                            _showAddEditExpenseItemDialog(
                              context,
                              event,
                              existingItem: item,
                            );
                          } else if (val == 'delete') {
                            ref
                                .read(clubEventsProvider.notifier)
                                .deleteItem(event.id, item.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              '수정',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              '삭제',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSmallFilterChip(String label, String type, int count) {
    final isSel = _eventFilterType == type;
    return InkWell(
      key: Key('event_filter_$type'),
      onTap: () => setState(() => _eventFilterType = type),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSel ? AppTheme.primaryDark : const Color(0xFFF1F3F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isSel ? Colors.white : AppTheme.textDark,
          ),
        ),
      ),
    );
  }

  /// [+ 새 행사 직접 등록] 다이얼로그
  void _showCreateEventDialog(BuildContext context, Club club) {
    final titleCtrl = TextEditingController();
    final now = DateTime.now();
    final todayStr =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final dateCtrl = TextEditingController(text: todayStr);
    final memoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.event_available_rounded, color: AppTheme.primaryDark),
            SizedBox(width: 8),
            Text(
              '새 행사/모임 출납부 생성',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '행사/모임 명칭 *',
                hintText: '예: 10월 정기모임 정산, 가을 교류전',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(
                labelText: '행사 일자 (YYYY.MM.DD) *',
                hintText: '2026.09.28',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: memoCtrl,
              decoration: const InputDecoration(
                labelText: '행사 메모 (선택)',
                hintText: '장소, 참석 대상 등',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final title = titleCtrl.text.trim();
              final date = dateCtrl.text.trim();
              if (title.isEmpty || date.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('행사명과 일자를 모두 입력해 주세요.')),
                );
                return;
              }
              final newEvent = ref
                  .read(clubEventsProvider.notifier)
                  .createEvent(
                    clubId: club.id,
                    title: title,
                    eventDate: date,
                    memo: memoCtrl.text.trim(),
                  );
              Navigator.pop(dialogCtx);
              setState(() => _selectedEventId = newEvent.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.primaryDark,
                  content: Text('✅ "$title" 출납부가 생성되었습니다.'),
                ),
              );
            },
            child: const Text('생성 완료'),
          ),
        ],
      ),
    );
  }

  /// [📥 출석부 모임 불러오기] 다이얼로그 (일반 모드 출석부 데이터 원클릭 연동)
  void _showImportFromSessionDialog(
    BuildContext context,
    Club club,
    List<Member> members,
  ) {
    final ongoing = ref.read(currentClubOngoingSessionsProvider);
    final archived = ref.read(currentClubArchivedSessionsProvider);
    final allSessions = [...ongoing, ...archived];

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.download_rounded, color: AppTheme.primaryDark),
            SizedBox(width: 8),
            Text(
              '출석부 모임 데이터 불러오기',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: allSessions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '불러올 수 있는 출석부 모임 기록이 없습니다.\n[출석부]에서 모임을 먼저 생성해 보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: allSessions.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFF1F3F8)),
                  itemBuilder: (ctx, idx) {
                    final session = allSessions[idx];
                    final collected = session.calculatePaidFee(members);
                    final count = session.attendees.length;

                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      title: Text(
                        session.displayTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        '${session.sessionDate} · 참석자 $count명 · 수납액 ${FeeLedgerCalculator.formatWon(collected)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryMint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () {
                          final imported = ref
                              .read(clubEventsProvider.notifier)
                              .importFromSession(
                                session: session,
                                members: members,
                              );
                          Navigator.pop(dialogCtx);
                          setState(() => _selectedEventId = imported.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.primaryDark,
                              content: Text(
                                '✅ "${imported.title}" 모임 데이터가 출납부로 연동 생성되었습니다.',
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          '가져오기',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// 수입/지출 내역 추가 및 수정 다이얼로그 (영수증 증빙 사진 첨부 포함)
  void _showAddEditExpenseItemDialog(
    BuildContext context,
    ClubEvent event, {
    EventExpenseItem? existingItem,
  }) {
    bool isIncome = existingItem?.isIncome ?? false;
    final titleCtrl = TextEditingController(text: existingItem?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existingItem != null ? existingItem.amount.toString() : '',
    );
    final dateCtrl =
        TextEditingController(text: existingItem?.date ?? event.eventDate);
    final memoCtrl = TextEditingController(text: existingItem?.memo ?? '');
    String? receiptBase64 = existingItem?.receiptBase64;
    String? receiptFileName = existingItem?.receiptFileName;

    final incomePresets = ['참가비 수납', '클럽 찬조금', '기부금', '기타 수입'];
    final expensePresets = [
      '코트 대관료',
      '셔틀콕 구매',
      '음료/간식비',
      '뒤풀이 식대',
      '시상 상품',
      '기타 지출',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final presets = isIncome ? incomePresets : expensePresets;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  isIncome
                      ? Icons.arrow_circle_up_rounded
                      : Icons.arrow_circle_down_rounded,
                  color: isIncome ? AppTheme.pastelMintDark : AppTheme.pastelRoseDark,
                ),
                const SizedBox(width: 8),
                Text(
                  existingItem == null ? '수입/지출 내역 등록' : '내역 수정',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 수입 vs 지출 선택 토글
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => isIncome = true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isIncome
                                    ? AppTheme.primaryMint
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '수입 (+)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: isIncome
                                      ? Colors.white
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => isIncome = false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: !isIncome
                                    ? AppTheme.pastelRoseDark
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '지출 (-)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: !isIncome
                                      ? Colors.white
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 빠른 항목명 프리셋
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: presets.map((p) {
                      return InkWell(
                        onTap: () => setDialogState(() => titleCtrl.text = p),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4FA),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFDCE0F0)),
                          ),
                          child: Text(
                            p,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '항목명 *',
                      hintText: '예: 코트 대관료, 셔틀콕 구매',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '금액 (원) *',
                      hintText: '숫자만 입력 (예: 50000)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 빠른 금액 버튼 (+1만, +3만, +5만, +10만)
                  Row(
                    children: [10000, 30000, 50000, 100000].map((amt) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () {
                            final cur = int.tryParse(amountCtrl.text) ?? 0;
                            amountCtrl.text = (cur + amt).toString();
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF2FB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+${amt ~/ 10000}만',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(
                      labelText: '일자 *',
                      hintText: 'YYYY.MM.DD',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: memoCtrl,
                    decoration: const InputDecoration(
                      labelText: '메모 (선택)',
                      hintText: '상세 내역',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 영수증 증빙 사진 첨부
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFBFD),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E6F2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 16,
                              color: AppTheme.primaryDark,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '영수증 증빙 사진 첨부',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            if (receiptBase64 != null)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    receiptBase64 = null;
                                    receiptFileName = null;
                                  });
                                },
                                child: const Text(
                                  '삭제',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (receiptBase64 != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(receiptBase64!),
                              height: 90,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            receiptFileName ?? '영수증 첨부됨',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ] else
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryDark,
                              side: const BorderSide(color: Color(0xFFD6DBED)),
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                            ),
                            icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                            label: const Text(
                              '영수증 사진 / 파일 선택',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                            onPressed: () async {
                              final res = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: [
                                  'jpg',
                                  'jpeg',
                                  'png',
                                  'webp',
                                  'gif',
                                ],
                              );
                              if (res.isNotEmpty) {
                                final f = res.first;
                                final bytes = await f.xFile.readAsBytes();
                                setDialogState(() {
                                  receiptFileName = f.name;
                                  receiptBase64 = base64Encode(bytes);
                                });
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
                  final date = dateCtrl.text.trim();
                  if (title.isEmpty || amount <= 0 || date.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('항목명, 0원 이상의 금액, 일자를 올바르게 입력해 주세요.'),
                      ),
                    );
                    return;
                  }

                  if (existingItem == null) {
                    final newItem = EventExpenseItem(
                      id: 'item_${DateTime.now().millisecondsSinceEpoch}',
                      eventId: event.id,
                      title: title,
                      amount: amount,
                      isIncome: isIncome,
                      date: date,
                      memo: memoCtrl.text.trim(),
                      receiptBase64: receiptBase64,
                      receiptFileName: receiptFileName,
                      createdAt: DateTime.now(),
                    );
                    ref
                        .read(clubEventsProvider.notifier)
                        .addItem(event.id, newItem);
                  } else {
                    final updatedItem = existingItem.copyWith(
                      title: title,
                      amount: amount,
                      isIncome: isIncome,
                      date: date,
                      memo: memoCtrl.text.trim(),
                      receiptBase64: receiptBase64,
                      receiptFileName: receiptFileName,
                    );
                    ref
                        .read(clubEventsProvider.notifier)
                        .updateItem(event.id, updatedItem);
                  }

                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryDark,
                      content: Text('✅ "$title" 내역이 저장되었습니다.'),
                    ),
                  );
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 영수증 증빙 원본 미리보기 팝업
  void _showReceiptPreviewDialog(BuildContext context, EventExpenseItem item) {
    if (item.receiptBase64 == null) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: AppTheme.primaryDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '영수증 증빙: ${item.title}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.date} · ${item.isIncome ? "수입" : "지출"} ${FeeLedgerCalculator.formatWon(item.amount)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(item.receiptBase64!),
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// 행사비 출납부 정산 내역 CSV/Excel(UTF-8 BOM) 다운로드
  Future<void> _exportEventCsv(
    BuildContext context,
    Club club,
    ClubEvent event,
  ) async {
    final fileName =
        '${club.clubName}_${event.title.replaceAll(" ", "_")}_정산_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final csvString = EventExpenseCalculator.buildEventCsvString(event);
    final csvBytes =
        Uint8List.fromList(EventExpenseCalculator.buildEventCsvBytes(event));
    final previewLines = csvString.split('\n').take(6).join('\n');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.table_view_rounded, color: AppTheme.primaryDark, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${event.title} 정산 내역 다운로드',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '행사 수입/지출 명세서 및 최종 정산 내역이 엑셀(CSV, UTF-8 BOM)로 다운로드됩니다.',
              style: TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E6F2)),
              ),
              child: Text(
                previewLines,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: Color(0xFF4A5568),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('클립보드 복사'),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await Clipboard.setData(ClipboardData(text: csvString));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정산 내역이 클립보드에 복사되었습니다.')),
                );
              }
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('CSV 다운로드 / 공유'),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                final savedPath = await FilePicker.saveFile(
                  dialogTitle: fileName,
                  fileName: fileName,
                  type: FileType.custom,
                  allowedExtensions: ['csv'],
                  bytes: csvBytes,
                );
                if (savedPath != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryDark,
                      content: Text('✅ $fileName 저장 완료'),
                    ),
                  );
                  return;
                }
              } catch (_) {}

              try {
                final xFile = XFile.fromData(
                  csvBytes,
                  name: fileName,
                  mimeType: 'text/csv;charset=utf-8',
                );
                await SharePlus.instance.share(
                  ShareParams(
                    files: [xFile],
                    fileNameOverrides: [fileName],
                    subject: '$fileName 정산 내역',
                  ),
                );
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: csvString));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('클립보드에 정산 내역 CSV가 복사되었습니다.'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// 행사 삭제 확인 다이얼로그
  void _confirmDeleteEvent(BuildContext context, ClubEvent event) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('행사 출납부 삭제'),
        content: Text('정말 "${event.title}" 행사 정산 출납부를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              ref.read(clubEventsProvider.notifier).deleteEvent(event.id);
              Navigator.pop(dialogCtx);
              setState(() => _selectedEventId = null);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${event.title}" 행사가 삭제되었습니다.')),
              );
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String text,
    double width, {
    bool alignLeft = false,
    bool isHighlighted = false,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: alignLeft ? 10 : 2),
        child: Align(
          alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
          child: Container(
            padding: isHighlighted
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                : EdgeInsets.zero,
            decoration: isHighlighted
                ? BoxDecoration(
                    color: AppTheme.primaryDark,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: isHighlighted ? Colors.white : AppTheme.textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 개별 월 납부 셀 (🟢 완납 / 🔴 미납 / ⚪ 면제/휴면)
  Widget _buildMonthStatusCell({
    required BuildContext context,
    required Club club,
    required Member member,
    required int month,
    required double width,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required bool isReadOnly,
  }) {
    final record = FeeLedgerCalculator.resolveCellRecord(
      ledgerMap: ledgerMap,
      clubId: club.id,
      year: _selectedYear,
      month: month,
      member: member,
      policy: policy,
    );

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String badgeText;

    switch (record.status) {
      case FeeStatus.paid:
        bgColor = AppTheme.pastelMint;
        borderColor = AppTheme.pastelMintDark.withValues(alpha: 0.35);
        textColor = AppTheme.pastelMintDark;
        badgeText = '🟢 완납';
        break;
      case FeeStatus.unpaid:
        bgColor = AppTheme.pastelCoral;
        borderColor = AppTheme.pastelCoralDark.withValues(alpha: 0.35);
        textColor = AppTheme.pastelCoralDark;
        badgeText = '🔴 미납';
        break;
      case FeeStatus.exempt:
        bgColor = const Color(0xFFEEF1F8);
        borderColor = const Color(0xFFD0D5E6);
        textColor = AppTheme.textMuted;
        badgeText = '⚪ 면제';
        break;
    }

    String? subText;
    if (record.status == FeeStatus.paid &&
        record.paidDate != null &&
        record.paidDate!.trim().isNotEmpty) {
      final parts = record.paidDate!.split('.');
      if (parts.length >= 3) {
        subText = '${parts[1]}.${parts[2]}';
      } else {
        subText = record.paidDate;
      }
    } else if (record.status == FeeStatus.exempt &&
        record.memo != null &&
        record.memo!.isNotEmpty) {
      subText = record.memo!.contains('휴회') || record.memo!.contains('휴면')
          ? '휴면/휴회'
          : '면제';
    }

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: InkWell(
          onTap: () {
            if (isReadOnly) {
              _showReadOnlyCellInfoDialog(
                context: context,
                member: member,
                year: _selectedYear,
                month: month,
                record: record,
                policy: policy,
              );
            } else {
              _showEditCellRecordDialog(
                context: context,
                clubId: club.id,
                member: member,
                year: _selectedYear,
                month: month,
                currentRecord: record,
                policy: policy,
              );
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: month == _selectedMonth
                    ? AppTheme.primaryDark.withValues(alpha: 0.65)
                    : borderColor,
                width: month == _selectedMonth ? 1.4 : 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                ),
                if (subText != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subText,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: textColor.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 셀 클릭(Tap) 시: 완납/미납/면제 빠른 상태 변경 및 입금일자/메모 입력 팝업
  void _showEditCellRecordDialog({
    required BuildContext context,
    required String clubId,
    required Member member,
    required int year,
    required int month,
    required MonthlyFeeRecord currentRecord,
    required ClubFeePolicy policy,
  }) {
    FeeStatus selectedStatus = currentRecord.status;
    final standardFee =
        FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);
    final amountCtrl = TextEditingController(
      text: (currentRecord.paidAmount ?? standardFee).toString(),
    );
    final dateCtrl = TextEditingController(
      text: currentRecord.paidDate ??
          DateFormat('yyyy.MM.dd').format(DateTime.now()),
    );
    final memoCtrl = TextEditingController(text: currentRecord.memo ?? '');
    final autoReason =
        FeeLedgerCalculator.resolveAutoExemptReason(member, year, month);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelPeriwinkle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_calendar_rounded,
                    size: 18,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${member.name} · $year년 $month월 회비 상태',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        '기준 월 회비: ${FeeLedgerCalculator.formatWon(standardFee)} (${FeeLedgerCalculator.getMemberFeePolicySubLabel(member, policy)})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (autoReason != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelPeriwinkle.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '💡 회원 프로필 연동 안내: 해당 월은 [$autoReason] 대상입니다.',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ),
                    ],
                    const Text(
                      '납부 상태 빠른 선택',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatusSelectButton(
                            label: '🟢 완납',
                            isSelected: selectedStatus == FeeStatus.paid,
                            activeBg: AppTheme.pastelMintDark,
                            onTap: () => setModalState(
                              () => selectedStatus = FeeStatus.paid,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildStatusSelectButton(
                            label: '🔴 미납',
                            isSelected: selectedStatus == FeeStatus.unpaid,
                            activeBg: AppTheme.pastelCoralDark,
                            onTap: () => setModalState(
                              () => selectedStatus = FeeStatus.unpaid,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildStatusSelectButton(
                            label: '⚪ 면제/휴면',
                            isSelected: selectedStatus == FeeStatus.exempt,
                            activeBg: AppTheme.primaryDark,
                            onTap: () => setModalState(
                              () => selectedStatus = FeeStatus.exempt,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('dialog_annual_all_paid_button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.pastelMintDark,
                            side: BorderSide(
                              color: AppTheme.pastelMintDark.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            await ref
                                .read(feeLedgerProvider.notifier)
                                .markMemberPeriodAllPaid(
                                  clubId: clubId,
                                  year: year,
                                  member: member,
                                  policy: policy,
                                  paidDate: dateCtrl.text.trim(),
                                );
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppTheme.primaryDark,
                                  content: Text(
                                    '✅ ${member.name} 회원의 $year년 1~12월 [1년 일괄 완납] 처리가 완료되었습니다.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.done_all_rounded, size: 14),
                          label: const Text(
                            '1년 일괄 완납',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryDark,
                            side: BorderSide(
                              color: AppTheme.primaryDark.withValues(alpha: 0.35),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            await ref
                                .read(feeLedgerProvider.notifier)
                                .markMemberPeriodAllPaid(
                                  clubId: clubId,
                                  year: year,
                                  member: member,
                                  policy: policy,
                                  startMonth: 1,
                                  endMonth: 6,
                                  paidDate: dateCtrl.text.trim(),
                                );
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                          },
                          child: const Text(
                            '상반기(1~6월) 일괄 완납',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryDark,
                            side: BorderSide(
                              color: AppTheme.primaryDark.withValues(alpha: 0.35),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            await ref
                                .read(feeLedgerProvider.notifier)
                                .markMemberPeriodAllPaid(
                                  clubId: clubId,
                                  year: year,
                                  member: member,
                                  policy: policy,
                                  startMonth: 7,
                                  endMonth: 12,
                                  paidDate: dateCtrl.text.trim(),
                                );
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                          },
                          child: const Text(
                            '하반기(7~12월) 일괄 완납',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (selectedStatus == FeeStatus.paid) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '납부 금액 (원)',
                                suffixText: '원',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: dateCtrl,
                              decoration: InputDecoration(
                                labelText: '입금일자',
                                hintText: '2026.09.18',
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 16,
                                    color: AppTheme.primaryDark,
                                  ),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: DateTime(year, month, 18),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2032),
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        dateCtrl.text = DateFormat(
                                          'yyyy.MM.dd',
                                        ).format(picked);
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: memoCtrl,
                      decoration: const InputDecoration(
                        labelText: '입금/면제 메모 (선택)',
                        hintText: '예: 카카오페이 이체, 가족할인, 엘보 부상 휴회 등',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await ref
                      .read(feeLedgerProvider.notifier)
                      .resetCellToAutoDefault(
                        clubId: clubId,
                        year: year,
                        memberId: member.id,
                        month: month,
                      );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                },
                child: const Text(
                  '프로필 자동값 복원',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final parsedAmt =
                      int.tryParse(amountCtrl.text.trim()) ?? standardFee;
                  final updatedRecord = MonthlyFeeRecord(
                    status: selectedStatus,
                    paidAmount: selectedStatus == FeeStatus.paid ? parsedAmt : 0,
                    paidDate: selectedStatus == FeeStatus.paid
                        ? dateCtrl.text.trim()
                        : null,
                    memo: memoCtrl.text.trim().isEmpty
                        ? null
                        : memoCtrl.text.trim(),
                    isManualOverride: true,
                  );
                  await ref.read(feeLedgerProvider.notifier).updateCellRecord(
                        clubId: clubId,
                        year: year,
                        memberId: member.id,
                        month: month,
                        record: updatedRecord,
                      );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                },
                child: const Text(
                  '저장하기',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusSelectButton({
    required String label,
    required bool isSelected,
    required Color activeBg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeBg : const Color(0xFFD9DDF0),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: isSelected ? Colors.white : AppTheme.textDark,
            ),
          ),
        ),
      ),
    );
  }

  void _showReadOnlyCellInfoDialog({
    required BuildContext context,
    required Member member,
    required int year,
    required int month,
    required MonthlyFeeRecord record,
    required ClubFeePolicy policy,
  }) {
    final standardFee =
        FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          '${member.name} · $year년 $month월 납부 상세',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• 납부 상태: ${record.status.label}'),
            const SizedBox(height: 4),
            Text(
              '• 월 회비 기준액: ${FeeLedgerCalculator.formatWon(standardFee)} (${FeeLedgerCalculator.getMemberFeePolicySubLabel(member, policy)})',
            ),
            if (record.paidDate != null && record.paidDate!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('• 입금일자: ${record.paidDate}'),
            ],
            if (record.memo != null && record.memo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('• 비고/메모: ${record.memo}'),
            ],
          ],
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

  /// 클럽 기본 회비 정책 및 계좌 정보 수정 팝업
  void _showEditFeePolicyDialog(
    BuildContext context,
    Club currentClub,
    ClubFeePolicy policy,
  ) {
    final feeCtrl = TextEditingController(
      text: policy.defaultMonthlyFee.toString(),
    );
    final dueDayCtrl = TextEditingController(
      text: policy.paymentDueDay.toString(),
    );
    final bankCtrl = TextEditingController(text: policy.bankName);
    final accountCtrl = TextEditingController(text: policy.accountNumber);
    final holderCtrl = TextEditingController(text: policy.accountHolder);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '클럽 기본 회비 정책 및 입금 계좌 설정',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: feeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '기본 월 회비 (신규 회원 등록 시 기본값 연동)',
                    suffixText: '원',
                    hintText: '30000',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dueDayCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '정기 납부 마감일 (매월 N일)',
                    suffixText: '일',
                    hintText: '25',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(
                    labelText: '은행명',
                    hintText: '예: 카카오뱅크, 신한은행, 국민은행',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: accountCtrl,
                  decoration: const InputDecoration(
                    labelText: '계좌번호',
                    hintText: '예: 3333-01-5829104',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: holderCtrl,
                  decoration: const InputDecoration(
                    labelText: '예금주',
                    hintText: '예: 김연아(메가배드민턴)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final fee =
                  int.tryParse(feeCtrl.text.trim()) ?? policy.defaultMonthlyFee;
              final dueDay = (int.tryParse(dueDayCtrl.text.trim()) ?? 25)
                  .clamp(1, 31);
              final updated = policy.copyWith(
                defaultMonthlyFee: fee,
                paymentDueDay: dueDay,
                bankName: bankCtrl.text.trim().isEmpty
                    ? policy.bankName
                    : bankCtrl.text.trim(),
                accountNumber: accountCtrl.text.trim().isEmpty
                    ? policy.accountNumber
                    : accountCtrl.text.trim(),
                accountHolder: holderCtrl.text.trim().isEmpty
                    ? policy.accountHolder
                    : holderCtrl.text.trim(),
              );
              await ref
                  .read(clubFeePoliciesProvider.notifier)
                  .updatePolicy(updated);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppTheme.primaryDark,
                    content: Text('클럽 기본 회비 정책 및 입금 계좌가 저장되었습니다.'),
                  ),
                );
              }
            },
            child: const Text('저장하기'),
          ),
        ],
      ),
    );
  }

  /// ① [📷 밴드 공지용 이미지 저장] 모달 ('당월 납부 현황 카드' 및 '연간 장부 전체 표' PNG 캡처/저장)
  void _showBandImageExportModal({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
    required MonthlyFeeSummary summary,
  }) {
    int captureMode = 0; // 0 = 당월 납부 현황 카드 (밴드 피드 최적화), 1 = 연간 장부 전체 표
    final GlobalKey repaintKey = GlobalKey();
    bool isCapturing = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 14, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            title: Row(
              children: [
                const Text('📷', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '네이버 밴드 공지용 고해상도 이미지 저장',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        '밴드 피드/단톡방 공지에 최적화된 PNG 이미지를 생성합니다',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            content: SizedBox(
              width: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusSelectButton(
                          label: '① 당월 납부 현황 카드 (완납/미납 + 계좌)',
                          isSelected: captureMode == 0,
                          activeBg: AppTheme.primaryDark,
                          onTap: () => setModalState(() => captureMode = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusSelectButton(
                          label: '② $_selectedYear년 연간 장부 전체 표',
                          isSelected: captureMode == 1,
                          activeBg: AppTheme.primaryDark,
                          onTap: () => setModalState(() => captureMode = 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: RepaintBoundary(
                          key: repaintKey,
                          child: captureMode == 0
                              ? _buildBandMonthlyShareCardWidget(
                                  club: club,
                                  policy: policy,
                                  summary: summary,
                                )
                              : _buildBandAnnualTableShareWidget(
                                  club: club,
                                  members: members
                                      .where((m) => !m.isGuest)
                                      .toList(),
                                  ledgerMap: ledgerMap,
                                  policy: policy,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('닫기'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: isCapturing
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 17),
                label: Text(
                  captureMode == 0
                      ? '당월 납부 현황 카드 PNG 저장'
                      : '연간 장부 전체 표 PNG 저장',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                onPressed: isCapturing
                    ? null
                    : () async {
                        setModalState(() => isCapturing = true);
                        try {
                          final boundary = repaintKey.currentContext
                              ?.findRenderObject() as RenderRepaintBoundary?;
                          if (boundary == null) return;
                          final uiImage = await boundary.toImage(
                            pixelRatio: 2.5,
                          );
                          final byteData = await uiImage.toByteData(
                            format: ui.ImageByteFormat.png,
                          );
                          if (byteData == null) return;
                          final pngBytes = byteData.buffer.asUint8List();
                          final fileName = captureMode == 0
                              ? '${club.clubName}_$_selectedYear년$_selectedMonth월_회비납부현황카드.png'
                              : '${club.clubName}_$_selectedYear년_연간회비장부표.png';

                          if (context.mounted) {
                            await _saveOrSharePngBytes(
                              context,
                              fileName: fileName,
                              pngBytes: pngBytes,
                            );
                          }
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        } finally {
                          if (ctx.mounted) {
                            setModalState(() => isCapturing = false);
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 네이버 밴드 피드 최적화 '당월 납부 현황 카드 (완납/미납자 명단 + 입금 계좌)' 위젯
  Widget _buildBandMonthlyShareCardWidget({
    required Club club,
    required ClubFeePolicy policy,
    required MonthlyFeeSummary summary,
  }) {
    return Container(
      width: 460,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryDark, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryDark, Color(0xFF7565E8)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🏸 ${club.clubName}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_selectedYear년 $_selectedMonth월 정기 회비 납부 현황',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '수납률 ${summary.collectionRate.toStringAsFixed(1)}% · 총 수납액 ${summary.formattedCollectedAmount}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 완납자 명단
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.pastelMint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🟢 완납 회원 (${summary.paidCount}명)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.pastelMintDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.paidMembers.isEmpty
                      ? '완납 내역 없음'
                      : summary.paidMembers.map((m) => m.name).join(', '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 미납자 명단
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.pastelCoral,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔴 미납 확인 대상 (${summary.unpaidCount}명)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.pastelCoralDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.unpaidMembers.isEmpty
                      ? '전원 완납 완료 🎉'
                      : summary.unpaidMembers.map((m) => m.name).join(', '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 면제/휴면 명단
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '⚪ 면제/휴면 (${summary.exemptCount}명): ${summary.exemptMembers.map((m) => m.name).join(', ')}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 입금 계좌 박스
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.pastelPeriwinkle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💳 회비 입금 계좌 안내',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${policy.bankName} ${policy.accountNumber} (예금주: ${policy.accountHolder})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  '기본 월 회비: ${policy.formattedDefaultFee} · 정기 납부 마감일: ${policy.formattedDueDay}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 네이버 밴드 공지용 '연간 장부 전체 표' 캡처 위젯
  Widget _buildBandAnnualTableShareWidget({
    required Club club,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${club.clubName} · $_selectedYear년 연간/월별 회비 납부 현황표',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryDark,
            ),
          ),
          Text(
            '기본 월 회비: ${policy.formattedDefaultFee} | 마감일: ${policy.formattedDueDay} | 입금계좌: ${policy.formattedBankAccount}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          _buildMatrixTableContent(
            context: context,
            club: club,
            members: members,
            allClubMembers: members,
            ledgerMap: ledgerMap,
            policy: policy,
            isReadOnly: true,
          ),
        ],
      ),
    );
  }

  Future<void> _saveOrSharePngBytes(
    BuildContext context, {
    required String fileName,
    required Uint8List pngBytes,
  }) async {
    try {
      final savedPath = await FilePicker.saveFile(
        dialogTitle: fileName,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: pngBytes,
      );
      if (savedPath != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.primaryDark,
              content: Text('이미지가 저장되었습니다: $fileName'),
            ),
          );
        }
        return;
      }
    } catch (_) {}

    try {
      final xFile = XFile.fromData(
        pngBytes,
        name: fileName,
        mimeType: 'image/png',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          fileNameOverrides: [fileName],
          subject: fileName,
        ),
      );
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primaryDark,
          content: Text('밴드 공지용 고해상도 이미지($fileName)가 생성되었습니다.'),
        ),
      );
    }
  }

  /// ② [🔗 실시간 회비 웹뷰어 링크 복사]
  Future<void> _copyWebViewerLinkAndShowPreview({
    required BuildContext context,
    required Club club,
  }) async {
    final shareUrl =
        'https://songsunjeung.github.io/cockmatch/#/viewer/fees?clubId=${club.id}&year=$_selectedYear&month=$_selectedMonth';
    await Clipboard.setData(ClipboardData(text: shareUrl));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.primaryDark,
        duration: const Duration(seconds: 4),
        content: Text(
          '실시간 회비 웹뷰어 링크가 복사되었습니다!\n$shareUrl',
          style: const TextStyle(fontSize: 12),
        ),
        action: SnackBarAction(
          label: '웹뷰어 열기',
          textColor: AppTheme.pastelBlue,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FeeStatusWebViewerScreen(
                  clubId: club.id,
                  initialYear: _selectedYear,
                  initialMonth: _selectedMonth,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// ③ [📢 미납자 카톡 독려 문구 복사] 다이얼로그
  void _showKakaoUnpaidMessageDialog({
    required BuildContext context,
    required Club club,
    required MonthlyFeeSummary summary,
    required ClubFeePolicy policy,
  }) {
    final messageText = FeeLedgerCalculator.buildKakaoUnpaidReminderMessage(
      clubName: club.clubName,
      year: _selectedYear,
      month: _selectedMonth,
      summary: summary,
      policy: policy,
    );
    final msgCtrl = TextEditingController(text: messageText);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('📢', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '미납자 카톡 독려 문구 생성 및 복사',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '이번 달 미납자 명단과 클럽 입금 계좌가 자동으로 조합되었습니다. 내용을 확인·수정한 뒤 복사해 단톡방에 붙여넣으세요.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: msgCtrl,
                maxLines: 11,
                style: const TextStyle(fontSize: 12, height: 1.45),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text(
              '카톡 독려 문구 복사하기',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: msgCtrl.text.trim()));
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppTheme.primaryDark,
                    content: Text(
                      '미납자 카톡 독려 문구가 클립보드에 복사되었습니다!',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// ④ [📊 엑셀 다운로드] 다이얼로그
  void _showExcelExportDialog({
    required BuildContext context,
    required Club club,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
  }) {
    final fileName =
        '${club.clubName}_$_selectedYear년_연간회비장부_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final csvString = FeeLedgerCalculator.buildAnnualLedgerCsvString(
      clubName: club.clubName,
      clubId: club.id,
      year: _selectedYear,
      members: members,
      ledgerMap: ledgerMap,
      policy: policy,
    );
    final csvBytes = FeeLedgerCalculator.buildAnnualLedgerCsvBytes(
      clubName: club.clubName,
      clubId: club.id,
      year: _selectedYear,
      members: members,
      ledgerMap: ledgerMap,
      policy: policy,
    );
    final previewLines = csvString.split('\n').take(7).join('\n');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('📊', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '연간 회비 장부 엑셀(CSV) 다운로드',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• 파일명: $fileName\n'
                '• 포함 구간: $_selectedYear년 1월 ~ 12월 전체 납부 상태 및 연간 납부 합계\n'
                '• 인코딩: UTF-8 BOM 적용 (엑셀에서 바로 열어도 한글이 깨지지 않습니다)',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDCE0F0)),
                ),
                child: Text(
                  previewLines,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: AppTheme.textDark,
                  ),
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.pastelMintDark,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text(
              '엑셀 파일 저장 / 공유',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await Clipboard.setData(ClipboardData(text: csvString));
              try {
                final savedPath = await FilePicker.saveFile(
                  dialogTitle: fileName,
                  fileName: fileName,
                  type: FileType.custom,
                  allowedExtensions: ['csv'],
                  bytes: csvBytes,
                );
                if (savedPath != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryDark,
                      content: Text('$fileName 파일이 저장되었습니다.'),
                    ),
                  );
                  return;
                }
              } catch (_) {}

              try {
                final xFile = XFile.fromData(
                  csvBytes,
                  name: fileName,
                  mimeType: 'text/csv;charset=utf-8',
                );
                await SharePlus.instance.share(
                  ShareParams(
                    files: [xFile],
                    fileNameOverrides: [fileName],
                    subject: fileName,
                  ),
                );
              } catch (_) {}

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.primaryDark,
                    content: Text(
                      '$fileName 데이터가 생성 및 클립보드에 백업되었습니다.',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// [읽기 전용 실시간 회비 웹뷰어 라우트 화면] (`/viewer/fees`)
/// - 회원이 공유 링크로 접속하여 실시간 입금 반영 내역을 확인할 수 있는 읽기 전용 뷰어
/// - 하단에는 배너 광고 슬롯 (`AdBannerSlot(placement: BannerPlacement.bottom)`) 상시 노출
/// ============================================================================
class FeeStatusWebViewerScreen extends ConsumerStatefulWidget {
  final String? clubId;
  final int initialYear;
  final int initialMonth;

  const FeeStatusWebViewerScreen({
    super.key,
    this.clubId,
    this.initialYear = 2026,
    this.initialMonth = 9,
  });

  @override
  ConsumerState<FeeStatusWebViewerScreen> createState() =>
      _FeeStatusWebViewerScreenState();
}

class _FeeStatusWebViewerScreenState
    extends ConsumerState<FeeStatusWebViewerScreen> {
  late int _selectedYear;
  late int _selectedMonth;
  FeeLedgerFilter _selectedFilter = FeeLedgerFilter.all;
  bool _isRulesExpanded = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    _selectedMonth = widget.initialMonth;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(clubsProvider);
    final activeClubId = widget.clubId ?? ref.watch(currentClubIdProvider);
    final club = clubs.firstWhere(
      (c) => c.id == activeClubId,
      orElse: () => clubs.first,
    );
    final allMembers = ref
        .watch(membersProvider)
        .where((m) => m.clubId == club.id && !m.isGuest)
        .toList();
    final policies = ref.watch(clubFeePoliciesProvider);
    final policy = policies[club.id] ?? ClubFeePolicy(clubId: club.id);
    final ledgerMap = ref.watch(feeLedgerProvider);

    final summary = FeeLedgerCalculator.calculateMonthlySummary(
      ledgerMap: ledgerMap,
      clubId: club.id,
      year: _selectedYear,
      month: _selectedMonth,
      members: allMembers,
      policy: policy,
    );

    final filteredMembers = allMembers.where((member) {
      if (_searchQuery.trim().isNotEmpty) {
        if (!KoreanSearchUtil.matches(member.name, _searchQuery)) return false;
      }
      final rec = FeeLedgerCalculator.resolveCellRecord(
        ledgerMap: ledgerMap,
        clubId: club.id,
        year: _selectedYear,
        month: _selectedMonth,
        member: member,
        policy: policy,
      );
      switch (_selectedFilter) {
        case FeeLedgerFilter.all:
          return true;
        case FeeLedgerFilter.currentMonthUnpaid:
          return rec.status == FeeStatus.unpaid;
        case FeeLedgerFilter.exemptOrResting:
          return rec.status == FeeStatus.exempt ||
              member.status == MemberStatus.resting ||
              member.feePolicy == FeePolicyType.exempt;
        case FeeLedgerFilter.familyDiscount:
          return FeeLedgerCalculator.isFamilyDiscountMember(member, policy);
      }
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.pastelBlue,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'LIVE 읽기 전용 웹뷰어',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.pastelBlueDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${club.clubName} 회비 납부 현황',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                children: [
                  // 1. 입금 계좌 및 기본 정책 안내 카드
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE4E7F4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_rounded,
                              size: 16,
                              color: AppTheme.primaryDark,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '입금 계좌: ${policy.bankName} ${policy.accountNumber} (${policy.accountHolder})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        '${policy.bankName} ${policy.accountNumber}',
                                  ),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('계좌번호가 복사되었습니다.'),
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.pastelPeriwinkle,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '계좌 복사',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '기본 월 회비: ${policy.formattedDefaultFee} · 정기 납부 마감일: ${policy.formattedDueDay}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 2. 접이식 클럽 회비 회칙 (읽기 전용)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE4E7F4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(
                            () => _isRulesExpanded = !_isRulesExpanded,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                const Text('📜', style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    '클럽 회비 회칙 & 안내 보기',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _isRulesExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: AppTheme.primaryDark,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isRulesExpanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                            child: Text(
                              policy.rulesAndMemo,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textDark,
                                height: 1.45,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. 연도/월 선택 및 수납 요약
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE4E7F4)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            DropdownButton<int>(
                              value: _selectedYear,
                              underline: const SizedBox.shrink(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryDark,
                              ),
                              items: [2025, 2026, 2027]
                                  .map(
                                    (y) => DropdownMenuItem(
                                      value: y,
                                      child: Text('$y년 납부 현황'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedYear = v);
                                }
                              },
                            ),
                            Text(
                              '$_selectedMonth월 수납률 ${summary.collectionRate.toStringAsFixed(1)}% (${summary.formattedCollectedAmount})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(
                                  '🟢 완납 ${summary.paidCount}명',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.pastelMintDark,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '🔴 미납 ${summary.unpaidCount}명',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.pastelCoralDark,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '⚪ 면제/휴면 ${summary.exemptCount}명',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 4. 조회 필터 칩 및 회원 검색
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: FeeLedgerFilter.values.map((f) {
                        final selected = _selectedFilter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f.label),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedFilter = f),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '내 이름 검색 (초성 지원)...',
                      prefixIcon: Icon(Icons.search_rounded, size: 17),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 5. 읽기 전용 매트릭스 표
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE4E7F4)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: filteredMembers.map((member) {
                            final annualSum =
                                FeeLedgerCalculator.calculateMemberAnnualTotal(
                              ledgerMap: ledgerMap,
                              clubId: club.id,
                              year: _selectedYear,
                              member: member,
                              policy: policy,
                            );
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      '${member.name} (${member.displayRoleLabel})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  for (int m = 1; m <= 12; m++)
                                    Builder(
                                      builder: (_) {
                                        final r = FeeLedgerCalculator
                                            .resolveCellRecord(
                                          ledgerMap: ledgerMap,
                                          clubId: club.id,
                                          year: _selectedYear,
                                          month: m,
                                          member: member,
                                          policy: policy,
                                        );
                                        final badge = switch (r.status) {
                                          FeeStatus.paid => '🟢$m월',
                                          FeeStatus.unpaid => '🔴$m월',
                                          FeeStatus.exempt => '⚪$m월',
                                        };
                                        return Container(
                                          width: 52,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: r.status == FeeStatus.paid
                                                ? AppTheme.pastelMint
                                                : (r.status == FeeStatus.unpaid
                                                      ? AppTheme.pastelCoral
                                                      : const Color(0xFFEEF1F8)),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Center(
                                            child: Text(
                                              badge,
                                              style: const TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      FeeLedgerCalculator.formatWon(annualSum),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.primaryDark,
                                      ),
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
                ],
              ),
            ),

            // 웹뷰어 하단 배너 광고 슬롯 포함 (요구사항 3-②)
            const AdBannerSlot(
              placement: BannerPlacement.bottom,
            ),
          ],
        ),
      ),
    );
  }
}
