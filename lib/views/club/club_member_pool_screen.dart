import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/club_service.dart';

/// [화면 1] 회원 명부 화면
/// - 순수 회원 정보(주소록) 관리: 추가, 수정, 삭제, 검색, 3종 드롭다운 필터링
/// - 우측 상단 더보기(⋮) 메뉴: [CSV로 회원 대량 등록] / [회원명부 CSV 다운로드]
class ClubMemberPoolScreen extends ConsumerStatefulWidget {
  const ClubMemberPoolScreen({super.key});

  @override
  ConsumerState<ClubMemberPoolScreen> createState() => _ClubMemberPoolScreenState();
}

class _ClubMemberPoolScreenState extends ConsumerState<ClubMemberPoolScreen> {
  final TextEditingController _searchController = TextEditingController();

  // 롱프레스 다중 선택 문자 발송 모드 상태
  bool _isMultiSelectMode = false;
  final Set<String> _selectedMemberIds = {};

  void _toggleMultiSelectMember(String memberId) {
    setState(() {
      if (_selectedMemberIds.contains(memberId)) {
        _selectedMemberIds.remove(memberId);
        if (_selectedMemberIds.isEmpty) {
          _isMultiSelectMode = false;
        }
      } else {
        _selectedMemberIds.add(memberId);
        _isMultiSelectMode = true;
      }
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedMemberIds.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentClub = ref.watch(currentClubProvider);
    final clubMembers = ref.watch(currentClubMembersProvider);
    final filteredMembers = ref.watch(filteredMembersProvider);
    final activeFilter = ref.watch(memberFilterProvider);

    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0 ||
        View.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // 1. 컴팩트 상단 헤더 & 빠른 액션
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    child: Row(
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => _showClubSwitchBottomSheet(context, ref),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          currentClub.clubName,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textDark,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.arrow_drop_down_rounded,
                                        size: 24,
                                        color: AppTheme.primaryDark,
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.pastelMint,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '총 ${clubMembers.length}명',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.pastelMintDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    currentClub.description ?? '회원 명부 및 주소록 관리 (터치하여 모임 전환)',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 20,
                            color: AppTheme.primaryDark,
                          ),
                          tooltip: '연간/월별 회비 납부 현황표',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              ref.read(currentTabProvider.notifier).setTab(4),
                        ),
                        IconButton(
                          icon: const Icon(Icons.sms_rounded, size: 21, color: AppTheme.primaryMint),
                          tooltip: '단체 문자 발송',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _showGroupSmsDialog(context, clubMembers),
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 21),
                          tooltip: '신규 회원 직접 등록',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _showAddMemberDialog(context),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 22, color: AppTheme.textDark),
                          tooltip: '더보기 메뉴',
                          offset: const Offset(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          color: Colors.white,
                          elevation: 8,
                          onSelected: (value) {
                            if (value == 'csv_import') {
                              _showCsvImportDialog(context, currentClub, clubMembers);
                            } else if (value == 'csv_export') {
                              _showCsvExportDialog(context, currentClub, clubMembers);
                            } else if (value == 'text_batch') {
                              _showBatchAddDialog(context);
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem<String>(
                              value: 'csv_import',
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: AppTheme.pastelMint.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.upload_file_rounded,
                                      size: 18,
                                      color: AppTheme.pastelMintDark,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'CSV로 회원 대량 등록',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textDark,
                                          ),
                                        ),
                                        Text(
                                          '엑셀/CSV 파일 업로드 및 미리보기 검증',
                                          style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'csv_export',
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: AppTheme.pastelPeriwinkle.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.download_rounded,
                                      size: 18,
                                      color: AppTheme.pastelPeriwinkleDark,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '회원명부 CSV 다운로드',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textDark,
                                          ),
                                        ),
                                        Text(
                                          '전체 회원 백업 내보내기 (UTF-8 BOM)',
                                          style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem<String>(
                              value: 'text_batch',
                              child: Row(
                                children: [
                                  Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textMuted),
                                  SizedBox(width: 10),
                                  Text(
                                    '명단 텍스트 대량 등록',
                                    style: TextStyle(fontSize: 12.5, color: AppTheme.textDark),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. 실시간 이름/초성 검색창 + 우측 컴팩트 정렬 버튼(⇅)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.025),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: '이름 또는 초성 검색 (예: 안세영, ㅇㅅㅇ, ㅎㄱㄷ)',
                                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.cancel_rounded, size: 18, color: AppTheme.textMuted),
                                        onPressed: () {
                                          _searchController.clear();
                                          ref.read(memberFilterProvider.notifier).update(
                                                (prev) => prev.copyWith(searchQuery: ''),
                                              );
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              onChanged: (val) {
                                ref.read(memberFilterProvider.notifier).update(
                                      (prev) => prev.copyWith(searchQuery: val),
                                    );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildMemberSortButton(activeFilter.sortBy),
                      ],
                    ),
                  ),
                ),

                // 3. 컴팩트 드롭다운 필터 3종 (급수 / 회원 구분 / 성별 - 한 줄 균등 배치)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Row(
                      children: [
                        // 1) [급수]: 전체, A조, B조, C조, D조, 초심
                        Expanded(
                          child: _buildCompactDropdownFilter(
                            filterTitle: '급수',
                            selectedLabel: activeFilter.tier?.label ?? '전체',
                            isActive: activeFilter.tier != null,
                            currentKey: activeFilter.tier?.code ?? 'ALL',
                            items: [
                              (key: 'ALL', label: '전체'),
                              ...Tier.values.map((t) => (key: t.code, label: t.label)),
                            ],
                            onSelected: (key) {
                              ref.read(memberFilterProvider.notifier).update((prev) {
                                if (key == 'ALL') {
                                  return prev.copyWith(clearTier: true);
                                }
                                final selectedTier = Tier.fromString(key);
                                return prev.copyWith(tier: selectedTier);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 2) [회원 구분]: 전체, 운영진, 정회원, 준회원
                        Expanded(
                          child: _buildCompactDropdownFilter(
                            filterTitle: '회원 구분',
                            selectedLabel: activeFilter.grade?.label ?? '전체',
                            isActive: activeFilter.grade != null,
                            currentKey: activeFilter.grade?.code ?? 'ALL',
                            items: [
                              (key: 'ALL', label: '전체'),
                              ...MemberGrade.values.map((g) => (key: g.code, label: g.label)),
                            ],
                            onSelected: (key) {
                              ref.read(memberFilterProvider.notifier).update((prev) {
                                if (key == 'ALL') {
                                  return prev.copyWith(clearGrade: true);
                                }
                                final selectedGrade = MemberGrade.values.firstWhere(
                                  (g) => g.code == key,
                                  orElse: () => MemberGrade.regular,
                                );
                                return prev.copyWith(grade: selectedGrade);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 3) [성별]: 전체, 남성, 여성
                        Expanded(
                          child: _buildCompactDropdownFilter(
                            filterTitle: '성별',
                            selectedLabel: activeFilter.gender?.label ?? '전체',
                            isActive: activeFilter.gender != null,
                            currentKey: activeFilter.gender?.code ?? 'ALL',
                            items: [
                              (key: 'ALL', label: '전체'),
                              (key: Gender.male.code, label: Gender.male.label),
                              (key: Gender.female.code, label: Gender.female.label),
                            ],
                            onSelected: (key) {
                              ref.read(memberFilterProvider.notifier).update((prev) {
                                if (key == 'ALL') {
                                  return prev.copyWith(clearGender: true);
                                }
                                final selectedGender = Gender.fromCode(key);
                                return prev.copyWith(gender: selectedGender);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. 회원 목록 요약 헤더
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '전체 회원 명부',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '(${filteredMembers.length}명)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryMint,
                              ),
                            ),
                            if (activeFilter.hasActiveFilters) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => ref
                                    .read(memberFilterProvider.notifier)
                                    .update((prev) => MemberFilter(
                                          searchQuery: prev.searchQuery,
                                          sortBy: prev.sortBy,
                                        )),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.refresh_rounded, size: 11, color: AppTheme.textDark),
                                      SizedBox(width: 3),
                                      Text(
                                        '필터 초기화',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        InkWell(
                          onTap: () => _showGroupSmsDialog(context, clubMembers),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelMint,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primaryMint.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.sms_outlined, size: 14, color: AppTheme.pastelMintDark),
                                SizedBox(width: 4),
                                Text(
                                  '단체 문자 발송',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.pastelMintDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 5. 회원 목록 가상 스크롤
                if (filteredMembers.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '검색 또는 필터 조건에 일치하는 회원이 없습니다.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      2,
                      20,
                      (_isMultiSelectMode && !isKeyboardOpen) ? 84 : 16,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final member = filteredMembers[index];
                          return _buildMemberCard(context, ref, member);
                        },
                        childCount: filteredMembers.length,
                      ),
                    ),
                  ),
              ],
            ),
            if (_isMultiSelectMode && !isKeyboardOpen)
              Positioned(
                left: 20,
                right: 20,
                bottom: 12,
                child: _buildMultiSelectMemberSmsBar(
                  context: context,
                  clubMembers: clubMembers,
                  filteredMembers: filteredMembers,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 회원명부 컴팩트 정렬 버튼 위젯 (검색창 우측 배치)
  /// - 기본값: 이름순 (가나다) [ㄱ -> ㅎ]
  /// - 선택 옵션: 이름순 (가나다) [기본], 급수순 (상위 급수 우선: A -> 초심), 회원 구분순 (운영진 -> 정회원 -> 준회원), 최근 등록순
  Widget _buildMemberSortButton(MemberSortBy currentSort) {
    final bool isCustomSort = currentSort != MemberSortBy.nameAsc;
    return PopupMenuButton<MemberSortBy>(
      tooltip: '회원명부 정렬',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 6,
      onSelected: (selected) {
        ref.read(memberFilterProvider.notifier).update(
              (prev) => prev.copyWith(sortBy: selected),
            );
      },
      itemBuilder: (ctx) => MemberSortBy.memberPoolOptions.map((option) {
        final isSelected = option == currentSort;
        return PopupMenuItem<MemberSortBy>(
          value: option,
          height: 40,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: isSelected ? AppTheme.primaryMint : Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  option.menuLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? AppTheme.pastelMintDark : AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: isCustomSort
              ? AppTheme.pastelMint.withValues(alpha: 0.35)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCustomSort ? AppTheme.primaryMint : Colors.grey.shade300,
            width: isCustomSort ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⇅ ${currentSort.label}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isCustomSort ? FontWeight.w900 : FontWeight.w800,
                color: isCustomSort ? AppTheme.pastelMintDark : AppTheme.textDark,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: isCustomSort ? AppTheme.pastelMintDark : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  /// 컴팩트 드롭다운 필터 버튼 위젯 (급수 / 회원 구분 / 성별)
  /// - 기본값: '급수: 전체 ▾', '회원 구분: 전체 ▾', '성별: 전체 ▾'
  /// - 선택 시: '급수: B조 ▾' 등 라벨 변경 및 활성화 스타일(테두리/텍스트 강조) 적용
  Widget _buildCompactDropdownFilter({
    required String filterTitle,
    required String selectedLabel,
    required bool isActive,
    required String currentKey,
    required List<({String key, String label})> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: '$filterTitle 필터 선택',
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      elevation: 6,
      onSelected: onSelected,
      itemBuilder: (ctx) => items.map((item) {
        final isItemSelected = item.key == currentKey;
        return PopupMenuItem<String>(
          value: item.key,
          height: 38,
          child: Row(
            children: [
              Icon(
                isItemSelected ? Icons.check_rounded : Icons.circle_outlined,
                size: 15,
                color: isItemSelected ? AppTheme.primaryMint : Colors.transparent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isItemSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isItemSelected ? AppTheme.pastelMintDark : AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.pastelMint.withValues(alpha: 0.35)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppTheme.primaryMint : Colors.grey.shade300,
            width: isActive ? 1.6 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$filterTitle: $selectedLabel ▾',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                color: isActive ? AppTheme.pastelMintDark : AppTheme.textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 회원 명부 카드
  /// - 동그란 남/여 아이콘 제거, 성별에 따라 카드 배경·테두리 컬러 구분 (남: 은은한 블루톤 / 여: 은은한 핑크·코랄톤)
  /// - 짧게 클릭(Tap): 상세 정보 팝업(전화 걸기 / 문자 보내기 / 회원 정보 수정 진입 포함) 호출
  /// - 길게 누르기(Long Press): 다중 선택 체크 모드 전환 및 ["선택한 회원(N명) 문자 발송"] 액션 바 노출
  Widget _buildMemberCard(
    BuildContext context,
    WidgetRef ref,
    Member member,
  ) {
    final tierBg = AppTheme.getTierBgColor(member.tier);
    final tierText = AppTheme.getTierTextColor(member.tier);
    final hasCustomRole =
        member.customRoleTitle != null && member.customRoleTitle!.trim().isNotEmpty;
    final isSelected = _selectedMemberIds.contains(member.id);

    // 등급/직책 배지 스타일
    final Color roleBadgeBg;
    final Color roleBadgeText;
    if (member.isExecutive || hasCustomRole) {
      roleBadgeBg = AppTheme.pastelPeriwinkle;
      roleBadgeText = AppTheme.pastelPeriwinkleDark;
    } else {
      roleBadgeBg = AppTheme.surfaceGrey;
      roleBadgeText = const Color(0xFF5E657E);
    }

    final restingBadge = member.restingBadgeText;
    final feePolicyBadge = member.feePolicyBadgeText;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.getGenderCardBg(member.gender, isDimmed: member.isResting),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: member.isResting && !isSelected
              ? AppTheme.pastelYellowDark.withValues(alpha: 0.45)
              : AppTheme.getGenderCardBorder(
                  member.gender,
                  isSelected: isSelected,
                  isDimmed: member.isResting,
                ),
          width: isSelected ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_isMultiSelectMode) {
              _toggleMultiSelectMember(member.id);
            } else {
              _showMemberDetailPopup(context, ref, member);
            }
          },
          onLongPress: () => _toggleMultiSelectMember(member.id),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (_isMultiSelectMode) ...[
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: AppTheme.primaryDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      onChanged: (_) => _toggleMultiSelectMember(member.id),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Container(
                    width: 4,
                    height: 34,
                    decoration: BoxDecoration(
                      color: member.isResting
                          ? AppTheme.pastelYellowDark
                          : AppTheme.getGenderAccentColor(member.gender),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // 회원 정보 (이름, 등급/직책, 휴면/회비 혜택 뱃지, 연락처)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            member.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: member.isResting ? AppTheme.textMuted : AppTheme.textDark,
                            ),
                          ),
                          // 1) 직책/등급 뱃지 (커스텀 직책 포함)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: roleBadgeBg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              member.displayRoleLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: roleBadgeText,
                              ),
                            ),
                          ),
                          // 2) 휴면 상태 뱃지: 예 [휴면 (복귀 예정 26.11.30)]
                          if (restingBadge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppTheme.pastelYellow,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.pastelYellowDark.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.pause_circle_filled_rounded,
                                    size: 10.5,
                                    color: AppTheme.pastelYellowDark,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    restingBadge,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.pastelYellowDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // 3) 회비 혜택/면제 뱃지: 예 [면제 (~26.12.31)], [가족할인 20,000원], [휴회 면제]
                          if (feePolicyBadge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: member.feePolicy == FeePolicyType.discounted && !member.isResting
                                    ? AppTheme.pastelCoral.withValues(alpha: 0.7)
                                    : AppTheme.pastelPeriwinkle.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                feePolicyBadge,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: member.feePolicy == FeePolicyType.discounted && !member.isResting
                                      ? AppTheme.pastelCoralDark
                                      : AppTheme.pastelPeriwinkleDark,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => _callMember(context, ref, member),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                              child: Text(
                                member.phoneNumber ?? '연락처 미등록 (탭하여 등록)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: member.phoneNumber != null ? FontWeight.w700 : FontWeight.normal,
                                  color: member.phoneNumber != null ? AppTheme.pastelMintDark : AppTheme.textMuted,
                                  decoration: member.phoneNumber != null ? TextDecoration.underline : null,
                                  decorationColor: AppTheme.primaryMint.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          ),
                          if (member.isResting &&
                              member.restingReason != null &&
                              member.restingReason!.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.pastelRose.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '휴면사유: ${member.restingReason!}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.pastelRoseDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ] else if (member.memo != null && member.memo!.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  member.memo!,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // 급수 뱃지 (파스텔 캡슐 - 급수 명칭만 깔끔하게 노출)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tierBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    member.tier.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tierText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 더보기 메뉴 (전화 / 문자 / 수정 / 삭제)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textMuted),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'call') {
                      _callMember(context, ref, member);
                    } else if (val == 'sms') {
                      _sendMemberSms(context, member);
                    } else if (val == 'edit') {
                      _showEditMemberDialog(context, ref, member);
                    } else if (val == 'delete') {
                      ref.read(membersProvider.notifier).deleteMember(member.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${member.name} 회원이 삭제되었습니다.')),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'call',
                      child: Row(
                        children: [
                          Icon(Icons.phone_rounded, size: 16, color: AppTheme.primaryMint),
                          SizedBox(width: 8),
                          Text('전화 걸기', style: TextStyle(color: AppTheme.textDark, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'sms',
                      child: Row(
                        children: [
                          Icon(Icons.sms_rounded, size: 16, color: AppTheme.pastelPeriwinkleDark),
                          SizedBox(width: 8),
                          Text('문자 보내기', style: TextStyle(color: AppTheme.textDark, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16, color: AppTheme.primaryDark),
                          SizedBox(width: 8),
                          Text('회원 정보 수정', style: TextStyle(color: AppTheme.textDark, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('회원 삭제', style: TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 회원 카드 짧게 클릭(Tap) 시 호출되는 상세 정보 팝업 (전화 걸기 / 문자 보내기 / 정보 수정 진입 포함)
  void _showMemberDetailPopup(BuildContext context, WidgetRef ref, Member member) {
    final hasPhone = member.phoneNumber != null && member.phoneNumber!.trim().isNotEmpty;
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
              icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
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
                border: Border.all(color: AppTheme.getGenderCardBorder(member.gender)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '구분: ${member.gender.label} · ${member.displayRoleLabel}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '연락처: ${hasPhone ? member.phoneNumber! : "연락처 미등록"}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                  ),
                  if (restingBadge != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '활동 상태: $restingBadge${member.restingReason != null ? " (${member.restingReason})" : ""}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.pastelYellowDark),
                    ),
                  ],
                  if (feePolicyBadge != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '회비 정책: $feePolicyBadge',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.pastelPeriwinkleDark),
                    ),
                  ],
                  if (member.memo != null && member.memo!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '메모: ${member.memo!}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.call_rounded, size: 17),
                    label: const Text('전화 걸기', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _callMember(context, ref, member);
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.sms_rounded, size: 17),
                    label: const Text('문자 보내기', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _sendMemberSms(context, member);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textDark,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.textDark),
                label: const Text(
                  '회원 정보 수정',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showEditMemberDialog(context, ref, member);
                },
              ),
            ),
          ],
        ),
      ),
    );
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
      final launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: rawPhone));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${member.name} 님 번호($rawPhone)로 문자 앱 연결을 요청했습니다. (sms:)')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: rawPhone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.name} 님의 번호($rawPhone)를 복사했습니다. (sms:$cleanPhone)')),
        );
      }
    }
  }

  /// 롱프레스 다중 선택 시 노출되는 ["선택한 회원(N명) 문자 발송"] 액션 바
  Widget _buildMultiSelectMemberSmsBar({
    required BuildContext context,
    required List<Member> clubMembers,
    required List<Member> filteredMembers,
  }) {
    final selectedCount = _selectedMemberIds.length;
    final allFilteredSelected = filteredMembers.isNotEmpty &&
        filteredMembers.every((m) => _selectedMemberIds.contains(m.id));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryMint, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              setState(() {
                if (allFilteredSelected) {
                  _selectedMemberIds.clear();
                  _isMultiSelectMode = false;
                } else {
                  _selectedMemberIds.addAll(filteredMembers.map((m) => m.id));
                }
              });
            },
            child: Text(
              allFilteredSelected ? '전체해제' : '전체선택',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textDark),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryMint,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.sms_rounded, size: 16),
              label: Text(
                '선택한 회원($selectedCount명) 문자 발송',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
              ),
              onPressed: () async {
                final targets = clubMembers
                    .where((m) => _selectedMemberIds.contains(m.id))
                    .toList();
                final phones = targets
                    .map((m) => (m.phoneNumber ?? '').replaceAll(RegExp(r'[^0-9+]'), ''))
                    .where((p) => p.isNotEmpty)
                    .toList();
                if (phones.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('선택한 회원의 등록된 전화번호가 없습니다.')),
                  );
                  return;
                }
                final recipients = phones.join(',');
                final smsUri = Uri.parse('sms:$recipients');
                try {
                  await launchUrl(smsUri, mode: LaunchMode.externalApplication);
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: recipients));
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.primaryDark,
                      content: Text('선택한 회원(${targets.length}명)에게 단체 문자 앱을 열었습니다. (sms:)'),
                    ),
                  );
                }
                _exitMultiSelectMode();
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '선택 모드 닫기',
            onPressed: _exitMultiSelectMode,
            icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  /// 회원 정보 수정 다이얼로그
  void _showEditMemberDialog(BuildContext context, WidgetRef ref, Member member) {
    _showMemberFormDialog(context, ref, existingMember: member);
  }

  /// 신규 회원 직접 등록 다이얼로그
  void _showAddMemberDialog(BuildContext context) {
    _showMemberFormDialog(context, ref);
  }

  /// 날짜 선택 달력 픽커(showDatePicker) 헬퍼 ("YYYY.MM.DD" 포맷 반환)
  Future<String?> _pickFormattedDate(
    BuildContext context, {
    String? currentValue,
    String helpText = '날짜 선택',
  }) async {
    DateTime initial = DateTime.now();
    if (currentValue != null && currentValue.trim().isNotEmpty) {
      final norm = currentValue.trim().replaceAll('.', '-').replaceAll('/', '-');
      final parts = norm.split('-');
      if (parts.length == 3) {
        final y = parts[0].length == 2 ? int.tryParse('20${parts[0]}') : int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          initial = DateTime(y, m, d);
        }
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: helpText,
      cancelText: '취소',
      confirmText: '선택 완료',
    );
    if (picked == null) return null;
    return '${picked.year}.${picked.month.toString().padLeft(2, '0')}.${picked.day.toString().padLeft(2, '0')}';
  }

  /// [+ 직책/등급 직접 추가] 입력 서브 다이얼로그
  Future<String?> _showAddCustomRoleDialog(BuildContext context) async {
    final roleCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.badge_outlined, color: AppTheme.primaryMint, size: 22),
            SizedBox(width: 8),
            Text(
              '직책/등급 직접 추가',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '새로 추가할 회원 등급 또는 직책 명칭을 입력해 주세요.\n입력한 명칭은 선택 목록에 즉시 추가 및 저장됩니다.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roleCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '직책/등급 명칭',
                hintText: '예: 자문위원, 고문, 학생회원 등',
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  Navigator.pop(dialogCtx, val.trim());
                }
              },
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
              backgroundColor: AppTheme.primaryMint,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final text = roleCtrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogCtx, text);
            },
            child: const Text('추가하기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// 신규 회원 등록 및 수정 통합 다이얼로그
  /// - 1. [회원 활동 상태] 설정 (활동 회원 vs 휴면(휴회) 회원 + 휴면 시작일, 복귀 예정일 달력 픽커, 휴면 사유)
  /// - 2. [회원 등급 / 직책] 커스텀 직접 추가 ([+ 직책/등급 직접 추가] 항목 지원)
  /// - 3. [회비 부과 기준 (할인 및 면제)] 정책 필드 ([기본 회비 부과], [차등/할인 금액 지정], [회비 면제: 영구/기간 지정])
  void _showMemberFormDialog(
    BuildContext context,
    WidgetRef ref, {
    Member? existingMember,
  }) {
    final isEdit = existingMember != null;
    final now = DateTime.now();
    final todayFormatted =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

    final nameCtrl = TextEditingController(text: existingMember?.name ?? '');
    final phoneCtrl = TextEditingController(text: existingMember?.phoneNumber ?? '');
    final memoCtrl = TextEditingController(text: existingMember?.memo ?? '');

    Gender selectedGender = existingMember?.gender ?? Gender.male;
    Tier selectedTier = existingMember?.tier ?? Tier.novice;
    MemberRole selectedRole = existingMember?.role ?? MemberRole.member;
    String? customRoleTitle = existingMember?.customRoleTitle;

    // 1. [회원 활동 상태]: 활동 회원(기본값) vs 휴면(휴회) 회원
    MemberStatus selectedStatus = (existingMember?.status == MemberStatus.resting)
        ? MemberStatus.resting
        : MemberStatus.active;
    final restingStartCtrl = TextEditingController(
      text: existingMember?.restingStartDate ?? todayFormatted,
    );
    final restingReturnCtrl = TextEditingController(
      text: existingMember?.restingReturnDate ?? '',
    );
    final restingReasonCtrl = TextEditingController(
      text: existingMember?.restingReason ?? '',
    );

    // 2. [회비 부과 기준 (할인 및 면제)] 정책 필드
    FeePolicyType selectedFeePolicy =
        existingMember?.feePolicy ?? FeePolicyType.standard;
    final discountLabelCtrl = TextEditingController(
      text: existingMember?.customFeeLabel ?? '가족할인',
    );
    final discountAmountCtrl = TextEditingController(
      text: existingMember?.customFeeAmount != null
          ? '${existingMember!.customFeeAmount}'
          : '20000',
    );
    bool isPermanentExempt = existingMember?.isPermanentExempt ?? true;
    final exemptUntilCtrl = TextEditingController(
      text: existingMember?.exemptUntilDate ?? '2026.12.31',
    );

    // 기존 회원이 커스텀 직책을 가지고 있다면 목록에 보장
    if (customRoleTitle != null && customRoleTitle.trim().isNotEmpty) {
      ref.read(customRoleTitlesProvider.notifier).addCustomRoleTitle(customRoleTitle);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final customRoles = ref.watch(customRoleTitlesProvider);
          final String currentRoleKey =
              (customRoleTitle != null && customRoleTitle!.trim().isNotEmpty)
                  ? 'custom:${customRoleTitle!.trim()}'
                  : 'role:${selectedRole.code}';

          // 드롭다운 아이템 구성: 기본 직책 + 커스텀 직책 + 맨 하단 [+ 직책/등급 직접 추가]
          final roleDropdownItems = <DropdownMenuItem<String>>[
            ...MemberRole.values.map(
              (r) => DropdownMenuItem<String>(
                value: 'role:${r.code}',
                child: Text(
                  r.isExecutive ? '${r.label} (운영진)' : r.label,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ...customRoles.map(
              (customTitle) => DropdownMenuItem<String>(
                value: 'custom:$customTitle',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelYellow,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '커스텀',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.pastelYellowDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      customTitle,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            const DropdownMenuItem<String>(
              value: '__ADD_CUSTOM_ROLE__',
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 17, color: AppTheme.pastelMintDark),
                  SizedBox(width: 6),
                  Text(
                    '+ 직책/등급 직접 추가',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.pastelMintDark,
                    ),
                  ),
                ],
              ),
            ),
          ];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.pastelMint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEdit ? Icons.edit_outlined : Icons.person_add_alt_1_rounded,
                    color: AppTheme.pastelMintDark,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEdit ? '${existingMember.name} 정보 수정' : '신규 회원 등록',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 0. 기본 인적 정보 (이름, 성별, 급수)
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '이름 (필수)',
                        hintText: '예: 홍길동',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('성별: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('남성'),
                          selected: selectedGender == Gender.male,
                          onSelected: (_) => setModalState(() => selectedGender = Gender.male),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('여성'),
                          selected: selectedGender == Gender.female,
                          onSelected: (_) => setModalState(() => selectedGender = Gender.female),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Tier>(
                      initialValue: selectedTier,
                      decoration: const InputDecoration(labelText: '급수'),
                      items: Tier.values
                          .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedTier = val);
                      },
                    ),
                    const SizedBox(height: 14),

                    // ==========================================================
                    // 1. [회원 등급 / 직책] 드롭다운 (맨 하단 [+ 직책/등급 직접 추가] 포함)
                    // ==========================================================
                    DropdownButtonFormField<String>(
                      key: ValueKey(currentRoleKey),
                      initialValue: roleDropdownItems.any((item) => item.value == currentRoleKey)
                          ? currentRoleKey
                          : 'role:member',
                      decoration: const InputDecoration(
                        labelText: '회원 등급 / 직책',
                      ),
                      items: roleDropdownItems,
                      onChanged: (val) async {
                        if (val == null) return;
                        if (val == '__ADD_CUSTOM_ROLE__') {
                          final addedTitle = await _showAddCustomRoleDialog(ctx);
                          if (addedTitle != null && addedTitle.trim().isNotEmpty) {
                            ref
                                .read(customRoleTitlesProvider.notifier)
                                .addCustomRoleTitle(addedTitle.trim());
                            setModalState(() {
                              customRoleTitle = addedTitle.trim();
                              selectedRole = MemberRole.member;
                            });
                          } else {
                            setModalState(() {});
                          }
                          return;
                        }
                        if (val.startsWith('custom:')) {
                          setModalState(() {
                            customRoleTitle = val.substring('custom:'.length);
                            selectedRole = MemberRole.member;
                          });
                        } else if (val.startsWith('role:')) {
                          final code = val.substring('role:'.length);
                          setModalState(() {
                            customRoleTitle = null;
                            selectedRole = MemberRole.fromCode(code);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // ==========================================================
                    // 2. [회원 활동 상태] 설정 (활동 회원 vs 휴면(휴회) 회원)
                    // ==========================================================
                    const Text(
                      '회원 활동 상태',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setModalState(() {
                                selectedStatus = MemberStatus.active;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                              decoration: BoxDecoration(
                                color: selectedStatus == MemberStatus.active
                                    ? AppTheme.primaryDark
                                    : AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedStatus == MemberStatus.active
                                      ? AppTheme.primaryDark
                                      : Colors.grey.shade300,
                                  width: selectedStatus == MemberStatus.active ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selectedStatus == MemberStatus.active
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 16,
                                    color: selectedStatus == MemberStatus.active
                                        ? AppTheme.primaryMint
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '활동 회원 (기본값)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: selectedStatus == MemberStatus.active
                                            ? Colors.white
                                            : AppTheme.textDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
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
                              setModalState(() {
                                selectedStatus = MemberStatus.resting;
                                if (restingStartCtrl.text.trim().isEmpty) {
                                  restingStartCtrl.text = todayFormatted;
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                              decoration: BoxDecoration(
                                color: selectedStatus == MemberStatus.resting
                                    ? AppTheme.primaryDark
                                    : AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedStatus == MemberStatus.resting
                                      ? AppTheme.primaryDark
                                      : Colors.grey.shade300,
                                  width: selectedStatus == MemberStatus.resting ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selectedStatus == MemberStatus.resting
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 16,
                                    color: selectedStatus == MemberStatus.resting
                                        ? AppTheme.pastelYellow
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '휴면(휴회) 회원',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: selectedStatus == MemberStatus.resting
                                            ? Colors.white
                                            : AppTheme.textDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // [휴면 회원] 선택 시 노출되는 상세 입력란 (휴면 시작일, 복귀 예정일 달력 픽커, 휴면 사유)
                    if (selectedStatus == MemberStatus.resting) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelYellow.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.pastelYellowDark.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.pause_circle_filled_rounded, size: 16, color: AppTheme.pastelYellowDark),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '휴면(휴회) 기간 및 사유 설정',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.pastelYellowDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '• 휴면 회원은 당일 모임 [출석부 목록]에서 기본 제외됩니다.\n'
                              '• 회비 청구 대상에서 자동으로 \'휴회 면제\' 상태로 연동됩니다.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.textDark,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: restingStartCtrl,
                                    onChanged: (_) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: '휴면 시작일',
                                      hintText: '예: 2026.09.26',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      suffixIcon: IconButton(
                                        tooltip: '휴면 시작일 달력 선택',
                                        icon: const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primaryDark),
                                        onPressed: () async {
                                          final picked = await _pickFormattedDate(
                                            ctx,
                                            currentValue: restingStartCtrl.text,
                                            helpText: '휴면 시작일 선택',
                                          );
                                          if (picked != null) {
                                            setModalState(() {
                                              restingStartCtrl.text = picked;
                                            });
                                          }
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: restingReturnCtrl,
                                    onChanged: (_) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: '복귀 예정일 (선택)',
                                      hintText: '예: 2026.11.30',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      suffixIcon: IconButton(
                                        tooltip: '복귀 예정일 달력 픽커',
                                        icon: const Icon(Icons.event_available_rounded, size: 17, color: AppTheme.pastelMintDark),
                                        onPressed: () async {
                                          final picked = await _pickFormattedDate(
                                            ctx,
                                            currentValue: restingReturnCtrl.text,
                                            helpText: '복귀 예정일 선택',
                                          );
                                          if (picked != null) {
                                            setModalState(() {
                                              restingReturnCtrl.text = picked;
                                            });
                                          }
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: restingReasonCtrl,
                              onChanged: (_) => setModalState(() {}),
                              decoration: InputDecoration(
                                labelText: '휴면 사유',
                                hintText: '예: 엘보 부상, 장기 출장 등',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: ['엘보 부상', '장기 출장', '무릎 재활', '개인 사정'].map((reasonPreset) {
                                final isSelected = restingReasonCtrl.text.trim() == reasonPreset;
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      restingReasonCtrl.text = reasonPreset;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppTheme.primaryDark : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      reasonPreset,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? Colors.white : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ==========================================================
                    // 3. [회비 부과 기준 (할인 및 면제)] 정책 필드
                    // ==========================================================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '회비 부과 기준',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textDark,
                          ),
                        ),
                        if (selectedStatus == MemberStatus.resting)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelPeriwinkle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '휴회 면제 자동 연동됨',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.pastelPeriwinkleDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 옵션 1: [기본 회비 부과] (클럽 기본 월 회비 설정값 자동 연동)
                    _buildFeePolicyOptionTile(
                      title: '기본 회비 부과',
                      subtitle:
                          '기본값 - 클럽 기본 월 회비(${ref.read(currentClubFeePolicyProvider).formattedDefaultFee}) 및 일일회비 연동',
                      icon: Icons.payments_outlined,
                      isSelected: selectedFeePolicy == FeePolicyType.standard,
                      onTap: () => setModalState(() => selectedFeePolicy = FeePolicyType.standard),
                    ),
                    const SizedBox(height: 6),

                    // 옵션 2: [차등/할인 금액 지정]
                    _buildFeePolicyOptionTile(
                      title: '차등/할인 금액 지정',
                      subtitle: '직접 부과할 금액 입력 (예: 가족할인 20,000원)',
                      icon: Icons.discount_outlined,
                      isSelected: selectedFeePolicy == FeePolicyType.discounted,
                      onTap: () => setModalState(() => selectedFeePolicy = FeePolicyType.discounted),
                    ),
                    if (selectedFeePolicy == FeePolicyType.discounted) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelCoral.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.pastelCoralDark.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextField(
                                    controller: discountLabelCtrl,
                                    onChanged: (_) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: '할인 명칭',
                                      hintText: '예: 가족할인',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: TextField(
                                    controller: discountAmountCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (_) => setModalState(() {}),
                                    decoration: InputDecoration(
                                      labelText: '직접 부과할 금액',
                                      hintText: '20000',
                                      suffixText: '원',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: ['가족할인', '부부할인', '학생할인', '청년할인'].map((preset) {
                                final isSelected = discountLabelCtrl.text.trim() == preset;
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      discountLabelCtrl.text = preset;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppTheme.primaryDark : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      preset,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? Colors.white : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),

                    // 옵션 3: [회비 면제] ('영구 면제' 또는 '기간 지정 면제' + 면제 종료일 달력 픽커)
                    _buildFeePolicyOptionTile(
                      title: '회비 면제',
                      subtitle: '\'영구 면제\' 또는 \'기간 지정 면제\' 선택',
                      icon: Icons.verified_outlined,
                      isSelected: selectedFeePolicy == FeePolicyType.exempt,
                      onTap: () => setModalState(() => selectedFeePolicy = FeePolicyType.exempt),
                    ),
                    if (selectedFeePolicy == FeePolicyType.exempt) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelPeriwinkle.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Center(child: Text('영구 면제')),
                                    selected: isPermanentExempt,
                                    onSelected: (_) => setModalState(() => isPermanentExempt = true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Center(child: Text('기간 지정 면제')),
                                    selected: !isPermanentExempt,
                                    onSelected: (_) => setModalState(() => isPermanentExempt = false),
                                  ),
                                ),
                              ],
                            ),
                            if (!isPermanentExempt) ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: exemptUntilCtrl,
                                onChanged: (_) => setModalState(() {}),
                                decoration: InputDecoration(
                                  labelText: '면제 종료일',
                                  hintText: '예: 2026.12.31',
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  suffixIcon: IconButton(
                                    tooltip: '면제 종료일 달력 픽커',
                                    icon: const Icon(
                                      Icons.calendar_month_rounded,
                                      size: 18,
                                      color: AppTheme.pastelPeriwinkleDark,
                                    ),
                                    onPressed: () async {
                                      final picked = await _pickFormattedDate(
                                        ctx,
                                        currentValue: exemptUntilCtrl.text,
                                        helpText: '면제 종료일 선택',
                                      );
                                      if (picked != null) {
                                        setModalState(() {
                                          exemptUntilCtrl.text = picked;
                                        });
                                      }
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // 연락처 & 메모
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: '연락처 (선택)',
                        hintText: '예: 010-1234-5678',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: memoCtrl,
                      decoration: const InputDecoration(
                        labelText: '메모 (선택)',
                        hintText: '예: 오전반 / 가족회원',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEdit ? AppTheme.primaryMint : AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;

                  final normalizedPhone = ClubService.normalizePhoneNumber(phoneCtrl.text.trim());
                  final memoText = memoCtrl.text.trim();

                  final isResting = selectedStatus == MemberStatus.resting;
                  final parsedDiscountAmount = int.tryParse(
                    discountAmountCtrl.text.replaceAll(',', '').trim(),
                  );
                  final discountLabelText = discountLabelCtrl.text.trim().isEmpty
                      ? '가족할인'
                      : discountLabelCtrl.text.trim();

                  // 휴면 회원이거나 회비 면제 정책인 경우 자동으로 면제(FeeStatus.exempt) 연동
                  final FeeStatus resolvedFeeStatus;
                  if (isResting || selectedFeePolicy == FeePolicyType.exempt) {
                    resolvedFeeStatus = FeeStatus.exempt;
                  } else if (existingMember != null) {
                    resolvedFeeStatus = existingMember.feeStatus == FeeStatus.exempt
                        ? FeeStatus.unpaid
                        : existingMember.feeStatus;
                  } else {
                    resolvedFeeStatus = FeeStatus.unpaid;
                  }

                  if (isEdit) {
                    final updated = existingMember.copyWith(
                      name: name,
                      gender: selectedGender,
                      tier: selectedTier,
                      role: selectedRole,
                      customRoleTitle: customRoleTitle,
                      clearCustomRoleTitle: customRoleTitle == null || customRoleTitle!.trim().isEmpty,
                      status: selectedStatus,
                      restingStartDate: isResting ? restingStartCtrl.text.trim() : null,
                      restingReturnDate: isResting && restingReturnCtrl.text.trim().isNotEmpty
                          ? restingReturnCtrl.text.trim()
                          : null,
                      restingReason: isResting && restingReasonCtrl.text.trim().isNotEmpty
                          ? restingReasonCtrl.text.trim()
                          : null,
                      clearRestingFields: !isResting,
                      feePolicy: selectedFeePolicy,
                      customFeeAmount: selectedFeePolicy == FeePolicyType.discounted
                          ? (parsedDiscountAmount ?? 20000)
                          : null,
                      customFeeLabel: selectedFeePolicy == FeePolicyType.discounted
                          ? discountLabelText
                          : null,
                      clearCustomFee: selectedFeePolicy != FeePolicyType.discounted,
                      isPermanentExempt: selectedFeePolicy == FeePolicyType.exempt
                          ? isPermanentExempt
                          : true,
                      exemptUntilDate: selectedFeePolicy == FeePolicyType.exempt && !isPermanentExempt
                          ? exemptUntilCtrl.text.trim()
                          : null,
                      clearExemptUntilDate:
                          selectedFeePolicy != FeePolicyType.exempt || isPermanentExempt,
                      feeStatus: resolvedFeeStatus,
                      phoneNumber: normalizedPhone,
                      memo: memoText,
                      isGuest: false,
                      updatedAt: DateTime.now(),
                    );

                    ref.read(membersProvider.notifier).updateMember(updated);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${updated.name} 회원 정보가 수정되었습니다.')),
                    );
                  } else {
                    final newMember = Member(
                      id: const Uuid().v4(),
                      name: name,
                      gender: selectedGender,
                      tier: selectedTier,
                      role: selectedRole,
                      customRoleTitle: customRoleTitle,
                      status: selectedStatus,
                      restingStartDate: isResting ? restingStartCtrl.text.trim() : null,
                      restingReturnDate: isResting && restingReturnCtrl.text.trim().isNotEmpty
                          ? restingReturnCtrl.text.trim()
                          : null,
                      restingReason: isResting && restingReasonCtrl.text.trim().isNotEmpty
                          ? restingReasonCtrl.text.trim()
                          : null,
                      feePolicy: selectedFeePolicy,
                      customFeeAmount: selectedFeePolicy == FeePolicyType.discounted
                          ? (parsedDiscountAmount ?? 20000)
                          : null,
                      customFeeLabel: selectedFeePolicy == FeePolicyType.discounted
                          ? discountLabelText
                          : null,
                      isPermanentExempt: selectedFeePolicy == FeePolicyType.exempt
                          ? isPermanentExempt
                          : true,
                      exemptUntilDate: selectedFeePolicy == FeePolicyType.exempt && !isPermanentExempt
                          ? exemptUntilCtrl.text.trim()
                          : null,
                      feeStatus: resolvedFeeStatus,
                      phoneNumber: normalizedPhone,
                      memo: memoText.isEmpty ? null : memoText,
                      isGuest: false,
                    );

                    ref.read(membersProvider.notifier).addMember(newMember);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$name 회원이 등록되었습니다.')),
                    );
                  }
                },
                child: Text(isEdit ? '저장하기' : '등록하기'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// [회비 부과 기준] 선택 옵션 타일 빌더
  Widget _buildFeePolicyOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryDark : AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.primaryMint : AppTheme.textDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isSelected ? Colors.white70 : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected ? AppTheme.primaryMint : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  /// [CSV로 회원 대량 등록] 파일 선택 및 표준 템플릿 안내 팝업
  void _showCsvImportDialog(
    BuildContext context,
    Club currentClub,
    List<Member> clubMembers,
  ) {
    final clubService = ref.read(clubServiceProvider);
    final directCsvCtrl = TextEditingController(
      text: clubService.generateStandardTemplateCsvString().trim(),
    );
    bool showDirectInput = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.pastelMint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.upload_file_rounded,
                  color: AppTheme.pastelMintDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CSV로 회원 대량 등록',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      '표준 CSV 규격에 맞춰 회원을 일괄 업로드합니다',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 표준 CSV 템플릿 규격 안내 박스
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.table_chart_outlined, size: 16, color: AppTheme.pastelMintDark),
                            SizedBox(width: 6),
                            Text(
                              'CSV 템플릿 표준 규격',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryMint.withValues(alpha: 0.35)),
                          ),
                          child: const Text(
                            '헤더 컬럼: 이름, 전화번호, 성별, 급수, 회원구분, 메모',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.pastelMintDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• 성별: 남 / 여 (또는 남성 / 여성)\n'
                          '• 급수: A, B, C, D, 초심 (또는 A조, B조 등)\n'
                          '• 회원구분: 운영진(회장/총무 등 직책 포함), 정회원, 준회원 (기본값: 정회원)\n'
                          '• 전화번호: 010-XXXX-XXXX 형식 (하이픈 유무 무관하게 정규화)',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textDark,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // [표준 템플릿 CSV 다운로드] 링크 버튼
                        InkWell(
                          onTap: () => _downloadStandardTemplateCsv(context),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelMint.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.primaryMint),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.file_download_outlined, size: 16, color: AppTheme.pastelMintDark),
                                SizedBox(width: 6),
                                Text(
                                  '표준 템플릿 CSV 다운로드',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.pastelMintDark,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. CSV 파일 선택 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryMint,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text(
                        'CSV 파일 선택하기 (.csv)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      onPressed: () async {
                        try {
                          final picked = await FilePicker.pickFile(
                            type: FileType.custom,
                            allowedExtensions: ['csv', 'txt'],
                          );
                          if (picked == null) return;

                          final Uint8List bytes = await picked.xFile.readAsBytes();
                          final rawCsv = clubService.decodeCsvBytes(bytes);

                          if (rawCsv.trim().isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('선택한 CSV 파일이 비어 있습니다.')),
                              );
                            }
                            return;
                          }

                          final latestClubMembers = ref.read(currentClubMembersProvider);
                          final analysis = clubService.analyzeCsvContent(
                            rawCsv,
                            clubId: currentClub.id,
                            existingClubMembers: latestClubMembers,
                          );

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }
                          if (context.mounted) {
                            _showCsvPreviewDialog(context, analysis, fileName: picked.name);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('CSV 파일 읽기 중 오류가 발생했습니다: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3. CSV 원문 직접 입력 / 붙여넣기 후 미리보기 검증 보조 토글
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          showDirectInput = !showDirectInput;
                        });
                      },
                      icon: Icon(
                        showDirectInput ? Icons.expand_less_rounded : Icons.paste_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      label: Text(
                        showDirectInput ? 'CSV 직접 입력 닫기' : '또는 CSV 텍스트 직접 붙여넣기 / 미리보기 검증',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),

                  if (showDirectInput) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: directCsvCtrl,
                      maxLines: 6,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: '이름,전화번호,성별,급수,회원구분,메모\n홍길동,010-1234-5678,남,A조,운영진(회장),창립멤버',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryDark,
                          side: const BorderSide(color: AppTheme.primaryDark, width: 1.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text(
                          'CSV 파싱 및 미리보기 팝업 열기',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        onPressed: () {
                          final rawCsv = directCsvCtrl.text.trim();
                          if (rawCsv.isEmpty) return;

                          final latestClubMembers = ref.read(currentClubMembersProvider);
                          final analysis = clubService.analyzeCsvContent(
                            rawCsv,
                            clubId: currentClub.id,
                            existingClubMembers: latestClubMembers,
                          );

                          Navigator.pop(dialogCtx);
                          _showCsvPreviewDialog(context, analysis, fileName: '직접입력_회원명단.csv');
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('닫기', style: TextStyle(color: AppTheme.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  /// [표준 템플릿 CSV 다운로드] 동작
  Future<void> _downloadStandardTemplateCsv(BuildContext context) async {
    final clubService = ref.read(clubServiceProvider);
    const fileName = '배드민턴클럽_회원명부_표준템플릿.csv';
    final csvText = clubService.generateStandardTemplateCsvString();
    final bytes = clubService.generateStandardTemplateCsvBytes();

    await _saveOrShareCsvFile(
      context,
      fileName: fileName,
      bytes: bytes,
      csvText: csvText,
      successLabel: '표준 템플릿 CSV($fileName)',
    );
  }

  /// CSV 파싱 후 '미리보기 팝업(총 N명 검출)' 다이얼로그
  /// - 유효한 행과 오류 행(필수값 누락, 잘못된 급수 등) 표시
  /// - 중복 처리 옵션: "기존에 동일한 전화번호가 있을 경우: [기존 정보 덮어쓰기 / 건너뛰기]"
  /// - [등록 완료] 클릭 시 로컬 상태 저장소에 일괄 반영
  void _showCsvPreviewDialog(
    BuildContext context,
    CsvImportAnalysisResult analysis, {
    String? fileName,
  }) {
    CsvDuplicatePolicy duplicatePolicy = CsvDuplicatePolicy.overwrite;
    String filterTab = 'ALL'; // 'ALL' | 'VALID' | 'ERROR'

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (previewCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final displayedRows = switch (filterTab) {
            'VALID' => analysis.validRows,
            'ERROR' => analysis.errorRows,
            _ => analysis.rows,
          };

          final totalCount = analysis.totalDetectedCount;
          final validCount = analysis.validRows.length;
          final errorCount = analysis.errorRows.length;
          final duplicateCount = analysis.duplicateRows.length;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 10),
            contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.pastelMint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.fact_check_rounded,
                    color: AppTheme.pastelMintDark,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '미리보기 팝업 (총 $totalCount명 검출)',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        fileName != null
                            ? '$fileName · 유효 $validCount명 / 오류 $errorCount건'
                            : '유효 $validCount명 / 오류 $errorCount건',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(previewCtx),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 요약 필터 탭 (전체 / 유효한 행 / 오류 행)
                  Row(
                    children: [
                      Expanded(
                        child: _buildPreviewTabChip(
                          label: '전체 ($totalCount)',
                          selected: filterTab == 'ALL',
                          activeColor: AppTheme.primaryDark,
                          onTap: () => setModalState(() => filterTab = 'ALL'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildPreviewTabChip(
                          label: '유효한 행 ($validCount)',
                          selected: filterTab == 'VALID',
                          activeColor: AppTheme.primaryMint,
                          onTap: () => setModalState(() => filterTab = 'VALID'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildPreviewTabChip(
                          label: '오류 행 ($errorCount)',
                          selected: filterTab == 'ERROR',
                          activeColor: Colors.redAccent,
                          onTap: () => setModalState(() => filterTab = 'ERROR'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. 중복 처리 옵션 ("기존에 동일한 전화번호가 있을 경우: [기존 정보 덮어쓰기 / 건너뛰기]")
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelPeriwinkle.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.contact_phone_outlined,
                              size: 15,
                              color: AppTheme.pastelPeriwinkleDark,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '기존에 동일한 전화번호가 있을 경우 ($duplicateCount명 검출):',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setModalState(
                                  () => duplicatePolicy = CsvDuplicatePolicy.overwrite,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: duplicatePolicy == CsvDuplicatePolicy.overwrite
                                        ? AppTheme.primaryMint
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: duplicatePolicy == CsvDuplicatePolicy.overwrite
                                          ? AppTheme.primaryMint
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        duplicatePolicy == CsvDuplicatePolicy.overwrite
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_off_rounded,
                                        size: 15,
                                        color: duplicatePolicy == CsvDuplicatePolicy.overwrite
                                            ? Colors.white
                                            : AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '기존 정보 덮어쓰기',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: duplicatePolicy == CsvDuplicatePolicy.overwrite
                                              ? Colors.white
                                              : AppTheme.textDark,
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
                                onTap: () => setModalState(
                                  () => duplicatePolicy = CsvDuplicatePolicy.skip,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: duplicatePolicy == CsvDuplicatePolicy.skip
                                        ? AppTheme.primaryDark
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: duplicatePolicy == CsvDuplicatePolicy.skip
                                          ? AppTheme.primaryDark
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        duplicatePolicy == CsvDuplicatePolicy.skip
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_off_rounded,
                                        size: 15,
                                        color: duplicatePolicy == CsvDuplicatePolicy.skip
                                            ? Colors.white
                                            : AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '건너뛰기',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: duplicatePolicy == CsvDuplicatePolicy.skip
                                              ? Colors.white
                                              : AppTheme.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. 검출된 행 리스트
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.36,
                      ),
                      child: displayedRows.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Center(
                                child: Text(
                                  '해당 조건의 행이 없습니다.',
                                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: displayedRows.length,
                              itemBuilder: (ctx, idx) {
                                final row = displayedRows[idx];
                                return _buildCsvPreviewRowItem(row, duplicatePolicy);
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(previewCtx),
                child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryMint,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text(
                  '등록 완료',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                onPressed: validCount == 0
                    ? null
                    : () {
                        final result = ref.read(membersProvider.notifier).importCsvRows(
                              analysisResult: analysis,
                              duplicatePolicy: duplicatePolicy,
                            );
                        Navigator.pop(previewCtx);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.primaryDark,
                            content: Text(
                              'CSV 일괄 등록 완료: 신규 ${result.addedCount}명 추가, '
                              '기존 ${result.updatedCount}명 덮어쓰기 '
                              '(건너뛰기 ${result.skippedCount}명, 오류 제외 $errorCount건)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreviewTabChip({
    required String label,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeColor : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppTheme.textDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCsvPreviewRowItem(
    CsvParsedRow row,
    CsvDuplicatePolicy duplicatePolicy,
  ) {
    if (!row.isValid) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  '${row.rowNumber}행 · 오류 행 (등록 제외)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.red,
                  ),
                ),
                const Spacer(),
                Text(
                  row.rawName.isNotEmpty ? row.rawName : '(이름 누락)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '원본값: 이름="${row.rawName}", 전화번호="${row.rawPhone}", 성별="${row.rawGender}", 급수="${row.rawTier}", 구분="${row.rawMemberType}"',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 4),
            ...row.errors.map(
              (err) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $err',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final member = row.member!;
    final isDup = row.isDuplicatePhone;
    final dupActionText = duplicatePolicy == CsvDuplicatePolicy.overwrite
        ? '덮어쓰기 예정'
        : '건너뛰기 예정';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDup
            ? AppTheme.pastelCoral.withValues(alpha: 0.25)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDup ? AppTheme.pastelCoralDark.withValues(alpha: 0.4) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 15, color: AppTheme.primaryMint),
              const SizedBox(width: 6),
              Text(
                '${row.rowNumber}행 · ${member.name}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppTheme.getTierBgColor(member.tier),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${member.gender.label} · ${member.tier.label}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTierTextColor(member.tier),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppTheme.pastelMint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  member.isExecutive ? '운영진(${member.role.label})' : member.role.label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.pastelMintDark,
                  ),
                ),
              ),
              const Spacer(),
              if (isDup)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelCoral,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '중복 ($dupActionText)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.pastelCoralDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                member.phoneNumber ?? '전화번호 미입력',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.pastelMintDark,
                ),
              ),
              if (member.memo != null && member.memo!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '메모: ${member.memo}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// [회원명부 CSV 다운로드] 백업 내보내기 팝업
  /// - 파일명 형식: "메가배드민턴_회원명부_YYYYMMDD.csv"
  /// - 한글 깨짐 방지를 위해 UTF-8 BOM 인코딩 적용
  void _showCsvExportDialog(
    BuildContext context,
    Club currentClub,
    List<Member> clubMembers,
  ) {
    final clubService = ref.read(clubServiceProvider);
    final fileName = clubService.buildExportFileName(currentClub.clubName);
    final csvText = clubService.exportMembersToCsvString(clubMembers);
    final csvBytes = clubService.exportMembersToCsvBytes(clubMembers);

    final previewLines = csvText.trim().split('\n').take(6).join('\n');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.pastelPeriwinkle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: AppTheme.pastelPeriwinkleDark,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '회원명부 CSV 다운로드',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                  Text(
                    '표준 규격 CSV 파일로 저장하거나 외부로 공유합니다',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 16, color: AppTheme.pastelMintDark),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              fileName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• 대상 인원: 총 ${clubMembers.length}명 (${currentClub.clubName})\n'
                        '• 헤더 규격: ${ClubService.standardCsvHeaders.join(', ')}\n'
                        '• 인코딩: UTF-8 BOM 적용 (엑셀 한글 깨짐 방지)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '생성된 CSV 미리보기 (상위 행)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    previewLines,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppTheme.textDark,
                      height: 1.4,
                    ),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.save_alt_rounded, size: 18),
                        label: const Text(
                          '기기 저장소에 저장',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        onPressed: () async {
                          Navigator.pop(dialogCtx);
                          await _saveOrShareCsvFile(
                            context,
                            fileName: fileName,
                            bytes: csvBytes,
                            csvText: csvText,
                            successLabel: fileName,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryDark,
                          side: const BorderSide(color: AppTheme.primaryDark, width: 1.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.share_rounded, size: 17),
                        label: const Text(
                          '공유 시트 (Share)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        onPressed: () async {
                          Navigator.pop(dialogCtx);
                          await _shareCsvFile(
                            context,
                            fileName: fileName,
                            bytes: csvBytes,
                            csvText: csvText,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
  }

  /// 기기 저장소에 CSV 파일(UTF-8 BOM) 저장 또는 폴백 공유/복사
  Future<void> _saveOrShareCsvFile(
    BuildContext context, {
    required String fileName,
    required Uint8List bytes,
    required String csvText,
    required String successLabel,
  }) async {
    await Clipboard.setData(ClipboardData(text: csvText));

    try {
      final savedUri = await FilePicker.saveFile(
        dialogTitle: '$fileName 저장',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );

      if (savedUri != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.primaryDark,
              content: Text('$successLabel 파일이 저장되었습니다. (UTF-8 BOM 적용)'),
            ),
          );
        }
        return;
      }
    } catch (_) {
      // 플랫폼에 따라 saveFile 미지원 시 공유 시트로 폴백
    }

    if (!context.mounted) return;
    await _shareCsvFile(
      context,
      fileName: fileName,
      bytes: bytes,
      csvText: csvText,
    );
  }

  /// 공유(Share) 시트 호출로 CSV 파일(UTF-8 BOM) 내보내기
  Future<void> _shareCsvFile(
    BuildContext context, {
    required String fileName,
    required Uint8List bytes,
    required String csvText,
  }) async {
    await Clipboard.setData(ClipboardData(text: csvText));

    try {
      final xFile = XFile.fromData(
        bytes,
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
    } catch (_) {
      // 데스크톱/테스트 환경 등에서 공유 시트가 닫히거나 미지원일 경우 클립보드 백업 보장
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primaryDark,
          content: Text('$fileName 내보내기 완료 (UTF-8 BOM 인코딩 및 클립보드 복사됨)'),
        ),
      );
    }
  }

  /// 텍스트 복사/붙여넣기 대량 등록 다이얼로그
  void _showBatchAddDialog(BuildContext context) {
    final batchCtrl = TextEditingController(
      text: '''김영수 남 A 정회원
이정민 여 B조 010-2345-6789 총무
박현우 남 C 준회원
최유나 여 초심''',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.playlist_add_check_rounded, color: AppTheme.primaryMint),
            SizedBox(width: 8),
            Text('명단 텍스트 대량 등록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '카카오톡 단체방이나 엑셀에서 복사한 명단을 아래에 붙여넣으세요.\n줄마다 "이름 성별 급수 [전화번호] [정회원/준회원/직책]" 형식으로 자동 인식됩니다.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: batchCtrl,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: '예:\n홍길동 남 A 정회원\n김민수 여 B 총무\n이초심 남 초심 준회원',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final text = batchCtrl.text.trim();
              if (text.isEmpty) return;

              final clubService = ref.read(clubServiceProvider);
              final parsed = clubService.parseBatchMembersText(text);

              if (parsed.isNotEmpty) {
                ref.read(membersProvider.notifier).addBatch(parsed);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${parsed.length}명의 회원이 일괄 등록되었습니다!')),
                );
              }
            },
            child: const Text('일괄 파싱 & 등록'),
          ),
        ],
      ),
    );
  }

  /// 클럽/모임 전환 바텀시트
  void _showClubSwitchBottomSheet(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final currentClubId = ref.watch(currentClubIdProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.80,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: AppTheme.primaryMint, size: 24),
                SizedBox(width: 8),
                Text(
                  '배드민턴 클럽 / 모임 전환',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '관리할 모임을 선택하면 회원명부, 오늘 모임 출석부, 대진표가 즉시 전환됩니다.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const Divider(height: 24),

            // 클럽 목록
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: clubs.length,
                itemBuilder: (ctx, index) {
                  final club = clubs[index];
                  final isSelected = club.id == currentClubId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.pastelMint.withValues(alpha: 0.25) : AppTheme.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryMint : Colors.grey.shade300,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryMint : AppTheme.pastelPeriwinkle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            club.clubName.isNotEmpty ? club.clubName.characters.first : '콕',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isSelected ? Colors.white : AppTheme.pastelPeriwinkleDark,
                            ),
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              club.clubName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? AppTheme.textDark : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryMint,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '선택됨',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        club.description ?? '회원 ${club.memberCount}명',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                        size: isSelected ? 22 : 14,
                        color: isSelected ? AppTheme.primaryMint : Colors.grey.shade400,
                      ),
                      onTap: () {
                        ref.read(currentClubIdProvider.notifier).switchClub(club.id);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.primaryDark,
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppTheme.primaryMint, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '[${club.clubName}] 모임으로 전환되었습니다.',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // [+ 새 클럽/모임 생성] 버튼
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.pastelMintDark,
                  side: const BorderSide(color: AppTheme.primaryMint, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text(
                  '+ 새 클럽/모임 생성',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreateClubDialog(context, ref);
                },
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// 신규 클럽/모임 생성 다이얼로그
  void _showCreateClubDialog(BuildContext context, WidgetRef ref) {
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
            Text('새 클럽 / 모임 생성', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '독립된 회원 명부와 대진표를 관리할 새 모임을 만듭니다.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: '클럽 / 모임 이름 (필수)',
                hintText: '예: 서초 번개콕, 일요 모닝배턴',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: '모임 일정 / 설명 (선택)',
                hintText: '예: 매주 일요일 08시 · 3코트',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMint,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final desc = descCtrl.text.trim();
              final newClub = ref.read(clubsProvider.notifier).createClub(
                    name,
                    description: desc.isNotEmpty ? desc : null,
                  );

              // 생성된 클럽으로 즉시 자동 전환!
              ref.read(currentClubIdProvider.notifier).switchClub(newClub.id);

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.primaryDark,
                  content: Text('[${newClub.clubName}] 새 모임이 생성되어 활성화되었습니다!'),
                ),
              );
            },
            child: const Text('생성 및 전환'),
          ),
        ],
      ),
    );
  }

  /// 회원에게 바로 전화 걸기 (tel:)
  Future<void> _callMember(BuildContext context, WidgetRef ref, Member member) async {
    final rawPhone = member.phoneNumber?.trim();
    if (rawPhone == null || rawPhone.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.phone_missed_rounded, color: AppTheme.pastelCoralDark, size: 20),
              SizedBox(width: 8),
              Text('전화번호 미등록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            '\'${member.name}\' 회원의 연락처가 등록되어 있지 않습니다.\n지금 전화번호를 등록하시겠습니까?',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryMint,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showEditMemberDialog(context, ref, member);
              },
              child: const Text('번호 등록'),
            ),
          ],
        ),
      );
      return;
    }

    final cleanPhone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');

    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // 데스크톱 브라우저 등에서 전화 앱이 바로 열리지 않을 때 클립보드 복사 안내
      await Clipboard.setData(ClipboardData(text: cleanPhone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text('\'${member.name}\' 전화번호($cleanPhone)가 클립보드에 복사되었습니다.'),
          ),
        );
      }
    }
  }

  /// [단체 문자 발송] 모달 바텀시트
  void _showGroupSmsDialog(BuildContext context, List<Member> clubMembers) {
    final membersWithPhone = clubMembers
        .where((m) => m.phoneNumber != null && m.phoneNumber!.trim().isNotEmpty)
        .toList();

    // 초기 선택: 전화번호 등록 회원 전체 선택
    final Set<String> selectedIds = membersWithPhone.map((m) => m.id).toSet();
    final messageCtrl = TextEditingController(
      text: '🏸 [정기 모임 안내] 오늘 배드민턴 모임이 있습니다. 늦지 않게 참석 부탁드립니다!',
    );

    final templates = [
      '🏸 [정기 모임 안내] 오늘 배드민턴 모임이 있습니다. 늦지 않게 참석 부탁드립니다!',
      '📢 [일정 공지] 이번 주 정기 모임 일정 안내드립니다. 참석 여부를 회신해 주세요.',
      '💰 [회비 안내] 이번 달 정기 회비(콕비) 입금 확인 부탁드립니다. 감사합니다!',
      '⚡ [번개 모임] 오늘 번개 모임 참석 가능하신 분은 연락주세요!',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final selectedCount = selectedIds.length;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.pastelMint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.sms_rounded, color: AppTheme.pastelMintDark, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '단체 문자 발송',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            '선택한 회원들에게 문자 앱(SMS)으로 일괄 전송합니다',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    children: [
                      // 1. 발송 템플릿 칩
                      const Text(
                        '추천 문자 템플릿',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: templates.map((tpl) {
                          return ActionChip(
                            label: Text(
                              '${tpl.split(']')[0]}]',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: AppTheme.background,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            onPressed: () {
                              setModalState(() {
                                messageCtrl.text = tpl;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // 2. 메시지 내용 입력 필드
                      const Text(
                        '문자 메시지 본문',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: messageCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: '전송할 메시지 내용을 입력하세요.',
                          filled: true,
                          fillColor: AppTheme.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. 수신 대상 회원 선택 바
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text(
                                '수신 대상 회원',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.pastelMint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$selectedCount / ${membersWithPhone.length}명',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.pastelMintDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                if (selectedIds.length == membersWithPhone.length) {
                                  selectedIds.clear();
                                } else {
                                  selectedIds.addAll(membersWithPhone.map((m) => m.id));
                                }
                              });
                            },
                            child: Text(
                              selectedIds.length == membersWithPhone.length ? '전체 해제' : '전체 선택',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // 회원 목록
                      if (membersWithPhone.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text(
                              '전화번호가 등록된 회원이 없습니다.\n회원 정보에서 전화번호를 먼저 등록해 주세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ),
                        )
                      else
                        ...membersWithPhone.map((member) {
                          final isChecked = selectedIds.contains(member.id);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isChecked ? AppTheme.pastelMint.withValues(alpha: 0.15) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isChecked ? AppTheme.primaryMint : Colors.grey.shade200,
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              onTap: () {
                                setModalState(() {
                                  if (isChecked) {
                                    selectedIds.remove(member.id);
                                  } else {
                                    selectedIds.add(member.id);
                                  }
                                });
                              },
                              leading: Checkbox(
                                value: isChecked,
                                activeColor: AppTheme.primaryMint,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (_) {
                                  setModalState(() {
                                    if (isChecked) {
                                      selectedIds.remove(member.id);
                                    } else {
                                      selectedIds.add(member.id);
                                    }
                                  });
                                },
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    member.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isChecked ? FontWeight.w900 : FontWeight.bold,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getTierBgColor(member.tier),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      member.tier.label,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.getTierTextColor(member.tier),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: InkWell(
                                onTap: () => _callMember(context, ref, member),
                                child: Text(
                                  member.phoneNumber ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.pastelMintDark,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                // 하단 발송 액션 버튼
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryMint,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        '문자 앱 열기 ($selectedCount명 대상) ✉️',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      onPressed: selectedCount == 0
                          ? null
                          : () async {
                              final text = messageCtrl.text.trim();
                              final phoneNumbers = membersWithPhone
                                  .where((m) => selectedIds.contains(m.id))
                                  .map((m) => m.phoneNumber!.replaceAll(RegExp(r'[^0-9+]'), ''))
                                  .toList();

                              // 클립보드에 문자 메시지 복사 (모바일/PC 공통 편의성 보장)
                              await Clipboard.setData(ClipboardData(text: text));

                              // 문자 앱 열기 (sms:01012345678,01098765432?body=...)
                              final separator = ','; // Android/iOS 다중 번호 표준 구분자
                              final uri = Uri(
                                scheme: 'sms',
                                path: phoneNumbers.join(separator),
                                queryParameters: text.isNotEmpty ? {'body': text} : null,
                              );

                              try {
                                final launched = await launchUrl(uri);
                                if (!launched) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              } catch (e) {
                                // 문자 앱 미설치 환경 대비 fallback
                              }

                              if (context.mounted) {
                                Navigator.pop(sheetCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppTheme.primaryDark,
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded, color: AppTheme.primaryMint, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '총 ${phoneNumbers.length}명 대상 문자 앱이 실행되었습니다.\n(클립보드에 메시지가 복사되었습니다)',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
