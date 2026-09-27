import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// [화면 2 / 탭 2] 오늘 모임 준비 & 출석 체크 (출석부 화면)
/// - 모임 기본 정보 설정 (타이틀 수정, 참가비/콕비 설정, 실시간 총 수납 현황 Bento Grid)
/// - 회비 정산 영역 [미납자 안내 문자 발송] 및 참석자 개별/선택 문자(sms:) 발송
/// - 이름 아래 전화번호(010-XXXX-XXXX) 텍스트 클릭 시 즉시 전화 걸기(tel:) 실행
/// - 모임 데이터 보존 및 아카이빙(히스토리): [진행 모임]과 [지난 모임]을 구분하여 출석부, 회비 정산 내역, 경기 전적 언제든 재조회
/// - 데이터 삭제 안전장치: 상세 메뉴에서 [모임 기록 영구 삭제] 선택 및 확인 팝업을 거칠 때만 영구 삭제
class SessionAttendanceScreen extends ConsumerStatefulWidget {
  const SessionAttendanceScreen({super.key});

  @override
  ConsumerState<SessionAttendanceScreen> createState() => _SessionAttendanceScreenState();
}

class _SessionAttendanceScreenState extends ConsumerState<SessionAttendanceScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // [상단 1단] 인적 속성 드롭다운 필터 (회원명부와 동일 규격: 급수 / 회원 구분 / 성별)
  Tier? _selectedTier;
  MemberGrade? _selectedGrade;
  Gender? _selectedGender;

  // [상단 2단] 당일 출석(출전 상태) 및 회비 상태 필터 (AND 복합 필터링 지원)
  AttendanceStatus? _selectedAttendanceStatus; // null: 전체, active: 출전, resting: 휴식, withdrawn: 조퇴
  FeeStatus? _selectedFeeStatus; // null: 전체, unpaid: 미납자만, paid: 완납, exempt: 면제
  // 출석부 정렬 기준 (기본값: 급수순 상위 급수 우선 A -> 초심)
  AttendanceSortBy _selectedSortBy = AttendanceSortBy.tierDesc;

  // 롱프레스 다중 선택 문자 발송 모드 상태
  bool _isMultiSelectMode = false;
  final Set<String> _selectedAttendeeIds = {};

  void _toggleMultiSelectMember(String memberId) {
    setState(() {
      if (_selectedAttendeeIds.contains(memberId)) {
        _selectedAttendeeIds.remove(memberId);
        if (_selectedAttendeeIds.isEmpty) {
          _isMultiSelectMode = false;
        }
      } else {
        _selectedAttendeeIds.add(memberId);
        _isMultiSelectMode = true;
      }
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedAttendeeIds.clear();
    });
  }

  bool get _hasActiveFilters =>
      _selectedTier != null ||
      _selectedGrade != null ||
      _selectedGender != null ||
      _selectedAttendanceStatus != null ||
      _selectedFeeStatus != null;

  void _resetAllFilters() {
    setState(() {
      _selectedTier = null;
      _selectedGrade = null;
      _selectedGender = null;
      _selectedAttendanceStatus = null;
      _selectedFeeStatus = null;
    });
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 전화번호 텍스트 클릭 시 즉시 전화 걸기 (tel:)
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
    final telUri = Uri(scheme: 'tel', path: cleanPhone);

    try {
      final launched = await launchUrl(telUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: rawPhone));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('전화 앱을 열 수 없어 ${member.name} 님의 번호($rawPhone)를 복사했습니다.')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: rawPhone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.name} 님의 전화번호($rawPhone)가 복사되었습니다. (tel:$cleanPhone)')),
        );
      }
    }
  }

  /// 개별 회원에게 문자 보내기 (sms:)
  Future<void> _sendIndividualSms(BuildContext context, Member member, {String? defaultBody}) async {
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
    final query = (defaultBody != null && defaultBody.isNotEmpty)
        ? 'body=${Uri.encodeComponent(defaultBody)}'
        : '';
    final smsUri = Uri.parse('sms:$cleanPhone${query.isNotEmpty ? "?$query" : ""}');

    try {
      final launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: rawPhone));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${member.name} 님 번호($rawPhone)로 문자 앱 연결을 요청했습니다.')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: rawPhone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.name} 님의 번호($rawPhone)를 클립보드에 복사했습니다. (sms:$cleanPhone)')),
        );
      }
    }
  }

  /// [미납자 안내 문자 발송] 현재 회비 상태가 '미납'인 참석자들의 번호를 수신자로 묶어 기본 입금 안내 문구와 함께 문자 앱(sms:) 실행
  Future<void> _sendUnpaidGuideSms(
    BuildContext context,
    GameSession session,
    List<Member> attendeeMembers,
  ) async {
    final unpaidMembers = attendeeMembers
        .where((m) => session.getAttendeeFeeStatus(m) == FeeStatus.unpaid)
        .toList();

    if (unpaidMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.primaryDark,
          content: Text('현재 미납 상태인 참석자가 없습니다.'),
        ),
      );
      return;
    }

    final phones = unpaidMembers
        .map((m) => (m.phoneNumber ?? '').replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty)
        .toList();

    final guideMessage =
        '[클릭콕 회비 안내] 안녕하세요! \'${session.displayTitle}\' 모임 회비(회원 ${_formatWon(session.memberFee)}원 / 게스트 ${_formatWon(session.guestFee)}원) 미납 안내드립니다. 확인 후 입금 부탁드립니다. 감사합니다!';

    if (phones.isEmpty) {
      await Clipboard.setData(ClipboardData(text: guideMessage));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.pastelRoseDark,
            content: Text('미납자(${unpaidMembers.length}명)의 등록된 전화번호가 없어 안내 문구를 복사했습니다.'),
          ),
        );
      }
      return;
    }

    final recipients = phones.join(',');
    final smsUri = Uri.parse('sms:$recipients?body=${Uri.encodeComponent(guideMessage)}');

    try {
      final launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text(
              launched
                  ? '미납자 ${unpaidMembers.length}명(${unpaidMembers.map((m) => m.name).join(", ")})에게 입금 안내 문자 앱을 열었습니다.'
                  : '미납자 ${unpaidMembers.length}명 수신 번호 및 입금 안내 문구를 준비했습니다.',
            ),
          ),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: '$recipients\n$guideMessage'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text('미납자 ${unpaidMembers.length}명 번호와 입금 안내 문구가 클립보드에 복사되었습니다.'),
          ),
        );
      }
    }
  }

  /// 다중 선택된 회원(N명)에게 일괄 SMS 발송 (sms:)
  Future<void> _sendBulkSmsToSelectedAttendees(
    BuildContext context,
    GameSession session,
    List<Member> attendeeMembers,
  ) async {
    final targetMembers = attendeeMembers
        .where((m) => _selectedAttendeeIds.contains(m.id))
        .toList();
    if (targetMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문자를 발송할 회원을 1명 이상 선택해 주세요.')),
      );
      return;
    }

    final phones = targetMembers
        .map((m) => (m.phoneNumber ?? '').replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty)
        .toList();
    final defaultMsg = '[콕매치 공지] 안녕하세요! \'${session.displayTitle}\' 모임 관련 안내드립니다.';

    if (phones.isEmpty) {
      await Clipboard.setData(ClipboardData(text: defaultMsg));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.pastelRoseDark,
            content: Text('선택한 회원(${targetMembers.length}명)의 등록된 전화번호가 없어 안내 문구를 복사했습니다.'),
          ),
        );
      }
      return;
    }

    final recipients = phones.join(',');
    final smsUri = Uri.parse('sms:$recipients?body=${Uri.encodeComponent(defaultMsg)}');

    try {
      final launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text(
              launched
                  ? '선택한 회원(${targetMembers.length}명)에게 단체 문자 앱을 열었습니다. (sms:)'
                  : '선택한 회원(${targetMembers.length}명) 수신 번호($recipients)로 문자 연결을 준비했습니다. (sms:)',
            ),
          ),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: '$recipients\n$defaultMsg'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primaryDark,
            content: Text('선택한 회원(${targetMembers.length}명) 번호가 클립보드에 복사되었습니다. (sms:$recipients)'),
          ),
        );
      }
    }

    _exitMultiSelectMode();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final allMembers = ref.watch(membersProvider);
    final currentClub = ref.watch(currentClubProvider);
    final ongoingSessions = ref.watch(currentClubOngoingSessionsProvider);
    final archivedSessions = ref.watch(currentClubArchivedSessionsProvider);

    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0 ||
        View.of(context).viewInsets.bottom > 0 ||
        _searchFocusNode.hasFocus;

    if (session == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              // 상단 헤더
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 20, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => AppTheme.openDrawer(context),
                        tooltip: '메뉴 열기',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.menu_rounded, color: AppTheme.textDark, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.pastelMint,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.edit_calendar_rounded, color: AppTheme.pastelMintDark, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.pastelMint,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    currentClub.clubName,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.pastelMintDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              '오늘 모임 & 출석부',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 새 모임 시작하기 배너 카드
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: AppTheme.pastelMint,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.sports_tennis_rounded,
                          size: 36,
                          color: AppTheme.primaryMint,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        ongoingSessions.isEmpty
                            ? '진행 중인 모임 세션이 없습니다'
                            : '진행 중인 모임 ${ongoingSessions.length}건이 있습니다',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '관리 중인 클럽을 선택하고 오늘 참석할 정회원을 출석부에 등록하여 활기찬 모임을 시작해 보세요.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textMuted,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryMint,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                          label: const Text(
                            '+ 새 모임 시작하기',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          onPressed: () => _showStartGatheringModal(context, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // [진행 모임] & [지난 모임] 아카이브 히스토리 섹션
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: _buildSessionArchiveSections(
                    context: context,
                    allMembers: allMembers,
                    ongoingSessions: ongoingSessions,
                    archivedSessions: archivedSessions,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 출석부에 등록된 회원 객체 매핑
    final attendeeMembers = session.attendees.map((id) {
      return allMembers.firstWhere(
        (m) => m.id == id,
        orElse: () => Member(id: id, name: '미등록 회원', tier: Tier.novice),
      );
    }).toList();

    // 검색 + [1단] 인적 속성 드롭다운(급수·회원 구분·성별) + [2단] 출전/회비 상태 복합(AND) 필터링 후 정렬 반영
    final query = _searchController.text.trim();
    final filteredAttendeeMembers = attendeeMembers.where((m) {
      // 1. 검색어 필터 (이름 또는 초성)
      if (query.isNotEmpty && !m.matchesSearch(query)) {
        return false;
      }

      // 2. [상단 1단] 인적 속성 드롭다운 필터 (급수 / 회원 구분 / 성별)
      if (_selectedTier != null && m.tier != _selectedTier) {
        return false;
      }
      if (_selectedGrade != null && m.grade != _selectedGrade) {
        return false;
      }
      if (_selectedGender != null && m.gender != _selectedGender) {
        return false;
      }

      // 3. [상단 2단] 당일 출전 상태 필터 (전체 / 출전 / 휴식 / 조퇴)
      final status = session.getAttendeeStatus(m.id);
      if (_selectedAttendanceStatus != null && status != _selectedAttendanceStatus) {
        return false;
      }

      // 4. [상단 2단] 회비 상태 필터 (미납자만 / 완납 / 면제)
      final feeStatus = session.getAttendeeFeeStatus(m);
      if (_selectedFeeStatus != null && feeStatus != _selectedFeeStatus) {
        return false;
      }

      return true;
    }).toList();

    final displayedMembers = ref.read(clubServiceProvider).sortAttendanceMembers(
          filteredAttendeeMembers,
          session,
          sortBy: _selectedSortBy,
        );

    // 수납 현황 계산 (면제자는 미납자에서 제외되며 별도 집계)
    final totalExpectedFee = session.calculateTotalFee(allMembers);
    final totalPaidFee = session.calculatePaidFee(allMembers);
    final paidCount = session.calculatePaidCount(allMembers);
    final unpaidCount = session.calculateUnpaidCount(allMembers);
    final exemptCount = session.calculateExemptCount(allMembers);
    final activeCount = session.activeAttendeeCount;
    final restingCount = session.restingAttendees.length;
    final withdrawnCount = session.withdrawnAttendees.length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // 1. 상단 모임 헤더 & 기본 정보 바
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: _buildSessionHeader(context, session, currentClub),
                  ),
                ),

                // 2. 슬림 요약 바: 당일 출석 인원 및 회비 수납 현황 카드 ([미납자 안내 문자 발송] 버튼 포함)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildBentoSummaryGrid(
                      context,
                      session: session,
                      attendeeMembers: attendeeMembers,
                      attendeeCount: attendeeMembers.length,
                      activeCount: activeCount,
                      restingCount: restingCount,
                      withdrawnCount: withdrawnCount,
                      totalExpectedFee: totalExpectedFee,
                      totalPaidFee: totalPaidFee,
                      paidCount: paidCount,
                      unpaidCount: unpaidCount,
                      exemptCount: exemptCount,
                    ),
                  ),
                ),

                // 3. 참석자 등록 빠른 액션 바 ([회원 불러오기], [게스트 즉시 추가])
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: _buildQuickActionRow(context, ref, allMembers, attendeeMembers, session),
                  ),
                ),

                // 4. 참석자 명단 내 검색창 + [1단] 인적 속성 드롭다운 필터 + [2단] 출전/회비 상태 필터 칩
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSearchAndFilterBar(
                      attendeeCount: attendeeMembers.length,
                      activeCount: activeCount,
                      restingCount: restingCount,
                      withdrawnCount: withdrawnCount,
                      paidCount: paidCount,
                      unpaidCount: unpaidCount,
                      exemptCount: exemptCount,
                      filteredCount: displayedMembers.length,
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 10)),

                // 5. 참석자 카드 리스트
                if (displayedMembers.isEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            attendeeMembers.isEmpty
                                ? '오늘 모임에 등록된 참석자가 없습니다.'
                                : '해당 조건과 일치하는 참석자가 없습니다.',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            attendeeMembers.isEmpty
                                ? '위 [+ 회원 불러오기] 또는 [+ 게스트 추가]를 눌러 출석부를 시작하세요.'
                                : '검색어를 지우거나 필터를 [전체]로 변경해 보세요.',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      isKeyboardOpen ? 16 : (_isMultiSelectMode ? 140 : 84),
                    ), // 하단 플로팅 바 여백
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final member = displayedMembers[index];
                          final status = session.getAttendeeStatus(member.id);
                          return _buildAttendeeCard(
                            context: context,
                            ref: ref,
                            index: index + 1,
                            member: member,
                            session: session,
                            status: status,
                          );
                        },
                        childCount: displayedMembers.length,
                      ),
                    ),
                  ),
              ],
            ),

            // 6. 하단 플로팅 액션 바 (가상 키보드 활성화 시 자동 숨김 처리)
            if (!isKeyboardOpen)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isMultiSelectMode) ...[
                      _buildMultiSelectSmsBar(
                        context: context,
                        session: session,
                        attendeeMembers: attendeeMembers,
                        displayedMembers: displayedMembers,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildBottomConfirmBar(
                      context: context,
                      ref: ref,
                      session: session,
                      activeCount: activeCount,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 모임 목록 화면: [진행 모임]과 [지난 모임] 구분 리스트
  Widget _buildSessionArchiveSections({
    required BuildContext context,
    required List<Member> allMembers,
    required List<GameSession> ongoingSessions,
    required List<GameSession> archivedSessions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) [진행 모임] 섹션
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.pastelMint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '[진행 모임]',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.pastelMintDark),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${ongoingSessions.length}건',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (ongoingSessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text(
              '현재 진행 중인 모임이 없습니다. 상단 [+ 새 모임 시작하기]를 눌러 모임을 생성하세요.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          )
        else
          ...ongoingSessions.map(
            (s) => _buildSessionHistoryItemCard(
              context: context,
              sessionItem: s,
              allMembers: allMembers,
              isArchived: false,
            ),
          ),

        const SizedBox(height: 22),

        // 2) [지난 모임] 섹션 (종료/완료 후 자동 보존된 아카이브)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.pastelPeriwinkle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '[지난 모임]',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.pastelPeriwinkleDark),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${archivedSessions.length}건 보관 중',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
            ),
            const Spacer(),
            const Text(
              '자동 삭제 없음 · 영구 보관',
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (archivedSessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text(
              '아직 보관된 지난 모임 기록이 없습니다. 모임 종료 시 자동 삭제되지 않고 이곳에 안전하게 보관됩니다.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          )
        else
          ...archivedSessions.map(
            (s) => _buildSessionHistoryItemCard(
              context: context,
              sessionItem: s,
              allMembers: allMembers,
              isArchived: true,
            ),
          ),
      ],
    );
  }

  /// 모임 목록 카드 ([진행 모임] / [지난 모임] 공용)
  Widget _buildSessionHistoryItemCard({
    required BuildContext context,
    required GameSession sessionItem,
    required List<Member> allMembers,
    required bool isArchived,
  }) {
    final paidFee = sessionItem.calculatePaidFee(allMembers);
    final totalFee = sessionItem.calculateTotalFee(allMembers);
    final paidCnt = sessionItem.calculatePaidCount(allMembers);
    final unpaidCnt = sessionItem.calculateUnpaidCount(allMembers);
    final exemptCnt = sessionItem.calculateExemptCount(allMembers);
    final matches = ref.read(matchesProvider.notifier).getMatchesForSession(sessionItem.id);
    final completedMatches = matches.where((m) => m.isFinished).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isArchived ? Colors.grey.shade200 : AppTheme.primaryMint.withValues(alpha: 0.6),
          width: isArchived ? 1.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          ref.read(sessionProvider.notifier).selectSession(sessionItem);
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isArchived ? AppTheme.pastelPeriwinkle : AppTheme.pastelMint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isArchived ? '지난 모임' : '진행 모임',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isArchived ? AppTheme.pastelPeriwinkleDark : AppTheme.pastelMintDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionItem.displayTitle,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isArchived) ...[
                    Tooltip(
                      message: '지난 모임 기록 삭제',
                      child: InkWell(
                        onTap: () => _showPermanentDeleteSessionDialog(context, sessionItem),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppTheme.pastelRose.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            size: 17,
                            color: AppTheme.pastelRoseDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildMiniStatBadge(
                    icon: Icons.how_to_reg_rounded,
                    text: '출석 ${sessionItem.attendees.length}명',
                    bg: AppTheme.background,
                    fg: AppTheme.textDark,
                  ),
                  _buildMiniStatBadge(
                    icon: Icons.account_balance_wallet_rounded,
                    text: '정산 ${_formatCompactFee(paidFee)}/${_formatCompactFee(totalFee)} (완납 $paidCnt·미납 $unpaidCnt·면제 $exemptCnt)',
                    bg: unpaidCnt > 0 ? AppTheme.pastelRose.withValues(alpha: 0.6) : AppTheme.pastelMint.withValues(alpha: 0.6),
                    fg: unpaidCnt > 0 ? AppTheme.pastelRoseDark : AppTheme.pastelMintDark,
                  ),
                  _buildMiniStatBadge(
                    icon: Icons.emoji_events_rounded,
                    text: '경기 전적 $completedMatches/${matches.length}게임 (${sessionItem.currentRound}R)',
                    bg: AppTheme.pastelYellow.withValues(alpha: 0.65),
                    fg: AppTheme.pastelYellowDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatBadge({
    required IconData icon,
    required String text,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }

  /// 1. 상단 모임 헤더 (좌측 햄버거 메뉴, 모임 타이틀 편집, 참가비 정보, 모임 목록 전환 및 영구 삭제 메뉴)
  Widget _buildSessionHeader(BuildContext context, GameSession session, Club currentClub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => AppTheme.openDrawer(context),
            tooltip: '메뉴 열기',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.menu_rounded, color: AppTheme.textDark, size: 21),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelMint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        currentClub.clubName,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.pastelMintDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: session.isCompleted ? AppTheme.pastelPeriwinkle : AppTheme.primaryDark,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        session.isCompleted ? '지난 모임' : '진행 모임',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: session.isCompleted ? AppTheme.pastelPeriwinkleDark : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        session.displayTitle,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _showEditTitleDialog(context, ref, session),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.drive_file_rename_outline_rounded, size: 15, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('회비: ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text(
                      '회원 ${session.memberFee == 0 ? "무료" : "${session.memberFee}원"}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    const Text(' · ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text(
                      '게스트 ${session.guestFee == 0 ? "무료" : "${session.guestFee}원"}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.pastelMintDark),
                    ),
                    const SizedBox(width: 2),
                    InkWell(
                      onTap: () => _showEditFeeDialog(context, ref, session),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelYellow,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('설정', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.pastelYellowDark)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('session_header_more_menu'),
            tooltip: '',
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textMuted),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              if (value == 'list') {
                ref.read(sessionProvider.notifier).closeSessionView();
              } else if (value == 'end') {
                _showEndSessionConfirmDialog(context, session);
              } else if (value == 'edit_title') {
                _showEditTitleDialog(context, ref, session);
              } else if (value == 'edit_fee') {
                _showEditFeeDialog(context, ref, session);
              } else if (value == 'permanent_delete') {
                _showPermanentDeleteSessionDialog(context, session);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'list',
                child: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, size: 18, color: AppTheme.textDark),
                    SizedBox(width: 8),
                    Text('모임 목록 (진행/지난 모임)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit_title',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: AppTheme.textDark),
                    SizedBox(width: 8),
                    Text('모임 타이틀 변경', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit_fee',
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: AppTheme.textDark),
                    SizedBox(width: 8),
                    Text('참가비/콕비 설정', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if (!session.isCompleted) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'end',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, size: 18, color: AppTheme.pastelPeriwinkleDark),
                      SizedBox(width: 8),
                      Text(
                        '모임 종료하기 (지난 모임 보관)',
                        style: TextStyle(fontSize: 13, color: AppTheme.pastelPeriwinkleDark, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'permanent_delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_rounded, size: 18, color: AppTheme.pastelRoseDark),
                    SizedBox(width: 8),
                    Text(
                      '모임 기록 영구 삭제',
                      style: TextStyle(fontSize: 13, color: AppTheme.pastelRoseDark, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 모임 세션 종료 확인 다이얼로그 (데이터 삭제 없이 [지난 모임]으로 안전하게 보관)
  void _showEndSessionConfirmDialog(BuildContext context, GameSession session) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.archive_rounded, color: AppTheme.pastelPeriwinkleDark, size: 24),
            SizedBox(width: 8),
            Text('모임 종료 및 히스토리 보관', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
        content: Text(
          '\'${session.displayTitle}\' 모임을 종료하시겠습니까?\n\n모임이 종료되어도 출석부, 회비 정산 내역, 경기 전적은 삭제되지 않고 [지난 모임]에 안전하게 보관되어 언제든 다시 조회할 수 있습니다.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppTheme.textDark),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              ref.read(sessionProvider.notifier).endSession();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppTheme.primaryDark,
                  content: Text('모임이 종료되어 [지난 모임] 히스토리에 안전하게 보관되었습니다.'),
                ),
              );
            },
            child: const Text('종료 및 보관하기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// [모임 기록 영구 삭제] 안전장치 확인 팝업 (총무가 수동으로 선택 후 확인을 거칠 때만 삭제)
  void _showPermanentDeleteSessionDialog(BuildContext context, GameSession session) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.pastelRoseDark, size: 24),
            SizedBox(width: 8),
            Text('모임 기록 영구 삭제', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppTheme.pastelRoseDark)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '모임명: ${session.displayTitle}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textDark),
            ),
            const SizedBox(height: 10),
            const Text(
              '모임 기록을 완전히 삭제하시겠습니까? (출석 및 경기 전적이 영구 삭제됩니다)',
              style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.pastelRoseDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('영구 삭제 확인', style: TextStyle(fontWeight: FontWeight.w900)),
            onPressed: () {
              final title = session.displayTitle;
              Navigator.pop(dialogCtx);
              ref.read(sessionProvider.notifier).permanentlyDeleteSession(session.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.pastelRoseDark,
                  content: Text('\'$title\' 모임 기록이 영구 삭제되었습니다.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 금액 포맷터 헬퍼 (천 단위 콤마)
  String _formatWon(int amount) {
    return amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  /// 요약 카드용 금액 포맷터 (1000원 단위는 X.X만, 세밀한 직접 입력 금액은 원 단위 표시)
  String _formatCompactFee(int amount) {
    if (amount == 0) return '0원';
    if (amount % 1000 == 0) {
      final man = amount / 10000;
      return '${man.toStringAsFixed(man * 10 % 1 == 0 ? 1 : 2)}만';
    }
    return '${_formatWon(amount)}원';
  }

  /// 2. 슬림 요약 바: 당일 출석 인원 및 회비 수납 현황 (모바일 화면 가로 칩 Wrap 구성으로 세로 글자 깨짐 원천 방지)
  Widget _buildBentoSummaryGrid(
    BuildContext context, {
    required GameSession session,
    required List<Member> attendeeMembers,
    required int attendeeCount,
    required int activeCount,
    required int restingCount,
    required int withdrawnCount,
    required int totalExpectedFee,
    required int totalPaidFee,
    required int paidCount,
    required int unpaidCount,
    required int exemptCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1단: 당일 출석 인원 요약 (가로 Wrap + 가로 칩으로 세로 줄바꿈 방지)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.how_to_reg_rounded, size: 15, color: AppTheme.primaryMint),
                  const SizedBox(width: 5),
                  const Text(
                    '당일 출석 인원',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$attendeeCount',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                  ),
                  const Text('명', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                ],
              ),
              _buildSummaryStatusChip(
                label: '출전 $activeCount명',
                bg: AppTheme.pastelMint,
                fg: AppTheme.pastelMintDark,
              ),
              _buildSummaryStatusChip(
                label: '휴식 $restingCount명',
                bg: AppTheme.background,
                fg: AppTheme.textDark,
              ),
              _buildSummaryStatusChip(
                label: '조퇴 $withdrawnCount명',
                bg: withdrawnCount > 0 ? AppTheme.pastelRose.withValues(alpha: 0.55) : AppTheme.background,
                fg: withdrawnCount > 0 ? AppTheme.pastelRoseDark : AppTheme.textMuted,
              ),
            ],
          ),
          const Divider(height: 14),
          // 2단: 회비 수납 현황 요약 + [미납자 안내 문자 발송] 버튼 + 가로 칩 Row/Wrap
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 15, color: AppTheme.pastelYellowDark),
              const SizedBox(width: 5),
              const Text(
                '회비 수납 현황',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 6),
              Text(
                _formatCompactFee(totalPaidFee),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textDark),
              ),
              Expanded(
                child: Text(
                  ' / ${_formatCompactFee(totalExpectedFee)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _sendUnpaidGuideSms(context, session, attendeeMembers),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: unpaidCount > 0 ? AppTheme.pastelRose : AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: unpaidCount > 0
                          ? AppTheme.pastelRoseDark.withValues(alpha: 0.35)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sms_outlined,
                        size: 12,
                        color: unpaidCount > 0 ? AppTheme.pastelRoseDark : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '미납자 안내 문자 발송',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: unpaidCount > 0 ? AppTheme.pastelRoseDark : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSummaryStatusChip(
                label: unpaidCount > 0 ? '미납 $unpaidCount명' : '전원 수납완료!',
                bg: unpaidCount > 0 ? AppTheme.pastelRose : AppTheme.pastelMint,
                fg: unpaidCount > 0 ? AppTheme.pastelRoseDark : AppTheme.pastelMintDark,
              ),
              _buildSummaryStatusChip(
                label: '완납 $paidCount명',
                bg: AppTheme.pastelMint.withValues(alpha: 0.55),
                fg: AppTheme.pastelMintDark,
              ),
              _buildSummaryStatusChip(
                label: '면제 $exemptCount명',
                bg: AppTheme.pastelPeriwinkle.withValues(alpha: 0.65),
                fg: AppTheme.pastelPeriwinkleDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 요약 바 내부 가로형 상태 칩 (줄바꿈 없이 가로로 깔끔하게 표시)
  Widget _buildSummaryStatusChip({
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  /// 3. 빠른 액션 바 ([회원 불러오기], [게스트 즉시 추가])
  Widget _buildQuickActionRow(
    BuildContext context,
    WidgetRef ref,
    List<Member> allMembers,
    List<Member> attendeeMembers,
    GameSession session,
  ) {
    return Row(
      children: [
        // [+ 회원 불러오기]
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryDark,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.group_add_rounded, size: 17),
            label: const Text(
              '회원 불러오기',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            onPressed: () => _showImportMembersDialog(context, ref, allMembers, session),
          ),
        ),
        const SizedBox(width: 8),

        // [+ 게스트 즉시 추가]
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.textDark,
              side: const BorderSide(color: AppTheme.primaryMint, width: 1.5),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.person_add_rounded, size: 17, color: AppTheme.primaryMint),
            label: const Text(
              '게스트 즉시 추가',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.textDark),
            ),
            onPressed: () => _showAddGuestDialog(context, ref, session.clubId),
          ),
        ),
      ],
    );
  }

  /// 4. 참석자 내 검색창 + [상단 1단] 인적 속성 드롭다운 필터 + [상단 2단] 출전/회비 상태 필터 칩
  Widget _buildSearchAndFilterBar({
    required int attendeeCount,
    required int activeCount,
    required int restingCount,
    required int withdrawnCount,
    required int paidCount,
    required int unpaidCount,
    required int exemptCount,
    required int filteredCount,
  }) {
    final bool isAllStatusSelected =
        _selectedAttendanceStatus == null && _selectedFeeStatus == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 0) 검색창 + 우측 컴팩트 정렬 버튼(⇅)
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onTapOutside: (_) => _searchFocusNode.unfocus(),
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: InputBorder.none,
                    hintText: '출석자 이름 또는 초성 검색 (예: 손흥민, ㅅㅎㅁ)',
                    hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel_rounded, size: 16, color: AppTheme.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildAttendanceSortButton(),
          ],
        ),
        const SizedBox(height: 8),

        // 1) [상단 1단] 인적 속성 드롭다운 필터 3종 (회원명부와 동일 규격: 급수 / 회원 구분 / 성별)
        Row(
          children: [
            // [급수: 전체 ▾] (전체, A조, B조, C조, D조, 초심)
            Expanded(
              child: _buildCompactDropdownFilter(
                filterTitle: '급수',
                selectedLabel: _selectedTier?.label ?? '전체',
                isActive: _selectedTier != null,
                currentKey: _selectedTier?.code ?? 'ALL',
                items: [
                  (key: 'ALL', label: '전체'),
                  ...Tier.values.map((t) => (key: t.code, label: t.label)),
                ],
                onSelected: (key) {
                  setState(() {
                    if (key == 'ALL') {
                      _selectedTier = null;
                    } else {
                      _selectedTier = Tier.fromString(key);
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),

            // [회원 구분: 전체 ▾] (전체, 운영진, 정회원, 준회원)
            Expanded(
              child: _buildCompactDropdownFilter(
                filterTitle: '회원 구분',
                selectedLabel: _selectedGrade?.label ?? '전체',
                isActive: _selectedGrade != null,
                currentKey: _selectedGrade?.code ?? 'ALL',
                items: [
                  (key: 'ALL', label: '전체'),
                  ...MemberGrade.values.map((g) => (key: g.code, label: g.label)),
                ],
                onSelected: (key) {
                  setState(() {
                    if (key == 'ALL') {
                      _selectedGrade = null;
                    } else {
                      _selectedGrade = MemberGrade.values.firstWhere(
                        (g) => g.code == key,
                        orElse: () => MemberGrade.regular,
                      );
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),

            // [성별: 전체 ▾] (전체, 남성, 여성)
            Expanded(
              child: _buildCompactDropdownFilter(
                filterTitle: '성별',
                selectedLabel: _selectedGender?.label ?? '전체',
                isActive: _selectedGender != null,
                currentKey: _selectedGender?.code ?? 'ALL',
                items: [
                  (key: 'ALL', label: '전체'),
                  (key: Gender.male.code, label: Gender.male.label),
                  (key: Gender.female.code, label: Gender.female.label),
                ],
                onSelected: (key) {
                  setState(() {
                    if (key == 'ALL') {
                      _selectedGender = null;
                    } else {
                      _selectedGender = Gender.fromCode(key);
                    }
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 2) [상단 2단] 당일 출석 및 회비 상태 필터 칩 (출전 상태 | 회비 상태 분리 + 실시간 카운트 뱃지)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // --- 출전 상태 그룹: [전체] | [출전] | [휴식] | [조퇴] ---
              _buildStatusCountChip(
                label: '전체',
                count: attendeeCount,
                isSelected: isAllStatusSelected,
                onTap: () {
                  setState(() {
                    _selectedAttendanceStatus = null;
                    _selectedFeeStatus = null;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildStatusCountChip(
                label: '출전',
                count: activeCount,
                isSelected: _selectedAttendanceStatus == AttendanceStatus.active,
                onTap: () {
                  setState(() {
                    _selectedAttendanceStatus =
                        _selectedAttendanceStatus == AttendanceStatus.active
                            ? null
                            : AttendanceStatus.active;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildStatusCountChip(
                label: '휴식',
                count: restingCount,
                isSelected: _selectedAttendanceStatus == AttendanceStatus.resting,
                onTap: () {
                  setState(() {
                    _selectedAttendanceStatus =
                        _selectedAttendanceStatus == AttendanceStatus.resting
                            ? null
                            : AttendanceStatus.resting;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildStatusCountChip(
                label: '조퇴',
                count: withdrawnCount,
                isSelected: _selectedAttendanceStatus == AttendanceStatus.withdrawn,
                onTap: () {
                  setState(() {
                    _selectedAttendanceStatus =
                        _selectedAttendanceStatus == AttendanceStatus.withdrawn
                            ? null
                            : AttendanceStatus.withdrawn;
                  });
                },
              ),

              // --- 구분선 (|) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  width: 1.5,
                  height: 18,
                  color: Colors.grey.shade300,
                ),
              ),

              // --- 회비 상태 그룹: [미납자만] | [완납] | [면제] ---
              _buildStatusCountChip(
                label: '미납자만',
                count: unpaidCount,
                isSelected: _selectedFeeStatus == FeeStatus.unpaid,
                isAlert: unpaidCount > 0,
                onTap: () {
                  setState(() {
                    _selectedFeeStatus =
                        _selectedFeeStatus == FeeStatus.unpaid ? null : FeeStatus.unpaid;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildStatusCountChip(
                label: '완납',
                count: paidCount,
                isSelected: _selectedFeeStatus == FeeStatus.paid,
                onTap: () {
                  setState(() {
                    _selectedFeeStatus =
                        _selectedFeeStatus == FeeStatus.paid ? null : FeeStatus.paid;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildStatusCountChip(
                label: '면제',
                count: exemptCount,
                isSelected: _selectedFeeStatus == FeeStatus.exempt,
                onTap: () {
                  setState(() {
                    _selectedFeeStatus =
                        _selectedFeeStatus == FeeStatus.exempt ? null : FeeStatus.exempt;
                  });
                },
              ),
            ],
          ),
        ),

        // 복합 필터 활성화 시 [필터 초기화] 및 필터링 결과 인원수 표시 바
        if (_hasActiveFilters) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '필터 적용 결과: $filteredCount명',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryMint,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _resetAllFilters,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 12, color: AppTheme.textDark),
                      SizedBox(width: 3),
                      Text(
                        '필터 초기화',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 출석부 컴팩트 정렬 버튼 위젯 (검색창 우측 배치)
  /// - 기본값: 급수순 (A -> 초심)
  /// - 선택 옵션: 급수순 (A -> 초심) [기본], 이름순 (가나다), 출전 상태순 (출전 -> 휴식 -> 조퇴), 회비 상태순 (미납자 최우선 정렬)
  Widget _buildAttendanceSortButton() {
    final bool isCustomSort = _selectedSortBy != AttendanceSortBy.tierDesc;
    return PopupMenuButton<AttendanceSortBy>(
      tooltip: '출석부 정렬',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 6,
      onSelected: (selected) {
        setState(() {
          _selectedSortBy = selected;
        });
      },
      itemBuilder: (ctx) => AttendanceSortBy.values.map((option) {
        final isSelected = option == _selectedSortBy;
        return PopupMenuItem<AttendanceSortBy>(
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
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⇅ ${_selectedSortBy.label}',
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

  /// [상단 1단] 컴팩트 드롭다운 필터 버튼 위젯 (회원명부와 동일 규격)
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

  /// [상단 2단] 상태 필터 칩 + 실시간 인원수 카운트 뱃지 위젯
  Widget _buildStatusCountChip({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    bool isAlert = false,
  }) {
    Color bg;
    Color textColor;
    Color badgeBg;
    Color badgeText;

    if (isSelected) {
      bg = AppTheme.primaryDark;
      textColor = Colors.white;
      badgeBg = Colors.white.withValues(alpha: 0.2);
      badgeText = Colors.white;
    } else if (isAlert) {
      bg = AppTheme.pastelRose;
      textColor = AppTheme.pastelRoseDark;
      badgeBg = Colors.white.withValues(alpha: 0.75);
      badgeText = AppTheme.pastelRoseDark;
    } else {
      bg = Colors.white;
      textColor = AppTheme.textDark;
      badgeBg = AppTheme.surfaceGrey;
      badgeText = AppTheme.textMuted;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryDark
                : (isAlert ? AppTheme.pastelRoseDark.withValues(alpha: 0.35) : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: badgeText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 5. 참석자 카드
  /// - 동그란 남/여 아이콘 제거, 성별에 따라 카드 배경·테두리 컬러 구분 (남: 은은한 블루톤 / 여: 은은한 핑크·코랄톤)
  /// - 회비 납부 상태 단일 순환 뱃지 (완납 → 미납 → 면제 → 완납)
  /// - 짧게 탭(Tap): 상세 정보 팝업(전화 걸기 / 문자 보내기 포함)
  /// - 길게 누르기(Long Press): 다중 선택 체크 모드 전환 및 일괄 문자 발송 연동
  Widget _buildAttendeeCard({
    required BuildContext context,
    required WidgetRef ref,
    required int index,
    required Member member,
    required GameSession session,
    required AttendanceStatus status,
  }) {
    final tierBg = AppTheme.getTierBgColor(member.tier);
    final tierText = AppTheme.getTierTextColor(member.tier);
    final hasPhone = (member.phoneNumber ?? '').trim().isNotEmpty;
    final isWithdrawn = status == AttendanceStatus.withdrawn;
    final isSelected = _selectedAttendeeIds.contains(member.id);

    // 출전 상태에 따른 스타일 정의
    Color statusBg;
    Color statusText;
    IconData statusIcon;

    switch (status) {
      case AttendanceStatus.active:
        statusBg = AppTheme.pastelMint;
        statusText = AppTheme.pastelMintDark;
        statusIcon = Icons.sports_tennis_rounded;
        break;
      case AttendanceStatus.resting:
        statusBg = AppTheme.pastelYellow;
        statusText = AppTheme.pastelYellowDark;
        statusIcon = Icons.bedtime_rounded;
        break;
      case AttendanceStatus.withdrawn:
        statusBg = Colors.grey.shade200;
        statusText = Colors.grey.shade700;
        statusIcon = Icons.exit_to_app_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.getGenderCardBg(member.gender, isDimmed: isWithdrawn),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.getGenderCardBorder(
            member.gender,
            isSelected: isSelected,
            isDimmed: isWithdrawn,
          ),
          width: isSelected ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_isMultiSelectMode) {
              _toggleMultiSelectMember(member.id);
            } else {
              _showAttendeeDetailDialog(
                context: context,
                ref: ref,
                member: member,
                session: session,
                status: status,
              );
            }
          },
          onLongPress: () => _toggleMultiSelectMember(member.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 다중 선택 모드일 때 체크박스 표시, 기본 모드일 때 순번 + 성별 포인트 바 표시
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
                  const SizedBox(width: 8),
                ] else ...[
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.getGenderAccentColor(member.gender),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 20,
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],

                // 이름 및 소속/게스트/급수 뱃지 + 전화번호 텍스트 탭(tel:)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isWithdrawn ? Colors.grey : AppTheme.textDark,
                                decoration: isWithdrawn ? TextDecoration.lineThrough : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 5),
                          if (member.isGuest)
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.pastelYellow,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '게스트',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.pastelYellowDark,
                                ),
                              ),
                            ),
                          // 급수 뱃지
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: tierBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              member.tier.label,
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: tierText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (!member.isGuest &&
                              (member.role != MemberRole.member ||
                                  (member.customRoleTitle != null &&
                                      member.customRoleTitle!.trim().isNotEmpty))) ...[
                            Text(
                              '${member.displayRoleLabel} · ',
                              style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                            ),
                          ],
                          if (hasPhone)
                            Flexible(
                              child: InkWell(
                                onTap: () => _callMember(context, member),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1),
                                  child: Text(
                                    member.phoneNumber!,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textDark,
                                      decoration: TextDecoration.underline,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: Text(
                                member.isGuest ? (member.homeClub ?? '일회성 게스트') : '전화번호 미등록',
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // [회비 수납 상태 단일 순환 뱃지: 완납 → 미납 → 면제 → 완납]
                _buildFeeStatusSegment(ref, session, member),
                const SizedBox(width: 6),

                // [참여 상태 토글 버튼 (출전 대기 / 일시 휴식 / 조퇴)]
                InkWell(
                  onTap: () => _showStatusSelectModal(context, ref, member, status),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusText),
                        const SizedBox(width: 3),
                        Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: statusText,
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
      ),
    );
  }

  /// 회비 상태 순환 순서: 완납(paid) → 미납(unpaid) → 면제(exempt) → 완납(paid)
  FeeStatus _getNextFeeStatus(FeeStatus current) {
    switch (current) {
      case FeeStatus.paid:
        return FeeStatus.unpaid;
      case FeeStatus.unpaid:
        return FeeStatus.exempt;
      case FeeStatus.exempt:
        return FeeStatus.paid;
    }
  }

  /// 참석자별 회비 납부 상태 단일 순환 뱃지 (터치 시 완납 → 미납 → 면제 → 완납 순환)
  Widget _buildFeeStatusSegment(WidgetRef ref, GameSession session, Member member) {
    final currentFeeStatus = session.getAttendeeFeeStatus(member);

    Color activeBg;
    Color activeText;
    Color borderColor;
    switch (currentFeeStatus) {
      case FeeStatus.paid:
        activeBg = AppTheme.pastelMint;
        activeText = AppTheme.pastelMintDark;
        borderColor = AppTheme.primaryMint.withValues(alpha: 0.35);
        break;
      case FeeStatus.unpaid:
        activeBg = AppTheme.pastelRose;
        activeText = AppTheme.pastelRoseDark;
        borderColor = AppTheme.pastelRoseDark.withValues(alpha: 0.35);
        break;
      case FeeStatus.exempt:
        activeBg = AppTheme.pastelPeriwinkle;
        activeText = AppTheme.pastelPeriwinkleDark;
        borderColor = AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.35);
        break;
    }

    return InkWell(
      onTap: () {
        final nextStatus = _getNextFeeStatus(currentFeeStatus);
        ref.read(membersProvider.notifier).updateFeeStatus(member.id, nextStatus);
        ref.read(sessionProvider.notifier).updateAttendeeFeeStatus(member.id, nextStatus);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentFeeStatus.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: activeText,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.sync_rounded,
              size: 11,
              color: activeText.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  /// 참석자 카드 짧게 클릭(Tap) 시 호출되는 상세 정보 팝업 (전화 걸기 / 문자 보내기 / 정보 수정 / 출석 취소 제공)
  void _showAttendeeDetailDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Member member,
    required GameSession session,
    required AttendanceStatus status,
  }) {
    final feeStatus = session.getAttendeeFeeStatus(member);
    final hasPhone = (member.phoneNumber ?? '').trim().isNotEmpty;

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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    '구분: ${member.gender.label} · ${member.isGuest ? "게스트 (${member.homeClub ?? "일반"})" : member.displayRoleLabel}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '연락처: ${hasPhone ? member.phoneNumber! : "전화번호 미등록"}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '당일 상태: ${status.label} · 회비 ${feeStatus.label}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  ),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.sms_rounded, size: 17),
                    label: const Text('문자 보내기', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      final isUnpaid = feeStatus == FeeStatus.unpaid;
                      final body = isUnpaid
                          ? '[클릭콕 회비 안내] ${member.name}님, \'${session.displayTitle}\' 모임 회비 입금 안내드립니다. 감사합니다!'
                          : null;
                      _sendIndividualSms(context, member, defaultBody: body);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    ref.read(currentTabProvider.notifier).setTab(0);
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 17, color: AppTheme.textDark),
                  label: const Text(
                    '회원명부에서 정보 수정',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    ref.read(sessionProvider.notifier).removeAttendee(member.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${member.name} 님이 오늘 출석부에서 제외되었습니다.')),
                    );
                  },
                  icon: const Icon(Icons.person_remove_rounded, size: 16, color: Colors.red),
                  label: const Text(
                    '출석 취소',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 롱프레스 다중 선택 시 노출되는 ["선택한 회원(N명) 문자 발송"] 액션 바
  Widget _buildMultiSelectSmsBar({
    required BuildContext context,
    required GameSession session,
    required List<Member> attendeeMembers,
    required List<Member> displayedMembers,
  }) {
    final selectedCount = _selectedAttendeeIds.length;
    final allDisplayedSelected = displayedMembers.isNotEmpty &&
        displayedMembers.every((m) => _selectedAttendeeIds.contains(m.id));

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
                if (allDisplayedSelected) {
                  _selectedAttendeeIds.clear();
                  _isMultiSelectMode = false;
                } else {
                  _selectedAttendeeIds.addAll(displayedMembers.map((m) => m.id));
                }
              });
            },
            child: Text(
              allDisplayedSelected ? '전체해제' : '전체선택',
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
              onPressed: () => _sendBulkSmsToSelectedAttendees(context, session, attendeeMembers),
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

  /// 6. 하단 플로팅 액션 바 [출전 가능 N명 · 대진표 설정 및 이동]
  Widget _buildBottomConfirmBar({
    required BuildContext context,
    required WidgetRef ref,
    required GameSession session,
    required int activeCount,
  }) {
    final possibleCourts = (activeCount ~/ 4).clamp(0, 15);
    final canGenerate = activeCount >= 4;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7565E8), Color(0xFF6151D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6151D8).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports_tennis_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      '출전 $activeCount명',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  canGenerate
                      ? '최대 $possibleCourts코트 가동 가능 (${activeCount % 4}명 대기)'
                      : '4명 이상 출전 시 대진표 생성 가능',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.82)),
                ),
              ],
            ),
          ),

          // 대진 설정 & 이동 버튼 (참조 이미지의 화이트 캡슐 CTA 스타일)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: canGenerate ? Colors.white : Colors.white.withValues(alpha: 0.25),
              foregroundColor: canGenerate ? AppTheme.primaryDark : Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text(
              '대진 설정 & 이동',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
            onPressed: canGenerate
                ? () {
                    _showSessionConfirmSheet(context, ref, session.activeAttendees, session);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 모달 및 다이얼로그 헬퍼 메서드들
  // ==========================================

  /// 모임 타이틀 수정 다이얼로그
  void _showEditTitleDialog(BuildContext context, WidgetRef ref, GameSession session) {
    final titleCtrl = TextEditingController(text: session.displayTitle);
    const titlePresets = ['정기 모임', '번개 모임', '월례 대회', '교류전', '주말 운동'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final now = DateTime.now();
          final datePrefix =
              '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
          final currentText = titleCtrl.text.trim();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('모임 타이틀 수정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: '예: 2026.09.25 메가콕 금요 정기모임',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: titlePresets.map((preset) {
                    final isSelected = currentText == '$datePrefix $preset' ||
                        currentText == preset ||
                        currentText.endsWith(' $preset');
                    return InkWell(
                      onTap: () {
                        titleCtrl.text = '$datePrefix $preset';
                        setDialogState(() {});
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryDark : AppTheme.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.primaryMint),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              preset,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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
                  final newTitle = titleCtrl.text.trim();
                  if (newTitle.isNotEmpty) {
                    ref.read(sessionProvider.notifier).updateTitle(newTitle);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 참가비(회원 콕비 / 게스트 참가비) 수정 다이얼로그
  void _showEditFeeDialog(BuildContext context, WidgetRef ref, GameSession session) {
    final memberFeeCtrl = TextEditingController(text: '${session.memberFee}');
    final guestFeeCtrl = TextEditingController(text: '${session.guestFee}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('참가비 / 콕비 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: memberFeeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '정회원 참가비 (원)',
                suffixText: '원',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: guestFeeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '게스트 참가비 (원)',
                suffixText: '원',
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
              final memFee = int.tryParse(memberFeeCtrl.text.trim()) ?? 0;
              final gstFee = int.tryParse(guestFeeCtrl.text.trim()) ?? 0;
              ref.read(sessionProvider.notifier).updateFees(memberFee: memFee, guestFee: gstFee);
              Navigator.pop(ctx);
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
  }

  /// 참석자 출전 상태 변경 모달 (출전 대기 / 일시 휴식 / 조퇴)
  void _showStatusSelectModal(
    BuildContext context,
    WidgetRef ref,
    Member member,
    AttendanceStatus currentStatus,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${member.name} 님의 출전 상태 변경',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textDark),
                ),
                const SizedBox(height: 4),
                const Text(
                  '상태를 변경해도 이미 완료되거나 진행 중인 라운드의 기록은 절대 손상되지 않습니다.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const Divider(height: 24),

                _buildStatusOptionTile(
                  title: '출전',
                  subtitle: '다음 라운드 대진 자동 배정',
                  icon: Icons.sports_tennis_rounded,
                  color: AppTheme.pastelMintDark,
                  bg: AppTheme.pastelMint,
                  isSelected: currentStatus == AttendanceStatus.active,
                  onTap: () {
                    ref.read(sessionProvider.notifier).updateAttendeeStatus(member.id, AttendanceStatus.active);
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 8),

                _buildStatusOptionTile(
                  title: '휴식',
                  subtitle: '잠시 숨돌리기. 다음 라운드 대진 편성에서 제외',
                  icon: Icons.bedtime_rounded,
                  color: AppTheme.pastelYellowDark,
                  bg: AppTheme.pastelYellow,
                  isSelected: currentStatus == AttendanceStatus.resting,
                  onTap: () {
                    ref.read(sessionProvider.notifier).updateAttendeeStatus(member.id, AttendanceStatus.resting);
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 8),

                _buildStatusOptionTile(
                  title: '조퇴',
                  subtitle: '조퇴 또는 부상으로 귀가. 이후 모든 대진에서 제외',
                  icon: Icons.exit_to_app_rounded,
                  color: Colors.red.shade700,
                  bg: AppTheme.pastelRose,
                  isSelected: currentStatus == AttendanceStatus.withdrawn,
                  onTap: () {
                    ref.read(sessionProvider.notifier).updateAttendeeStatus(member.id, AttendanceStatus.withdrawn);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bg,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryDark : AppTheme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.2) : bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: isSelected ? Colors.white : color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white70 : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.primaryMint),
          ],
        ),
      ),
    );
  }

  /// [+ 회원 불러오기] 모달 (해당 클럽 활동 정회원 풀에서 다중 선택 - 휴면 회원은 기본 제외)
  void _showImportMembersDialog(
    BuildContext context,
    WidgetRef ref,
    List<Member> allMembers,
    GameSession session,
  ) {
    final regularMembers = allMembers
        .where((m) =>
            !m.isGuest &&
            m.status == MemberStatus.active &&
            (m.clubId == null || m.clubId == session.clubId))
        .toList();
    final Set<String> tempSelected = Set<String>.from(session.attendees);
    String searchKeyword = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = regularMembers.where((m) {
            if (searchKeyword.isEmpty) return true;
            return m.matchesSearch(searchKeyword);
          }).toList();

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.group_add_rounded, color: AppTheme.primaryMint, size: 22),
                        const SizedBox(width: 8),
                        const Text('정회원 출석부로 불러오기', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              if (tempSelected.length == regularMembers.length) {
                                tempSelected.clear();
                              } else {
                                tempSelected.addAll(regularMembers.map((m) => m.id));
                              }
                            });
                          },
                          child: Text(
                            tempSelected.length == regularMembers.length ? '전체 해제' : '전체 선택',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 검색창
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        onChanged: (val) => setModalState(() => searchKeyword = val.trim()),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: InputBorder.none,
                          hintText: '이름 또는 초성 검색',
                          hintStyle: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 회원 리스트
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final m = filtered[i];
                          final isChecked = tempSelected.contains(m.id);

                          return InkWell(
                            onTap: () {
                              setModalState(() {
                                if (isChecked) {
                                  tempSelected.remove(m.id);
                                } else {
                                  tempSelected.add(m.id);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                    color: isChecked ? AppTheme.primaryMint : Colors.grey.shade400,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(m.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getTierBgColor(m.tier),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      m.tier.label,
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.getTierTextColor(m.tier)),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    m.gender == Gender.female ? '여' : '남',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.getGenderAccentColor(m.gender)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryMint,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          ref.read(sessionProvider.notifier).addAttendees(tempSelected.toList());
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('총 ${tempSelected.length}명의 회원이 출석부에 등록되었습니다!')),
                          );
                        },
                        child: Text(
                          '선택한 ${tempSelected.length}명 출석부 등록',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// [+ 게스트 즉시 추가] 다이얼로그 (일회성 참석자)
  void _showAddGuestDialog(BuildContext context, WidgetRef ref, String clubId) {
    final nameCtrl = TextEditingController();
    final clubCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    Gender selectedGender = Gender.male;
    Tier selectedTier = Tier.novice;
    FeeStatus selectedFeeStatus = FeeStatus.paid;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: AppTheme.primaryMint),
              SizedBox(width: 8),
              Text('게스트 즉시 추가', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '오늘 모임에만 참가하는 일회성 게스트입니다.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '이름 (필수)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),

                // 성별 선택
                Row(
                  children: [
                    const Text('성별: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('남성', style: TextStyle(fontSize: 12)),
                      selected: selectedGender == Gender.male,
                      selectedColor: AppTheme.pastelPeriwinkle,
                      onSelected: (val) => setDialogState(() => selectedGender = Gender.male),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('여성', style: TextStyle(fontSize: 12)),
                      selected: selectedGender == Gender.female,
                      selectedColor: AppTheme.pastelRose,
                      onSelected: (val) => setDialogState(() => selectedGender = Gender.female),
                    ),
                  ],
                ),

                // 급수 선택 드롭다운
                Row(
                  children: [
                    const Text('급수: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    DropdownButton<Tier>(
                      value: selectedTier,
                      items: Tier.values.map((t) {
                        return DropdownMenuItem(value: t, child: Text(t.label));
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedTier = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                TextField(
                  controller: clubCtrl,
                  decoration: InputDecoration(
                    labelText: '원소속 클럽 (선택, 예: 마포콕)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: '연락처 (선택)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // 참가비 납부 상태 (완납 / 미납 / 면제)
                const Text('참가비 납부 상태', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: FeeStatus.values.map((statusOption) {
                    final isSelected = selectedFeeStatus == statusOption;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Center(
                            child: Text(
                              statusOption.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryDark,
                          backgroundColor: AppTheme.background,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedFeeStatus = statusOption);
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
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

                // 새 게스트 멤버 객체 생성
                final newGuest = Member(
                  id: 'guest_${const Uuid().v4().substring(0, 8)}',
                  clubId: clubId,
                  name: name,
                  gender: selectedGender,
                  tier: selectedTier,
                  isGuest: true,
                  feeStatus: selectedFeeStatus,
                  homeClub: clubCtrl.text.trim().isEmpty ? '게스트' : clubCtrl.text.trim(),
                  phoneNumber: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  status: MemberStatus.active,
                );

                // 1. 회원 풀에 추가 (대진 생성 알고리즘이 참조할 수 있도록)
                ref.read(membersProvider.notifier).addMember(newGuest);

                // 2. 세션 출석부에 즉시 합류
                ref.read(sessionProvider.notifier).addAttendee(newGuest.id);

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('게스트 $name 님이 출석부에 추가되었습니다!')),
                );
              },
              child: const Text('추가하기'),
            ),
          ],
        ),
      ),
    );
  }

  /// 대진표 생성 전 [경기 방식, 코트 수 & 시작 코트 번호, 급수 매칭 모드(3단), 파트너 편성 방식 & 고정 페어, 성별 매칭 옵션] 확인/설정 바텀시트
  void _showSessionConfirmSheet(
    BuildContext context,
    WidgetRef ref,
    List<String> selectedIds,
    GameSession session,
  ) {
    final savedPrefs = ref.read(sessionPreferencesProvider);
    final hasSaved = savedPrefs.hasSavedPreferences;
    final recommendedCourts = (selectedIds.length ~/ 4).clamp(1, 15);

    int courtCount = hasSaved && savedPrefs.courtCount != null
        ? savedPrefs.courtCount!.clamp(1, 15)
        : recommendedCourts;
    int startCourtNumber = 1;
    MatchFormat matchFormat = hasSaved ? savedPrefs.matchFormat : session.matchFormat;
    MatchMode matchMode = hasSaved ? savedPrefs.matchMode : session.matchMode;
    PartnerMode partnerMode = hasSaved ? savedPrefs.partnerMode : session.partnerMode;
    final rawMatchType = hasSaved ? savedPrefs.matchType : session.matchType;
    MatchType matchType = MatchType.primaryOptions.contains(rawMatchType)
        ? rawMatchType
        : MatchType.normal;

    final allMembers = ref.read(membersProvider);
    final selectedMembers = allMembers.where((m) => selectedIds.contains(m.id)).toList()
      ..sort((a, b) => b.tierWeight.compareTo(a.tierWeight));
    final memberMap = {for (final m in selectedMembers) m.id: m};
    final maleCount = selectedMembers.where((m) => m.gender == Gender.male).length;
    final femaleCount = selectedMembers.where((m) => m.gender == Gender.female).length;

    // 기존 고정 페어(세션 또는 직전 저장값) 중 현재 출전 명단(selectedIds)에 두 선수 모두 포함된 페어만 유지
    final sourceFixedPairs = session.fixedPairs.isNotEmpty
        ? session.fixedPairs
        : (hasSaved ? savedPrefs.fixedPairs : const <List<String>>[]);
    List<List<String>> fixedPairs = sourceFixedPairs
        .where((p) => p.length == 2 && memberMap.containsKey(p[0]) && memberMap.containsKey(p[1]))
        .map((p) => [p[0], p[1]])
        .toList();

    // 2인 수동 묶기용 첫 번째 선택 선수 ID
    String? pendingPartnerMemberId;
    bool isUsingSavedPrefs = hasSaved;
    bool wasResetToDefault = false;

    void persistCurrentSheetSettings() {
      isUsingSavedPrefs = true;
      wasResetToDefault = false;
      ref.read(sessionPreferencesProvider.notifier).saveSessionSettings(
            matchFormat: matchFormat,
            courtCount: courtCount,
            startCourtNumber: startCourtNumber,
            matchMode: matchMode,
            matchType: matchType,
            partnerMode: partnerMode,
            fixedPairs: fixedPairs,
          );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final endCourtNumber = startCourtNumber + courtCount - 1;
          final waitingCount = (selectedIds.length - (courtCount * 4)).clamp(0, 999);
          final pairedMemberIds = fixedPairs.expand((p) => p).toSet();
          final unpairedMembers = selectedMembers
              .where((m) => !pairedMemberIds.contains(m.id))
              .toList();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.92,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.sports_tennis_rounded, color: AppTheme.primaryMint, size: 24),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '오늘 모임 세션 & 대진 설정',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        key: const Key('reset_session_settings_button'),
                        onPressed: () {
                          setSheetState(() {
                            matchFormat = MatchFormat.regular;
                            courtCount = recommendedCourts;
                            startCourtNumber = 1;
                            matchMode = MatchMode.tiered;
                            partnerMode = PartnerMode.rotation;
                            fixedPairs = [];
                            pendingPartnerMemberId = null;
                            matchType = MatchType.normal;
                            isUsingSavedPrefs = false;
                            wasResetToDefault = true;
                          });
                          ref.read(sessionPreferencesProvider.notifier).resetToDefaults();
                          ref.read(sessionProvider.notifier).resetBracketSettingsToDefault(
                                recommendedCourts: recommendedCourts,
                              );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textMuted,
                          backgroundColor: AppTheme.background,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        icon: const Icon(Icons.restart_alt_rounded, size: 14),
                        label: const Text(
                          '설정 초기화',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '출전 대기 중인 ${selectedIds.length}명 (남 $maleCount · 여 $femaleCount)을 위한 대진표와 코트를 설정합니다.',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ),
                      if (isUsingSavedPrefs || wasResetToDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: wasResetToDefault
                                ? Colors.grey.shade200
                                : AppTheme.pastelMint.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            wasResetToDefault ? '기본 권장 설정' : '직전 설정 기억됨',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: wasResetToDefault
                                  ? AppTheme.textMuted
                                  : AppTheme.pastelMintDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. 경기 방식 선택 (모임 성격)
                  const Text(
                    '경기 방식 선택 (모임 성격)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 10),

                  // 1) [정기 모임 (로테이션)]
                  _buildFormatSelectCard(
                    title: '정기 모임 (로테이션)',
                    badge: '동호회 추천',
                    subtitle: '평소 운동용 · 파트너/상대 자동 교체 · 쉰 사람 우선 배정',
                    icon: Icons.sync_rounded,
                    iconBg: AppTheme.pastelMint,
                    iconColor: AppTheme.pastelMintDark,
                    isSelected: matchFormat == MatchFormat.regular,
                    onTap: () {
                      setSheetState(() => matchFormat = MatchFormat.regular);
                      persistCurrentSheetSettings();
                    },
                  ),
                  const SizedBox(height: 8),

                  // 2) [풀리그전]
                  _buildFormatSelectCard(
                    title: '풀리그전',
                    badge: '리그 랭킹',
                    subtitle: '조별/전체 팀 대결 · 다승 및 득실차 실시간 순위 산출',
                    icon: Icons.leaderboard_rounded,
                    iconBg: AppTheme.pastelYellow,
                    iconColor: AppTheme.pastelYellowDark,
                    isSelected: matchFormat == MatchFormat.league,
                    onTap: () {
                      setSheetState(() => matchFormat = MatchFormat.league);
                      persistCurrentSheetSettings();
                    },
                  ),
                  const SizedBox(height: 8),

                  // 3) [토너먼트]
                  _buildFormatSelectCard(
                    title: '토너먼트',
                    badge: '승자 진출',
                    subtitle: '고정 복식 페어 유지 · 승자 팀만 다음 라운드 진출 (단두대 탈락)',
                    icon: Icons.emoji_events_rounded,
                    iconBg: AppTheme.pastelRose,
                    iconColor: AppTheme.pastelRoseDark,
                    isSelected: matchFormat == MatchFormat.tournament,
                    onTap: () {
                      setSheetState(() => matchFormat = MatchFormat.tournament);
                      persistCurrentSheetSettings();
                    },
                  ),
                  if (matchFormat == MatchFormat.tournament) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelRose.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.pastelRoseDark.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.pastelRoseDark),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '토너먼트는 1라운드에 결성된 2인 페어가 끝까지 유지되며, 경기 완료 시 승리(WIN)한 팀만 다음 라운드에 진출하고 패배 팀은 자동 탈락합니다.',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.pastelRoseDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 2. 코트 수 자동 추천 & 시작 코트 번호 설정
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 2-1. 운영 코트 수
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        '운영 코트 수',
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: courtCount == recommendedCourts
                                              ? AppTheme.pastelMint
                                              : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          courtCount == recommendedCourts
                                              ? '자동 추천 ($recommendedCourts코트)'
                                              : '추천 $recommendedCourts코트',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: courtCount == recommendedCourts
                                                ? AppTheme.pastelMintDark
                                                : AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '동시 최대 ${courtCount * 4}명 경기 · 대기 $waitingCount명',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: courtCount > 1
                                      ? () {
                                          setSheetState(() => courtCount--);
                                          persistCurrentSheetSettings();
                                        }
                                      : null,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.pastelYellow,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$courtCount코트',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.pastelYellowDark),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: courtCount < 15
                                      ? () {
                                          setSheetState(() => courtCount++);
                                          persistCurrentSheetSettings();
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. [선수 매칭 모드 (급수 기준)] 3단 옵션 재구성:
                  // ① 급수별 분리 매칭 (추천) / ② 통합 밸런스 매칭 / ③ 급수 무관 (랜덤 매칭)
                  const Text(
                    '선수 매칭 모드 (급수 기준)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      _buildTierMatchModeCard(
                        title: '급수별 분리 매칭 (추천)',
                        subtitle: '상위부/하위부 독립 코트 배정',
                        icon: Icons.layers_rounded,
                        isSelected: matchMode == MatchMode.tiered,
                        onTap: () {
                          setSheetState(() => matchMode = MatchMode.tiered);
                          persistCurrentSheetSettings();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildTierMatchModeCard(
                        title: '통합 밸런스 매칭',
                        subtitle: '전체 인원 통합 후 A+D vs B+C 실력 밸런스 배정',
                        icon: Icons.balance_rounded,
                        isSelected: matchMode == MatchMode.all,
                        onTap: () {
                          setSheetState(() => matchMode = MatchMode.all);
                          persistCurrentSheetSettings();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildTierMatchModeCard(
                        title: '급수 무관 (랜덤 매칭)',
                        subtitle: '급수 점수를 고려하지 않고 출전 인원 내 완전 무작위 셔플 매칭',
                        icon: Icons.casino_rounded,
                        isSelected: matchMode == MatchMode.random,
                        onTap: () {
                          setSheetState(() => matchMode = MatchMode.random);
                          persistCurrentSheetSettings();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 4. [파트너 편성 방식] 섹션 추가:
                  // 옵션 A: 개인별 로테이션 (기본값) / 옵션 B: 전원 고정 페어 (복식팀 대전)
                  const Text(
                    '파트너 편성 방식',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setSheetState(() {
                              partnerMode = PartnerMode.rotation;
                              pendingPartnerMemberId = null;
                            });
                            persistCurrentSheetSettings();
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                            decoration: BoxDecoration(
                              color: partnerMode == PartnerMode.rotation
                                  ? AppTheme.primaryDark
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: partnerMode == PartnerMode.rotation
                                    ? AppTheme.primaryDark
                                    : Colors.grey.shade300,
                                width: partnerMode == PartnerMode.rotation ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.autorenew_rounded,
                                      size: 15,
                                      color: partnerMode == PartnerMode.rotation
                                          ? AppTheme.primaryMint
                                          : AppTheme.textDark,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '개인별 로테이션 (기본값)',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: partnerMode == PartnerMode.rotation
                                              ? Colors.white
                                              : AppTheme.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '매 라운드 파트너와 상대 자동 교체',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: partnerMode == PartnerMode.rotation
                                        ? Colors.white70
                                        : AppTheme.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                            setSheetState(() {
                              partnerMode = PartnerMode.fixedAll;
                              pendingPartnerMemberId = null;
                            });
                            persistCurrentSheetSettings();
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                            decoration: BoxDecoration(
                              color: partnerMode == PartnerMode.fixedAll
                                  ? AppTheme.primaryDark
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: partnerMode == PartnerMode.fixedAll
                                    ? AppTheme.primaryDark
                                    : Colors.grey.shade300,
                                width: partnerMode == PartnerMode.fixedAll ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.people_alt_rounded,
                                      size: 15,
                                      color: partnerMode == PartnerMode.fixedAll
                                          ? AppTheme.primaryMint
                                          : AppTheme.textDark,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '전원 고정 페어 (복식팀 대전)',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: partnerMode == PartnerMode.fixedAll
                                              ? Colors.white
                                              : AppTheme.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '2인 1조 페어로 모임 내내 팀 대결',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: partnerMode == PartnerMode.fixedAll
                                        ? Colors.white70
                                        : AppTheme.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 4-1. [복식 페어(파트너) 편성 인터페이스]
                  if (partnerMode == PartnerMode.fixedAll) ...[
                    // [전원 고정 페어] 선택 시: 복식 페어 편성 목록 UI (2인 수동 묶기 및 [급수별 자동 짝짓기] 지원)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.pastelMint.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.primaryMint.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.group_work_rounded, size: 18, color: AppTheme.pastelMintDark),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  '복식 페어 편성 목록',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${fixedPairs.length}팀 편성 · 미편성 ${unpairedMembers.length}명',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.pastelMintDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // [급수별 자동 짝짓기] 버튼 및 [전체 해제] 버튼
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryDark,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16, color: AppTheme.primaryMint),
                                  label: const Text(
                                    '급수별 자동 짝짓기',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () {
                                    setSheetState(() {
                                      pendingPartnerMemberId = null;
                                      final generator = ref.read(matchGeneratorServiceProvider);
                                      if (unpairedMembers.length >= 2) {
                                        // 미편성 인원들을 급수 기준으로 자동 짝짓기 추가
                                        final newAutoPairs = generator.autoPairByTier(
                                          members: unpairedMembers,
                                          matchMode: matchMode,
                                          matchType: matchType,
                                        );
                                        fixedPairs = [...fixedPairs, ...newAutoPairs];
                                      } else {
                                        // 이미 전원 편성된 상태라면 전체 인원을 현재 급수 모드로 재편성
                                        fixedPairs = generator.autoPairByTier(
                                          members: selectedMembers,
                                          matchMode: matchMode,
                                          matchType: matchType,
                                        );
                                      }
                                    });
                                    persistCurrentSheetSettings();
                                  },
                                ),
                              ),
                              if (fixedPairs.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppTheme.pastelRoseDark,
                                    side: BorderSide(color: AppTheme.pastelRoseDark.withValues(alpha: 0.4)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded, size: 15),
                                  label: const Text(
                                    '초기화',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () {
                                    setSheetState(() {
                                      fixedPairs = [];
                                      pendingPartnerMemberId = null;
                                    });
                                    persistCurrentSheetSettings();
                                  },
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),

                          // 편성된 복식 페어 카드 리스트
                          if (fixedPairs.isNotEmpty) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: List.generate(fixedPairs.length, (idx) {
                                final pair = fixedPairs[idx];
                                final m1 = memberMap[pair[0]];
                                final m2 = memberMap[pair[1]];
                                if (m1 == null || m2 == null) return const SizedBox.shrink();
                                final sumPts = m1.tierWeight + m2.tierWeight;
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.primaryMint),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryDark,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${idx + 1}조',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${m1.name}(${m1.tier.code}) & ${m2.name}(${m2.tier.code})',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${sumPts}pt',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.pastelMintDark,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          setSheetState(() {
                                            fixedPairs.removeAt(idx);
                                          });
                                          persistCurrentSheetSettings();
                                        },
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 15,
                                          color: AppTheme.pastelRoseDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // 미편성 인원 2인 수동 묶기 영역
                          if (unpairedMembers.isNotEmpty) ...[
                            Text(
                              pendingPartnerMemberId == null
                                  ? '2인 수동 묶기: 파트너로 묶을 첫 번째 선수를 탭하세요 (${unpairedMembers.length}명 대기)'
                                  : '2인 수동 묶기: [${memberMap[pendingPartnerMemberId]?.name ?? ''}]님의 파트너가 될 두 번째 선수를 탭하세요!',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: pendingPartnerMemberId == null
                                    ? AppTheme.textMuted
                                    : AppTheme.pastelMintDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: unpairedMembers.map((m) {
                                final isFirstSelected = pendingPartnerMemberId == m.id;
                                return InkWell(
                                  onTap: () {
                                    bool pairCreated = false;
                                    setSheetState(() {
                                      if (pendingPartnerMemberId == null) {
                                        pendingPartnerMemberId = m.id;
                                      } else if (pendingPartnerMemberId == m.id) {
                                        pendingPartnerMemberId = null;
                                      } else {
                                        fixedPairs.add([pendingPartnerMemberId!, m.id]);
                                        pendingPartnerMemberId = null;
                                        pairCreated = true;
                                      }
                                    });
                                    if (pairCreated) {
                                      persistCurrentSheetSettings();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isFirstSelected ? AppTheme.primaryDark : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isFirstSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      '${m.name} (${m.tier.label})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: isFirstSelected ? Colors.white : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ] else if (fixedPairs.isNotEmpty) ...[
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, size: 15, color: AppTheme.pastelMintDark),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '모든 출전 인원의 복식 페어 편성이 완료되었습니다! 라운드 내내 고정 팀으로 출전합니다.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.pastelMintDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...[
                    // [개인별 로테이션] 선택 시: 특정 고정 페어 목록 표시 + [+ 특정 고정 페어 추가] 버튼 지원
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (fixedPairs.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.push_pin_rounded, size: 15, color: AppTheme.pastelPeriwinkleDark),
                                const SizedBox(width: 5),
                                Text(
                                  '지정된 특정 고정 페어 (${fixedPairs.length}팀 · 나머지는 개인 로테이션)',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.pastelPeriwinkleDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: List.generate(fixedPairs.length, (idx) {
                                final pair = fixedPairs[idx];
                                final m1 = memberMap[pair[0]];
                                final m2 = memberMap[pair[1]];
                                if (m1 == null || m2 == null) return const SizedBox.shrink();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.pastelPeriwinkleDark.withValues(alpha: 0.45)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lock_rounded, size: 12, color: AppTheme.pastelPeriwinkleDark),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${m1.name}(${m1.tier.code}) & ${m2.name}(${m2.tier.code})',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textDark,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          setSheetState(() {
                                            fixedPairs.removeAt(idx);
                                          });
                                          persistCurrentSheetSettings();
                                        },
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 15,
                                          color: AppTheme.pastelRoseDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.textDark,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppTheme.pastelMintDark),
                              label: const Text(
                                '+ 특정 고정 페어 추가',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              onPressed: unpairedMembers.length < 2
                                  ? null
                                  : () => _showAddSpecificFixedPairDialog(
                                        context: ctx,
                                        availableMembers: unpairedMembers,
                                        onPairAdded: (id1, id2) {
                                          setSheetState(() {
                                            fixedPairs.add([id1, id2]);
                                          });
                                          persistCurrentSheetSettings();
                                        },
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // 5. 성별 매칭 옵션 (4가지 선택지)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '성별 매칭 옵션',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelPeriwinkle,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '남 $maleCount명 · 여 $femaleCount명',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.pastelPeriwinkleDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.35,
                    children: MatchType.primaryOptions.map((option) {
                      final isSelected = matchType == option;
                      return InkWell(
                        onTap: () {
                          setSheetState(() => matchType = option);
                          persistCurrentSheetSettings();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryDark : AppTheme.background,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    option == MatchType.normal
                                        ? Icons.shuffle_rounded
                                        : option == MatchType.separate
                                            ? Icons.wc_rounded
                                            : option == MatchType.mixedOnly
                                                ? Icons.favorite_border_rounded
                                                : Icons.low_priority_rounded,
                                    size: 14,
                                    color: isSelected ? AppTheme.primaryMint : AppTheme.textDark,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      option == MatchType.normal ? '전체 혼합 (기본값)' : option.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? Colors.white : AppTheme.textDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                option.description,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected ? Colors.white70 : AppTheme.textMuted,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 6. 세션 시작 및 대진표 화면으로 바로 이동 버튼 (하단 고정)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              key: const Key('start_session_and_generate_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryMint,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: () {
                // [전원 고정 페어] 모드에서 미편성 인원이 남아있을 경우 자동으로 2인 페어 보완
                List<List<String>> finalFixedPairs = List<List<String>>.from(fixedPairs);
                if (partnerMode == PartnerMode.fixedAll && unpairedMembers.length >= 2) {
                  final autoPairs = ref.read(matchGeneratorServiceProvider).autoPairByTier(
                        members: unpairedMembers,
                        matchMode: matchMode,
                        matchType: matchType,
                      );
                  finalFixedPairs = [...finalFixedPairs, ...autoPairs];
                }

                // 새 세션 시작 및 1라운드 대진 생성 (대진표 화면 자동 전환 포함)
                ref.read(matchesProvider.notifier).startNewSessionAndGenerate(
                      attendeeIds: selectedIds,
                      courtCount: courtCount,
                      startCourtNumber: startCourtNumber,
                      matchMode: matchMode,
                      matchFormat: matchFormat,
                      matchType: matchType,
                      partnerMode: partnerMode,
                      fixedPairs: finalFixedPairs,
                    );

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
                            '[${matchFormat.label} · ${matchMode.label}] ${selectedIds.length}명 출전 · $startCourtNumber~$endCourtNumber번($courtCount코트) 대진표가 생성되었습니다!',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rocket_launch_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    '세션 시작 & 대진 생성',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
  },
),
);
  }

  /// [선수 매칭 모드 (급수 기준)] 3단 선택 카드 빌더
  Widget _buildTierMatchModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryDark : AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
            width: isSelected ? 1.8 : 1,
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
                  const SizedBox(height: 2),
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

  /// [개인별 로테이션] 내 [+ 특정 고정 페어 추가] 선택 다이얼로그
  void _showAddSpecificFixedPairDialog({
    required BuildContext context,
    required List<Member> availableMembers,
    required void Function(String id1, String id2) onPairAdded,
  }) {
    final selectedPairIds = <String>[];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.people_alt_rounded, color: AppTheme.pastelMintDark, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '특정 고정 페어 추가',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedPairIds.isEmpty
                        ? '고정 파트너로 묶을 선수 2명을 선택해 주세요. (나머지 인원은 개인 로테이션 진행)'
                        : selectedPairIds.length == 1
                            ? '파트너가 될 두 번째 선수를 선택해 주세요 (1/2 선택됨)'
                            : '고정 페어 2명이 선택되었습니다! (2/2 선택 완료)',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: availableMembers.map((m) {
                          final isSelected = selectedPairIds.contains(m.id);
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  selectedPairIds.remove(m.id);
                                } else if (selectedPairIds.length < 2) {
                                  selectedPairIds.add(m.id);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryDark : AppTheme.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                '${m.name} (${m.tier.label})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('취소', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryMint,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: selectedPairIds.length == 2
                    ? () {
                        onPairAdded(selectedPairIds[0], selectedPairIds[1]);
                        Navigator.pop(dialogCtx);
                      }
                    : null,
                child: const Text('고정 페어 등록', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 경기 방식 선택 카드 빌더
  Widget _buildFormatSelectCard({
    required String title,
    required String badge,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryDark : AppTheme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryDark.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.18) : iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryMint : iconBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : iconColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.white70 : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: isSelected ? AppTheme.primaryMint : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  /// 3단계 모임 생성 모달 (1단계: 클럽 선택 -> 2단계: 모임 정보 & 회비 -> 3단계: 참석 회원 선택)
  void _showStartGatheringModal(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final datePrefix =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

    final savedPrefs = ref.read(sessionPreferencesProvider);
    final hasSaved = savedPrefs.hasSavedPreferences;

    final initialPreset = hasSaved && savedPrefs.titlePreset.isNotEmpty
        ? savedPrefs.titlePreset
        : '정기 모임';
    final defaultTitle = '$datePrefix $initialPreset';

    final clubs = ref.read(clubsProvider);
    final allMembers = ref.read(membersProvider);
    final currentClubId = ref.read(currentClubIdProvider);

    int currentStep = 1;
    String selectedClubId = currentClubId;
    final titleController = TextEditingController(text: defaultTitle);
    String selectedTitlePreset = initialPreset;

    int memberFee = hasSaved ? savedPrefs.memberFee : 5000;
    int guestFee = hasSaved ? savedPrefs.guestFee : 10000;
    bool isCustomMemberFee = hasSaved ? savedPrefs.isCustomMemberFee : false;
    bool isCustomGuestFee = hasSaved ? savedPrefs.isCustomGuestFee : false;
    final customMemberFeeController = TextEditingController(text: memberFee.toString());
    final customGuestFeeController = TextEditingController(text: guestFee.toString());

    // 해당 클럽의 정회원 목록 중 활성 회원을 초기 참석자로 자동 설정
    Set<String> selectedMemberIds = allMembers
        .where((m) => m.clubId == selectedClubId && m.status == MemberStatus.active)
        .map((m) => m.id)
        .toSet();

    final stepSearchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // 휴면 상태인 회원은 당일 모임 [출석부 목록]에서 기본적으로 제외되어 출석 체크 혼선 방지
          final clubMembers = allMembers
              .where((m) => m.clubId == selectedClubId && m.status == MemberStatus.active)
              .toList();
          final selectedClub = clubs.firstWhere(
            (c) => c.id == selectedClubId,
            orElse: () => clubs.first,
          );

          // 검색 필터링된 회원 목록
          final searchQuery = stepSearchController.text.trim();
          final filteredClubMembers = clubMembers.where((m) {
            if (searchQuery.isEmpty) return true;
            return m.matchesSearch(searchQuery);
          }).toList();

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 상단 드래그 핸들
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

                  // 상단 모달 타이틀 & 설정 초기화 / 닫기 버튼
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.pastelMint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.rocket_launch_rounded, color: AppTheme.pastelMintDark, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '새 모임 시작하기',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setModalState(() {
                              selectedTitlePreset = '정기 모임';
                              titleController.text = '$datePrefix 정기 모임';
                              memberFee = 5000;
                              guestFee = 10000;
                              isCustomMemberFee = false;
                              isCustomGuestFee = false;
                              customMemberFeeController.text = '5000';
                              customGuestFeeController.text = '10000';
                            });
                            ref.read(sessionPreferencesProvider.notifier).resetToDefaults();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.textMuted,
                            backgroundColor: AppTheme.background,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          icon: const Icon(Icons.restart_alt_rounded, size: 14),
                          label: const Text(
                            '설정 초기화',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                  ),

                  // 3단계 스텝 인디케이터 배지 바
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStepBadge(
                            step: 1,
                            label: '클럽 선택',
                            currentStep: currentStep,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildStepBadge(
                            step: 2,
                            label: '모임 & 회비',
                            currentStep: currentStep,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildStepBadge(
                            step: 3,
                            label: '참석자 등록',
                            currentStep: currentStep,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1, thickness: 1),

                  // 메인 콘텐츠 단계별 뷰
                  Flexible(
                    child: currentStep == 1
                        ? _buildStep1ClubSelection(
                            clubs: clubs,
                            selectedClubId: selectedClubId,
                            onSelectClub: (clubId) {
                              setModalState(() {
                                selectedClubId = clubId;
                                // 클럽 변경 시 해당 클럽의 활성 회원으로 자동 재선택
                                selectedMemberIds = allMembers
                                    .where((m) => m.clubId == clubId && m.status == MemberStatus.active)
                                    .map((m) => m.id)
                                    .toSet();
                              });
                            },
                          )
                        : currentStep == 2
                            ? _buildStep2SessionInfo(
                                selectedClub: selectedClub,
                                titleController: titleController,
                                selectedTitlePreset: selectedTitlePreset,
                                memberFee: memberFee,
                                guestFee: guestFee,
                                isCustomMemberFee: isCustomMemberFee,
                                isCustomGuestFee: isCustomGuestFee,
                                customMemberFeeController: customMemberFeeController,
                                customGuestFeeController: customGuestFeeController,
                                onSelectPreset: (preset) {
                                  setModalState(() {
                                    selectedTitlePreset = preset;
                                    titleController.text = '$datePrefix $preset';
                                  });
                                },
                                onTitleTextEdited: (val) {
                                  setModalState(() {
                                    final trimmed = val.trim();
                                    const presets = ['정기 모임', '번개 모임', '월례 대회', '교류전', '주말 운동'];
                                    String matched = '';
                                    for (final p in presets) {
                                      if (trimmed.endsWith(p) || trimmed == p) {
                                        matched = p;
                                        break;
                                      }
                                    }
                                    selectedTitlePreset = matched;
                                  });
                                },
                                onSelectPresetMemberFee: (fee) {
                                  setModalState(() {
                                    isCustomMemberFee = false;
                                    memberFee = fee;
                                    customMemberFeeController.text = fee.toString();
                                  });
                                },
                                onEnableCustomMemberFee: () {
                                  setModalState(() {
                                    isCustomMemberFee = true;
                                    customMemberFeeController.text = memberFee.toString();
                                  });
                                },
                                onCustomMemberFeeEdited: (text) {
                                  setModalState(() {
                                    final parsed = int.tryParse(text.replaceAll(',', '').trim()) ?? 0;
                                    memberFee = parsed < 0 ? 0 : parsed;
                                  });
                                },
                                onSelectPresetGuestFee: (fee) {
                                  setModalState(() {
                                    isCustomGuestFee = false;
                                    guestFee = fee;
                                    customGuestFeeController.text = fee.toString();
                                  });
                                },
                                onEnableCustomGuestFee: () {
                                  setModalState(() {
                                    isCustomGuestFee = true;
                                    customGuestFeeController.text = guestFee.toString();
                                  });
                                },
                                onCustomGuestFeeEdited: (text) {
                                  setModalState(() {
                                    final parsed = int.tryParse(text.replaceAll(',', '').trim()) ?? 0;
                                    guestFee = parsed < 0 ? 0 : parsed;
                                  });
                                },
                              )
                            : ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: MediaQuery.of(ctx).size.height * 0.58,
                                ),
                                child: _buildStep3MemberSelection(
                                  clubMembers: filteredClubMembers,
                                  totalCount: clubMembers.length,
                                  selectedIds: selectedMemberIds,
                                  searchController: stepSearchController,
                                  onSearchChanged: () => setModalState(() {}),
                                  onToggleMember: (id) {
                                    setModalState(() {
                                      if (selectedMemberIds.contains(id)) {
                                        selectedMemberIds.remove(id);
                                      } else {
                                        selectedMemberIds.add(id);
                                      }
                                    });
                                  },
                                  onSelectAll: () {
                                    setModalState(() {
                                      if (selectedMemberIds.length == clubMembers.length) {
                                        selectedMemberIds.clear();
                                      } else {
                                        selectedMemberIds = clubMembers.map((m) => m.id).toSet();
                                      }
                                    });
                                  },
                                ),
                              ),
                  ),

                  // 하단 이전 / 다음 네비게이션 액션 바 (SafeArea bottom 밀착 정돈)
                  Container(
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
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: Row(
                          children: [
                            if (currentStep > 1) ...[
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.textDark,
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                label: const Text('이전', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () => setModalState(() => currentStep--),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryMint,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 0,
                                  ),
                                  onPressed: () {
                                    if (currentStep == 1) {
                                      setModalState(() => currentStep = 2);
                                    } else if (currentStep == 2) {
                                      if (titleController.text.trim().isEmpty) {
                                        titleController.text = defaultTitle;
                                      }
                                      if (isCustomMemberFee) {
                                        final parsed = int.tryParse(customMemberFeeController.text.replaceAll(',', '').trim()) ?? 0;
                                        memberFee = parsed < 0 ? 0 : parsed;
                                      }
                                      if (isCustomGuestFee) {
                                        final parsed = int.tryParse(customGuestFeeController.text.replaceAll(',', '').trim()) ?? 0;
                                        guestFee = parsed < 0 ? 0 : parsed;
                                      }
                                      setModalState(() => currentStep = 3);
                                    } else {
                                      // 3단계 완료: 세션 생성
                                      final finalTitle = titleController.text.trim().isEmpty
                                          ? defaultTitle
                                          : titleController.text.trim();

                                      // 0. 모임 기본 정보 설정(프리셋/회비) 로컬 저장소 기억
                                      ref.read(sessionPreferencesProvider.notifier).saveGatheringStartSettings(
                                            titlePreset: selectedTitlePreset.isNotEmpty
                                                ? selectedTitlePreset
                                                : '정기 모임',
                                            memberFee: memberFee,
                                            guestFee: guestFee,
                                            isCustomMemberFee: isCustomMemberFee,
                                            isCustomGuestFee: isCustomGuestFee,
                                          );

                                      // 1. 선택된 클럽 활성화
                                      ref.read(currentClubIdProvider.notifier).switchClub(selectedClubId);

                                      // 2. 세션 생성 및 참석자 일괄 등록
                                      ref.read(sessionProvider.notifier).createSession(
                                            clubId: selectedClubId,
                                            title: finalTitle,
                                            memberFee: memberFee,
                                            guestFee: guestFee,
                                            attendeeIds: selectedMemberIds.toList(),
                                          );

                                      Navigator.pop(modalCtx);

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.fromLTRB(20, 0, 20, 88),
                                          backgroundColor: AppTheme.primaryDark,
                                          content: Row(
                                            children: [
                                              const Icon(Icons.check_circle_rounded, color: AppTheme.primaryMint, size: 20),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '\'${selectedClub.clubName}\' 모임이 시작되었습니다! (${selectedMemberIds.length}명 출석 등록)',
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        currentStep == 1
                                            ? '다음: 모임 정보 설정 (2단계) →'
                                            : currentStep == 2
                                                ? '다음: 참석자 등록 (3단계) →'
                                                : '모임 시작 & 출석부 열기 (${selectedMemberIds.length}명) 🏸',
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
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
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 스텝 인디케이터 배지
  Widget _buildStepBadge({
    required int step,
    required String label,
    required int currentStep,
  }) {
    final isCurrent = currentStep == step;
    final isDone = currentStep > step;

    Color bgColor = Colors.grey.shade100;
    Color textColor = AppTheme.textMuted;
    Color borderColor = Colors.grey.shade300;

    if (isCurrent) {
      bgColor = AppTheme.pastelMint;
      textColor = AppTheme.pastelMintDark;
      borderColor = AppTheme.primaryMint;
    } else if (isDone) {
      bgColor = AppTheme.pastelMint.withValues(alpha: 0.45);
      textColor = AppTheme.pastelMintDark;
      borderColor = Colors.transparent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isCurrent ? 1.5 : 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: isCurrent || isDone ? AppTheme.primaryMint : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isDone
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '$step',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 1단계: 관리 중인 클럽 선택 뷰
  Widget _buildStep1ClubSelection({
    required List<Club> clubs,
    required String selectedClubId,
    required ValueChanged<String> onSelectClub,
  }) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        const Text(
          '1단계. 진행할 모임(클럽)을 선택해 주세요',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textDark),
        ),
        const SizedBox(height: 4),
        const Text(
          '다중 관리 중인 클럽 목록입니다. 오늘 정기 모임을 진행할 클럽을 선택하세요.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 16),
        ...clubs.map((club) {
          final isSelected = club.id == selectedClubId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => onSelectClub(club.id),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.pastelMint.withValues(alpha: 0.35) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryMint : Colors.grey.shade200,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryMint : AppTheme.pastelMint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        color: isSelected ? Colors.white : AppTheme.pastelMintDark,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                club.clubName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '등록 회원 ${club.memberCount}명 · ${(club.description?.isEmpty ?? true) ? "정기 배드민턴 클럽" : club.description!}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                      color: isSelected ? AppTheme.primaryMint : Colors.grey.shade400,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// 2단계: 모임 타이틀 및 회비 설정 뷰
  Widget _buildStep2SessionInfo({
    required Club selectedClub,
    required TextEditingController titleController,
    required String selectedTitlePreset,
    required int memberFee,
    required int guestFee,
    required bool isCustomMemberFee,
    required bool isCustomGuestFee,
    required TextEditingController customMemberFeeController,
    required TextEditingController customGuestFeeController,
    required ValueChanged<String> onSelectPreset,
    required ValueChanged<String> onTitleTextEdited,
    required ValueChanged<int> onSelectPresetMemberFee,
    required VoidCallback onEnableCustomMemberFee,
    required ValueChanged<String> onCustomMemberFeeEdited,
    required ValueChanged<int> onSelectPresetGuestFee,
    required VoidCallback onEnableCustomGuestFee,
    required ValueChanged<String> onCustomGuestFeeEdited,
  }) {
    final titlePresets = ['정기 모임', '번개 모임', '월례 대회', '교류전', '주말 운동'];
    final memberFeePresets = [0, 3000, 5000, 10000];
    final guestFeePresets = [5000, 10000, 15000, 20000];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.pastelMint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                selectedClub.clubName,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.pastelMintDark),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '2단계. 모임 정보 & 회비 설정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textDark),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '오늘 모임의 제목과 참석자별 회비/콕비를 설정하세요.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 18),

        // 모임 타이틀 입력
        const Text('모임 타이틀', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        const SizedBox(height: 6),
        TextField(
          controller: titleController,
          onChanged: onTitleTextEdited,
          decoration: InputDecoration(
            hintText: '예: 2026.09.26 정기 모임',
            prefixIcon: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryMint),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: titlePresets.map((preset) {
            final isSelected = selectedTitlePreset == preset ||
                titleController.text.trim().endsWith(preset);
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    preset,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              selectedColor: AppTheme.primaryDark,
              backgroundColor: AppTheme.background,
              showCheckmark: false,
              side: BorderSide(
                color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              onSelected: (_) => onSelectPreset(preset),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // 정회원 참가비 / 콕비 설정
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('정회원 참가비 (콕비)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            Text(
              memberFee == 0 ? '무료 (0원)' : '${memberFee.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.pastelMintDark),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...memberFeePresets.map((fee) {
              final isSelected = !isCustomMemberFee && memberFee == fee;
              return ChoiceChip(
                label: Text(
                  fee == 0 ? '무료' : '${fee ~/ 1000}천원',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.textDark,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppTheme.primaryDark,
                backgroundColor: AppTheme.background,
                showCheckmark: false,
                side: BorderSide(
                  color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (val) {
                  if (val) onSelectPresetMemberFee(fee);
                },
              );
            }),
            ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_rounded,
                    size: 13,
                    color: isCustomMemberFee ? Colors.white : AppTheme.pastelMintDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '직접 입력',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCustomMemberFee ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              selected: isCustomMemberFee,
              selectedColor: AppTheme.primaryMint,
              backgroundColor: AppTheme.background,
              showCheckmark: false,
              side: BorderSide(
                color: isCustomMemberFee ? AppTheme.primaryMint : Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (_) => onEnableCustomMemberFee(),
            ),
          ],
        ),
        if (isCustomMemberFee) ...[
          const SizedBox(height: 10),
          TextField(
            controller: customMemberFeeController,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: onCustomMemberFeeEdited,
            decoration: InputDecoration(
              labelText: '정회원 참가비 직접 입력',
              hintText: '금액 입력 (예: 7000)',
              suffixText: '원',
              prefixIcon: const Icon(Icons.payments_outlined, color: AppTheme.primaryMint, size: 20),
              filled: true,
              fillColor: AppTheme.pastelMint.withValues(alpha: 0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryMint),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryMint),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryMint, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],

        const SizedBox(height: 22),

        // 게스트 참가비 설정
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('게스트(일회성) 참가비', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            Text(
              guestFee == 0 ? '무료 (0원)' : '${guestFee.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.pastelYellowDark),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...guestFeePresets.map((fee) {
              final isSelected = !isCustomGuestFee && guestFee == fee;
              return ChoiceChip(
                label: Text(
                  '${fee ~/ 1000}천원',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.textDark,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppTheme.primaryDark,
                backgroundColor: AppTheme.background,
                showCheckmark: false,
                side: BorderSide(
                  color: isSelected ? AppTheme.primaryDark : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (val) {
                  if (val) onSelectPresetGuestFee(fee);
                },
              );
            }),
            ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_rounded,
                    size: 13,
                    color: isCustomGuestFee ? Colors.white : AppTheme.pastelYellowDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '직접 입력',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCustomGuestFee ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              selected: isCustomGuestFee,
              selectedColor: AppTheme.primaryMint,
              backgroundColor: AppTheme.background,
              showCheckmark: false,
              side: BorderSide(
                color: isCustomGuestFee ? AppTheme.primaryMint : Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (_) => onEnableCustomGuestFee(),
            ),
          ],
        ),
        if (isCustomGuestFee) ...[
          const SizedBox(height: 10),
          TextField(
            controller: customGuestFeeController,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: onCustomGuestFeeEdited,
            decoration: InputDecoration(
              labelText: '게스트 참가비 직접 입력',
              hintText: '금액 입력 (예: 8000)',
              suffixText: '원',
              prefixIcon: const Icon(Icons.payments_outlined, color: AppTheme.pastelYellowDark, size: 20),
              filled: true,
              fillColor: AppTheme.pastelYellow.withValues(alpha: 0.25),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.pastelYellowDark),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.pastelYellowDark),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.pastelYellowDark, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ],
    );
  }

  /// 3단계: 선택된 클럽 회원 일괄 참석 선택 뷰
  Widget _buildStep3MemberSelection({
    required List<Member> clubMembers,
    required int totalCount,
    required Set<String> selectedIds,
    required TextEditingController searchController,
    required VoidCallback onSearchChanged,
    required ValueChanged<String> onToggleMember,
    required VoidCallback onSelectAll,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 상단 안내 & 전체 선택 바
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '3단계. 오늘 참석 정회원 등록',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelMint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '선택됨 ${selectedIds.length} / $totalCount명',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.pastelMintDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '체크된 회원이 오늘 출석부에 바로 등록됩니다. (미체크 회원은 불참 처리)',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),

              // 검색창 및 전체 선택 버튼
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: searchController,
                        onChanged: (_) => onSearchChanged(),
                        decoration: InputDecoration(
                          hintText: '이름/초성 검색 (예: ㄱㄷㅎ, 홍길동)',
                          hintStyle: const TextStyle(fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          filled: true,
                          fillColor: AppTheme.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.background,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      selectedIds.length == totalCount ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 18,
                      color: AppTheme.textDark,
                    ),
                    label: Text(
                      selectedIds.length == totalCount ? '선택 해제' : '전체 선택',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    onPressed: onSelectAll,
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 회원 리스트
        Flexible(
          child: clubMembers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('등록된 회원이 없거나 검색 결과가 없습니다.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: clubMembers.length,
                  itemBuilder: (ctx, index) {
                    final member = clubMembers[index];
                    final isChecked = selectedIds.contains(member.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isChecked ? AppTheme.pastelMint.withValues(alpha: 0.15) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isChecked ? AppTheme.primaryMint : Colors.grey.shade200,
                          width: isChecked ? 1.5 : 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          onTap: () => onToggleMember(member.id),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: member.gender == Gender.male ? AppTheme.pastelPeriwinkle : AppTheme.pastelRose,
                            child: Icon(
                              member.gender == Gender.male ? Icons.male_rounded : Icons.female_rounded,
                              size: 18,
                              color: member.gender == Gender.male ? AppTheme.pastelPeriwinkleDark : AppTheme.pastelRoseDark,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                member.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isChecked ? FontWeight.w900 : FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildTierMiniBadge(member.tier),
                              if (member.role != MemberRole.member ||
                                  (member.customRoleTitle != null &&
                                      member.customRoleTitle!.trim().isNotEmpty)) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.pastelYellow,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    member.displayRoleLabel,
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.pastelYellowDark),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            member.homeClub != null ? '원소속: ${member.homeClub}' : '정회원',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                          trailing: Checkbox(
                            value: isChecked,
                            activeColor: AppTheme.primaryMint,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            onChanged: (_) => onToggleMember(member.id),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 미니 급수 뱃지
  Widget _buildTierMiniBadge(Tier tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppTheme.getTierBgColor(tier),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tier.label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.getTierTextColor(tier)),
      ),
    );
  }
}

