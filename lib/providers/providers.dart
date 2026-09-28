import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/mock_data.dart';
import '../models/models.dart';
import '../services/services.dart';

final clubServiceProvider = Provider<ClubService>((ref) => ClubService());
final sessionServiceProvider = Provider<SessionService>((ref) => SessionService());
final matchGeneratorServiceProvider = Provider<MatchGeneratorService>((ref) => MatchGeneratorService());

/// 직전 세션 & 대진 설정값 자동 기억(Persistence) 로컬 저장소 키
const String kSessionPreferencesStorageKey = 'cockmatch_last_session_preferences_v1';

/// '오늘 모임 세션 & 대진 설정' 및 '[+ 새 모임 시작하기]' 직전 설정값 자동 기억 Notifier
/// - SharedPreferences와 동기화되어 세션을 시작하거나 대진 설정을 변경할 때 자동 저장
/// - [설정 초기화] 시 앱 최초 기본 권장 설정으로 즉시 복원
class SessionPreferencesNotifier extends Notifier<SessionPreferences> {
  @override
  SessionPreferences build() {
    _loadFromStorageAsync();
    return SessionPreferences.defaults();
  }

  Future<void> _loadFromStorageAsync() async {
    await loadFromSharedPreferences();
  }

  /// SharedPreferences에서 저장된 직전 설정값 불러오기
  Future<void> loadFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(kSessionPreferencesStorageKey);
      if (rawJson != null && rawJson.trim().isNotEmpty) {
        state = SessionPreferences.fromJson(rawJson);
      }
    } catch (_) {
      // 테스트 환경 등에서 플러그인 채널 미초기화 시 메모리 상태 유지
    }
  }

  Future<void> _persistToStorage(SessionPreferences prefsState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSessionPreferencesStorageKey, prefsState.toJson());
    } catch (_) {
      // 테스트 환경 등에서 플러그인 채널 예외 무시
    }
  }

  /// '오늘 모임 세션 & 대진 설정' 바텀시트에서 선택한 모든 대진 설정값 자동 저장
  Future<void> saveSessionSettings({
    required MatchFormat matchFormat,
    required int courtCount,
    required int startCourtNumber,
    required MatchMode matchMode,
    required MatchType matchType,
    required PartnerMode partnerMode,
    List<List<String>> fixedPairs = const [],
  }) async {
    final updated = state.copyWith(
      matchFormat: matchFormat,
      courtCount: courtCount.clamp(1, 15),
      startCourtNumber: startCourtNumber.clamp(1, 50),
      matchMode: matchMode,
      matchType: matchType,
      partnerMode: partnerMode,
      fixedPairs: fixedPairs.map((p) => List<String>.from(p)).toList(),
      hasSavedPreferences: true,
    );
    state = updated;
    await _persistToStorage(updated);
  }

  /// '[+ 새 모임 시작하기]' 모달에서 선택한 모임 프리셋 및 회비 설정 자동 저장
  Future<void> saveGatheringStartSettings({
    required String titlePreset,
    required int memberFee,
    required int guestFee,
    required bool isCustomMemberFee,
    required bool isCustomGuestFee,
  }) async {
    final updated = state.copyWith(
      titlePreset: titlePreset.trim().isEmpty ? '정기 모임' : titlePreset.trim(),
      memberFee: memberFee,
      guestFee: guestFee,
      isCustomMemberFee: isCustomMemberFee,
      isCustomGuestFee: isCustomGuestFee,
      hasSavedPreferences: true,
    );
    state = updated;
    await _persistToStorage(updated);
  }

  /// [설정 초기화]: 앱 최초 기본 권장 설정으로 즉시 리셋 및 SharedPreferences 초기화
  Future<void> resetToDefaults() async {
    final defaults = SessionPreferences.defaults();
    state = defaults;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kSessionPreferencesStorageKey);
    } catch (_) {
      // 무시
    }
  }
}

final sessionPreferencesProvider =
    NotifierProvider<SessionPreferencesNotifier, SessionPreferences>(
  SessionPreferencesNotifier.new,
);

/// 메인 네비게이션 활성 탭 인덱스 Notifier (0: 회원명부, 1: 출석부, 2: 대진표, 3: 웹뷰어, 4: 월회비 관리)
class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => 1; // 기본(초기) 화면: 출석부 (Index 1)

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);

const String kIsProUserStorageKey = 'cockmatch_is_pro_user_v1';
const String kSessionHistoryStorageKey = 'cockmatch_session_history_v1';
const String kActiveSessionStorageKey = 'cockmatch_active_session_v1';
const String kSelectedRoundStorageKey = 'cockmatch_selected_round_v1';
const String kSessionMatchesArchiveStorageKey = 'cockmatch_matches_archive_v1';

/// PRO 유료 플랜 구독 상태 Notifier (월회비 관리 🔒 권한 가드용)
class IsProUserNotifier extends Notifier<bool> {
  bool _hasLocalMutation = false;

  @override
  bool build() {
    _loadFromStorageAsync();
    return false;
  }

  Future<void> _loadFromStorageAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(kIsProUserStorageKey);
      if (saved != null && !_hasLocalMutation) {
        state = saved;
      }
    } catch (_) {}
  }

  Future<void> setProStatus(bool isPro) async {
    _hasLocalMutation = true;
    state = isPro;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsProUserStorageKey, isPro);
    } catch (_) {}
  }

  Future<void> toggleProStatus() async {
    await setProStatus(!state);
  }
}

final isProUserProvider = NotifierProvider<IsProUserNotifier, bool>(
  IsProUserNotifier.new,
);

// ==========================================
// 1. 다중 클럽/모임 관리 (Clubs & Current Club)
// ==========================================

/// 관리 중인 클럽/모임 목록 Notifier
class ClubsNotifier extends Notifier<List<Club>> {
  @override
  List<Club> build() {
    return MockData.initialClubs;
  }

  /// 신규 클럽 생성
  Club createClub(String name, {String? description}) {
    final newClub = Club(
      id: 'club_${DateTime.now().millisecondsSinceEpoch}',
      ownerId: 'admin_1',
      clubName: name.trim(),
      description: description?.trim() ?? '신규 배드민턴 모임',
      memberCount: 0,
      createdAt: DateTime.now(),
    );
    state = [...state, newClub];
    return newClub;
  }

  /// 클럽 회원 수 동기화
  void updateMemberCount(String clubId, int count) {
    state = state.map((c) => c.id == clubId ? c.copyWith(memberCount: count) : c).toList();
  }
}

final clubsProvider = NotifierProvider<ClubsNotifier, List<Club>>(
  ClubsNotifier.new,
);

/// 현재 활성화된 클럽 고유 ID Notifier
class CurrentClubIdNotifier extends Notifier<String> {
  @override
  String build() {
    return 'club_mega'; // 기본 활성 클럽: 메가 배드민턴 클럽
  }

  /// 클럽 원클릭 전환
  void switchClub(String clubId) {
    if (state == clubId) return;
    state = clubId;

    // 클럽 전환 시 해당 클럽의 세션, 출석체크, 대진표 데이터로 즉시 동기화 전환!
    ref.read(sessionProvider.notifier).loadSessionForClub(clubId);
    ref.read(attendanceSelectionProvider.notifier).resetForCurrentClub();
    ref.read(matchesProvider.notifier).loadMatchesForClub(clubId);
  }
}

final currentClubIdProvider = NotifierProvider<CurrentClubIdNotifier, String>(
  CurrentClubIdNotifier.new,
);

/// 현재 선택된 클럽 정보 Provider
final currentClubProvider = Provider<Club>((ref) {
  final clubs = ref.watch(clubsProvider);
  final currentId = ref.watch(currentClubIdProvider);
  return clubs.firstWhere(
    (c) => c.id == currentId,
    orElse: () => clubs.first,
  );
});

// ==========================================
// 2. 회원 풀 관리 (전체 및 클럽별 분리)
// ==========================================

/// 전체 회원 저장소 Notifier
class MembersNotifier extends Notifier<List<Member>> {
  @override
  List<Member> build() {
    return MockData.initialMembers;
  }

  void addMember(Member member) {
    final currentClubId = ref.read(currentClubIdProvider);
    final memberWithClub = member.clubId == null
        ? member.copyWith(clubId: currentClubId)
        : member;
    state = [memberWithClub, ...state];
    if (memberWithClub.customRoleTitle != null &&
        memberWithClub.customRoleTitle!.trim().isNotEmpty) {
      ref
          .read(customRoleTitlesProvider.notifier)
          .addCustomRoleTitle(memberWithClub.customRoleTitle!);
    }
    _syncClubMemberCount(memberWithClub.clubId ?? currentClubId);
  }

  void addBatch(List<Member> newMembers) {
    final currentClubId = ref.read(currentClubIdProvider);
    final withClub = newMembers.map((m) {
      return m.clubId == null ? m.copyWith(clubId: currentClubId) : m;
    }).toList();
    state = [...withClub, ...state];
    _syncClubMemberCount(currentClubId);
  }

  /// CSV 일괄 업로드(Import) 반영 (중복 전화번호 처리 옵션: 기존 정보 덮어쓰기 / 건너뛰기 지원)
  ({int addedCount, int updatedCount, int skippedCount}) importCsvRows({
    required CsvImportAnalysisResult analysisResult,
    required CsvDuplicatePolicy duplicatePolicy,
    String? clubId,
  }) {
    final String targetClubId = clubId ?? ref.read(currentClubIdProvider);
    final updatedState = List<Member>.from(state);
    int addedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    for (final row in analysisResult.validRows) {
      final candidate = row.member!.copyWith(clubId: targetClubId);
      final normPhone = ClubService.normalizePhoneNumber(candidate.phoneNumber);

      // 현재 클럽 내 동일 전화번호 회원 검색
      final existingIdx = (normPhone != null && normPhone.isNotEmpty)
          ? updatedState.indexWhere(
              (m) =>
                  m.clubId == targetClubId &&
                  !m.isGuest &&
                  ClubService.normalizePhoneNumber(m.phoneNumber) == normPhone,
            )
          : -1;

      if (existingIdx >= 0) {
        if (duplicatePolicy == CsvDuplicatePolicy.overwrite) {
          final existing = updatedState[existingIdx];
          updatedState[existingIdx] = existing.copyWith(
            name: candidate.name,
            gender: candidate.gender,
            tier: candidate.tier,
            role: candidate.role,
            phoneNumber: normPhone,
            memo: candidate.memo ?? existing.memo,
            updatedAt: DateTime.now(),
          );
          updatedCount++;
        } else {
          skippedCount++;
        }
      } else {
        updatedState.insert(0, candidate.copyWith(phoneNumber: normPhone));
        addedCount++;
      }
    }

    state = updatedState;
    _syncClubMemberCount(targetClubId);
    return (
      addedCount: addedCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
    );
  }

  void updateMember(Member updated) {
    state = state.map((m) => m.id == updated.id ? updated : m).toList();
    if (updated.customRoleTitle != null && updated.customRoleTitle!.trim().isNotEmpty) {
      ref.read(customRoleTitlesProvider.notifier).addCustomRoleTitle(updated.customRoleTitle!);
    }
    // 휴면 상태인 회원은 당일 모임 출석부 목록에서 기본적으로 제외 및 '휴회 면제' 자동 연동
    if (updated.status == MemberStatus.resting) {
      ref.read(attendanceSelectionProvider.notifier).removeMember(updated.id);
      ref.read(sessionProvider.notifier).removeAttendee(updated.id);
      ref.read(sessionProvider.notifier).updateAttendeeFeeStatus(updated.id, FeeStatus.exempt);
    } else if (updated.feePolicy == FeePolicyType.exempt) {
      ref.read(sessionProvider.notifier).updateAttendeeFeeStatus(updated.id, FeeStatus.exempt);
    }
  }

  void deleteMember(String id) {
    final member = state.firstWhere((m) => m.id == id, orElse: () => state.first);
    state = state.where((m) => m.id != id).toList();
    if (member.clubId != null) {
      _syncClubMemberCount(member.clubId!);
    }
  }

  void toggleFeePaid(String id) {
    state = state.map((m) {
      if (m.id == id) {
        final nextStatus = switch (m.feeStatus) {
          FeeStatus.paid => FeeStatus.unpaid,
          FeeStatus.unpaid => FeeStatus.exempt,
          FeeStatus.exempt => FeeStatus.paid,
        };
        ref.read(sessionProvider.notifier).updateAttendeeFeeStatus(id, nextStatus);
        return m.copyWith(feeStatus: nextStatus);
      }
      return m;
    }).toList();
  }

  void updateFeeStatus(String id, FeeStatus status) {
    state = state.map((m) {
      if (m.id == id) {
        return m.copyWith(feeStatus: status);
      }
      return m;
    }).toList();
    ref.read(sessionProvider.notifier).updateAttendeeFeeStatus(id, status);
  }

  void _syncClubMemberCount(String clubId) {
    final count = state.where((m) => m.clubId == clubId && !m.isGuest).length;
    ref.read(clubsProvider.notifier).updateMemberCount(clubId, count);
  }
}

final membersProvider = NotifierProvider<MembersNotifier, List<Member>>(
  MembersNotifier.new,
);

/// [회원 등급 / 직책] 커스텀 직접 추가 목록 영구 저장소 Notifier
/// - [+ 직책/등급 직접 추가]를 통해 입력한 명칭(예: 자문위원, 고문, 학생회원 등)을 저장 및 유지
class CustomRoleTitlesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    return const ['자문위원', '고문', '학생회원'];
  }

  void addCustomRoleTitle(String rawTitle) {
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty) return;
    // 기본 직책과 중복되지 않고 아직 등록되지 않은 명칭이면 즉시 추가
    final isStandard = MemberRole.values.any((r) => r.label == trimmed);
    if (!isStandard && !state.contains(trimmed)) {
      state = [...state, trimmed];
    }
  }
}

final customRoleTitlesProvider = NotifierProvider<CustomRoleTitlesNotifier, List<String>>(
  CustomRoleTitlesNotifier.new,
);

/// 현재 활성화된 클럽에 소속된 순수 등록 회원 목록 Provider (게스트 제외, 클럽 간 데이터 격리)
final currentClubMembersProvider = Provider<List<Member>>((ref) {
  final allMembers = ref.watch(membersProvider);
  final currentClubId = ref.watch(currentClubIdProvider);
  return allMembers.where((m) => m.clubId == currentClubId && !m.isGuest).toList();
});

/// 회원 필터 관리 Notifier
class MemberFilterNotifier extends Notifier<MemberFilter> {
  @override
  MemberFilter build() => MemberFilter.initial();

  void update(MemberFilter Function(MemberFilter prev) updater) {
    state = updater(state);
  }

  void setFilter(MemberFilter filter) {
    state = filter;
  }

  void reset() {
    state = MemberFilter.initial();
  }
}

final memberFilterProvider = NotifierProvider<MemberFilterNotifier, MemberFilter>(
  MemberFilterNotifier.new,
);

/// 필터링된 회원 목록 셀렉터 Provider (현재 활성 클럽 회원 풀 기준)
final filteredMembersProvider = Provider<List<Member>>((ref) {
  final currentMembers = ref.watch(currentClubMembersProvider);
  final filter = ref.watch(memberFilterProvider);
  final clubService = ref.watch(clubServiceProvider);
  return clubService.filterMembers(currentMembers, filter);
});

/// 출석 체크 선택된 회원 ID 목록 Notifier (현재 클럽 기준, 휴면 회원은 기본 제외)
class AttendanceSelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final currentMembers = ref.read(currentClubMembersProvider);
    return currentMembers.where((m) => m.status == MemberStatus.active).map((m) => m.id).toSet();
  }

  /// 클럽 전환 시 해당 클럽의 활성 회원으로 자동 재설정 (휴면 회원 제외)
  void resetForCurrentClub() {
    final currentMembers = ref.read(currentClubMembersProvider);
    state = currentMembers.where((m) => m.status == MemberStatus.active).map((m) => m.id).toSet();
  }

  void removeMember(String memberId) {
    if (!state.contains(memberId)) return;
    final updated = Set<String>.from(state)..remove(memberId);
    state = updated;
  }

  void toggle(String memberId) {
    final updated = Set<String>.from(state);
    if (updated.contains(memberId)) {
      updated.remove(memberId);
    } else {
      updated.add(memberId);
    }
    state = updated;
  }

  void selectAll(List<Member> members) {
    state = members.where((m) => m.status == MemberStatus.active).map((m) => m.id).toSet();
  }

  void clearAll() {
    state = {};
  }
}

final attendanceSelectionProvider = NotifierProvider<AttendanceSelectionNotifier, Set<String>>(
  AttendanceSelectionNotifier.new,
);

// ==========================================
// 3. 모임 세션 및 아카이빙(히스토리) 관리
// ==========================================

/// 전체 모임 세션 아카이브 저장소 Notifier (진행 모임 + 지난 모임 영구 보존)
/// - 모임이 종료(완료)되어도 절대 자동 삭제되지 않으며,
///   총무가 [모임 기록 영구 삭제]를 수동 실행하고 확인 팝업을 거칠 때만 삭제됨.
class SessionHistoryNotifier extends Notifier<List<GameSession>> {
  bool _hasLocalMutation = false;

  @override
  List<GameSession> build() {
    _loadFromStorageAsync();
    return List<GameSession>.from(MockData.initialArchivedSessions);
  }

  Future<void> _loadFromStorageAsync() async {
    await restoreFromStorage(respectLocalMutation: true);
  }

  Future<void> restoreFromStorage({bool respectLocalMutation = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kSessionHistoryStorageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        if (respectLocalMutation && _hasLocalMutation) return;
        final decoded = jsonDecode(raw) as List<dynamic>;
        final loaded = <GameSession>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final id = (item['id'] as String?) ?? '';
            if (id.isNotEmpty) {
              loaded.add(GameSession.fromMap(item, id: id));
            }
          }
        }
        if (loaded.isNotEmpty) {
          state = loaded;
        }
      }
    } catch (_) {}
  }

  Future<void> _persistToStorage(List<GameSession> sessions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = sessions.map((s) => {'id': s.id, ...s.toMap()}).toList();
      await prefs.setString(kSessionHistoryStorageKey, jsonEncode(list));
    } catch (_) {}
  }

  /// 세션 추가 또는 최신 상태 동기화
  void upsertSession(GameSession session) {
    _hasLocalMutation = true;
    final exists = state.any((s) => s.id == session.id);
    if (exists) {
      state = state.map((s) => s.id == session.id ? session : s).toList();
    } else {
      state = [session, ...state];
    }
    _persistToStorage(state);
  }

  /// [모임 기록 영구 삭제] 수동 실행 시에만 아카이브에서 영구 제거
  void removeSessionPermanently(String sessionId) {
    _hasLocalMutation = true;
    state = state.where((s) => s.id != sessionId).toList();
    _persistToStorage(state);
  }
}

final sessionHistoryProvider = NotifierProvider<SessionHistoryNotifier, List<GameSession>>(
  SessionHistoryNotifier.new,
);

/// 현재 선택된 클럽의 [진행 모임] 목록 Provider
final currentClubOngoingSessionsProvider = Provider<List<GameSession>>((ref) {
  final history = ref.watch(sessionHistoryProvider);
  final clubId = ref.watch(currentClubIdProvider);
  return history.where((s) => s.clubId == clubId && !s.isCompleted).toList();
});

/// 현재 선택된 클럽의 [지난 모임] (종료/보관된 아카이브) 목록 Provider
final currentClubArchivedSessionsProvider = Provider<List<GameSession>>((ref) {
  final history = ref.watch(sessionHistoryProvider);
  final clubId = ref.watch(currentClubIdProvider);
  return history.where((s) => s.clubId == clubId && s.isCompleted).toList();
});

/// 현재 열려 있는 게임 세션 상태 관리 Notifier (null은 모임 목록/미선택 상태)
class SessionNotifier extends Notifier<GameSession?> {
  final Map<String, GameSession?> _clubSessionsCache = {};
  bool _hasLocalMutation = false;

  @override
  GameSession? build() {
    _loadFromStorageAsync();
    return null;
  }

  Future<void> _loadFromStorageAsync() async {
    await restoreFromStorage(respectLocalMutation: true);
  }

  /// 로컬 스토리지(SharedPreferences)에서 진행 중인 활성 세션 복원 (새로고침 자동 복구 지원)
  Future<void> restoreFromStorage({bool respectLocalMutation = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kActiveSessionStorageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        if (respectLocalMutation && _hasLocalMutation) return;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final id = (decoded['id'] as String?) ?? '';
        if (id.isNotEmpty) {
          final restored = GameSession.fromMap(decoded, id: id);
          _clubSessionsCache[restored.clubId] = restored;
          state = restored;
          await ref.read(matchesProvider.notifier).restoreFromStorage(
                respectLocalMutation: respectLocalMutation,
                targetSessionId: restored.id,
                targetClubId: restored.clubId,
              );
        }
      }
    } catch (_) {}
  }

  Future<void> _persistActiveSession(GameSession? session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (session == null) {
        await prefs.remove(kActiveSessionStorageKey);
      } else {
        await prefs.setString(
          kActiveSessionStorageKey,
          jsonEncode({'id': session.id, ...session.toMap()}),
        );
      }
    } catch (_) {}
  }

  @override
  bool updateShouldNotify(GameSession? previous, GameSession? next) {
    return !identical(previous, next);
  }

  void _syncToHistory(GameSession? updated) {
    _hasLocalMutation = true;
    if (updated != null) {
      _clubSessionsCache[updated.clubId] = updated;
      ref.read(sessionHistoryProvider.notifier).upsertSession(updated);
    }
    _persistActiveSession(updated);
  }

  /// 다른 클럽으로 세션 전환
  void loadSessionForClub(String clubId) {
    _hasLocalMutation = true;
    final prevClubId = ref.read(currentClubIdProvider);
    if (state != null) {
      _clubSessionsCache[prevClubId] = state;
    }
    state = _clubSessionsCache[clubId];
    _persistActiveSession(state);
  }

  /// 모임 목록에서 특정 모임([진행 모임] 또는 [지난 모임]) 선택하여 열기
  void selectSession(GameSession targetSession) {
    _hasLocalMutation = true;
    if (targetSession.clubId != ref.read(currentClubIdProvider)) {
      ref.read(currentClubIdProvider.notifier).switchClub(targetSession.clubId);
    }
    _clubSessionsCache[targetSession.clubId] = targetSession;
    state = targetSession;
    _persistActiveSession(targetSession);
    ref.read(matchesProvider.notifier).loadMatchesForSession(targetSession.id, clubId: targetSession.clubId);
  }

  /// 현재 조회 중인 모임 화면을 닫고 모임 목록 화면으로 복귀 (데이터는 100% 보존)
  void closeSessionView() {
    _hasLocalMutation = true;
    final currentClubId = ref.read(currentClubIdProvider);
    if (state != null) {
      _syncToHistory(state);
    }
    _clubSessionsCache[currentClubId] = null;
    state = null;
    _persistActiveSession(null);
  }

  /// 3단계 생성 플로우를 통해 새 모임 세션 시작 (직전에 저장된 대진 설정값 자동 반영)
  void createSession({
    required String clubId,
    required String title,
    required int memberFee,
    required int guestFee,
    required List<String> attendeeIds,
    int? courtCount,
    int? startCourtNumber,
    MatchMode? matchMode,
    MatchFormat? matchFormat,
    MatchType? matchType,
    PartnerMode? partnerMode,
    List<List<String>>? fixedPairs,
  }) {
    _hasLocalMutation = true;
    final savedPrefs = ref.read(sessionPreferencesProvider);
    final recommendedCourts = (attendeeIds.length ~/ 4).clamp(1, 15);
    final effectiveCourtCount =
        (courtCount ?? savedPrefs.courtCount ?? recommendedCourts).clamp(1, 15);
    final effectiveStartCourtNumber =
        (startCourtNumber ?? savedPrefs.startCourtNumber).clamp(1, 50);
    final effectiveMatchMode = matchMode ?? savedPrefs.matchMode;
    final effectiveMatchFormat = matchFormat ?? savedPrefs.matchFormat;
    final effectiveMatchType = matchType ?? savedPrefs.matchType;
    final effectivePartnerMode = partnerMode ?? savedPrefs.partnerMode;
    final attendeeSet = attendeeIds.toSet();
    final effectiveFixedPairs = (fixedPairs ?? savedPrefs.fixedPairs)
        .where((p) => p.length == 2 && attendeeSet.contains(p[0]) && attendeeSet.contains(p[1]))
        .map((p) => [p[0], p[1]])
        .toList();

    final allMembers = ref.read(membersProvider);
    final Map<String, AttendanceStatus> statusMap = {};
    final Map<String, FeeStatus> feeMap = {};
    for (final id in attendeeIds) {
      statusMap[id] = AttendanceStatus.active;
      final member = allMembers.where((m) => m.id == id).firstOrNull;
      if (member != null) {
        feeMap[id] = member.feeStatus;
      }
    }

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final newSession = GameSession(
      id: 'session_${clubId}_${now.millisecondsSinceEpoch}',
      clubId: clubId,
      title: title,
      sessionDate: dateStr,
      courtCount: effectiveCourtCount,
      startCourtNumber: effectiveStartCourtNumber,
      memberFee: memberFee,
      guestFee: guestFee,
      matchFormat: effectiveMatchFormat,
      matchType: effectiveMatchType,
      matchMode: effectiveMatchMode,
      partnerMode: effectivePartnerMode,
      fixedPairs: effectiveFixedPairs,
      attendees: attendeeIds,
      attendeeStatusMap: statusMap,
      attendeeFeeStatusMap: feeMap,
      currentRound: 1,
      isCompleted: false,
      createdAt: now,
    );

    _clubSessionsCache[clubId] = newSession;
    state = newSession;
    _syncToHistory(newSession);
    ref.read(matchesProvider.notifier).loadMatchesForSession(newSession.id, clubId: clubId);
  }

  /// 모임 세션 종료 (아카이빙 보관 정책 적용: 데이터를 절대 삭제하지 않고 [지난 모임]으로 전환)
  void endSession() {
    _hasLocalMutation = true;
    final current = state;
    final currentClubId = ref.read(currentClubIdProvider);
    if (current != null) {
      final allMembers = ref.read(membersProvider);
      final Map<String, FeeStatus> feeSnapshot = Map<String, FeeStatus>.from(current.attendeeFeeStatusMap);
      for (final id in current.attendees) {
        final member = allMembers.where((m) => m.id == id).firstOrNull;
        if (member != null) {
          feeSnapshot[id] = current.getAttendeeFeeStatus(member);
        }
      }

      final completedSession = current.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        attendeeFeeStatusMap: feeSnapshot,
      );
      ref.read(sessionHistoryProvider.notifier).upsertSession(completedSession);
    }
    _clubSessionsCache[currentClubId] = null;
    state = null;
    _persistActiveSession(null);
  }

  /// [모임 기록 영구 삭제] 총무가 수동으로 확인 팝업을 거쳤을 때만 호출되는 영구 삭제 메서드
  void permanentlyDeleteSession(String sessionId) {
    _hasLocalMutation = true;
    ref.read(sessionHistoryProvider.notifier).removeSessionPermanently(sessionId);
    ref.read(matchesProvider.notifier).deleteMatchesForSession(sessionId);

    _clubSessionsCache.removeWhere((_, s) => s?.id == sessionId);
    if (state?.id == sessionId) {
      state = null;
      _persistActiveSession(null);
    }
  }

  void updateAttendeeFeeStatus(String memberId, FeeStatus feeStatus) {
    if (state == null) return;
    final updatedFeeMap = Map<String, FeeStatus>.from(state!.attendeeFeeStatusMap);
    updatedFeeMap[memberId] = feeStatus;
    state = state!.copyWith(attendeeFeeStatusMap: updatedFeeMap);
    _syncToHistory(state);
  }

  void updateTitle(String title) {
    if (state == null) return;
    state = state!.copyWith(title: title);
    _syncToHistory(state);
  }

  void updateFees({int? memberFee, int? guestFee}) {
    if (state == null) return;
    state = state!.copyWith(
      memberFee: memberFee ?? state!.memberFee,
      guestFee: guestFee ?? state!.guestFee,
    );
    _syncToHistory(state);
  }

  void updateCourtCount(int count) {
    if (state == null) return;
    state = state!.copyWith(courtCount: count.clamp(1, 15));
    _syncToHistory(state);
  }

  void updateStartCourtNumber(int start) {
    if (state == null) return;
    state = state!.copyWith(startCourtNumber: start.clamp(1, 99));
    _syncToHistory(state);
  }

  void updateMatchMode(MatchMode mode) {
    if (state == null) return;
    state = state!.copyWith(matchMode: mode);
    _syncToHistory(state);
  }

  void updateMatchType(MatchType type) {
    if (state == null) return;
    state = state!.copyWith(matchType: type);
    _syncToHistory(state);
  }

  void updateMatchFormat(MatchFormat format) {
    if (state == null) return;
    state = state!.copyWith(matchFormat: format);
    _syncToHistory(state);
  }

  void updateCurrentRound(int round) {
    if (state == null) return;
    state = state!.copyWith(currentRound: round.clamp(1, 99));
    _syncToHistory(state);
  }

  /// 현재 세션의 대진 설정값을 앱 최초 기본 권장 설정으로 초기화
  void resetBracketSettingsToDefault({int? recommendedCourts}) {
    if (state == null) return;
    final defaultCourts =
        recommendedCourts ?? (state!.activeAttendees.length ~/ 4).clamp(1, 15);
    state = state!.copyWith(
      courtCount: defaultCourts,
      startCourtNumber: 1,
      matchFormat: MatchFormat.regular,
      matchMode: MatchMode.tiered,
      matchType: MatchType.normal,
      partnerMode: PartnerMode.rotation,
      fixedPairs: const [],
    );
    _syncToHistory(state);
  }

  void updateAttendeeStatus(String memberId, AttendanceStatus status) {
    if (state == null) return;
    final updatedMap = Map<String, AttendanceStatus>.from(state!.attendeeStatusMap);
    for (final id in state!.effectiveAttendees) {
      updatedMap.putIfAbsent(id, () => state!.getAttendeeStatus(id));
    }
    updatedMap[memberId] = status;
    state = state!.copyWith(attendeeStatusMap: updatedMap);
    _syncToHistory(state);
  }

  void addAttendee(String memberId, {AttendanceStatus status = AttendanceStatus.active}) {
    if (state == null) return;
    final updatedList = state!.attendees.contains(memberId)
        ? List<String>.from(state!.attendees)
        : [...state!.attendees, memberId];
    final updatedMap = Map<String, AttendanceStatus>.from(state!.attendeeStatusMap);
    for (final id in state!.effectiveAttendees) {
      updatedMap.putIfAbsent(id, () => state!.getAttendeeStatus(id));
    }
    updatedMap[memberId] = status;
    state = state!.copyWith(
      attendees: updatedList,
      attendeeStatusMap: updatedMap,
    );
    _syncToHistory(state);
  }

  void addAttendees(List<String> memberIds) {
    if (state == null) return;
    final updatedList = List<String>.from(state!.attendees);
    final updatedMap = Map<String, AttendanceStatus>.from(state!.attendeeStatusMap);
    for (final id in state!.effectiveAttendees) {
      updatedMap.putIfAbsent(id, () => state!.getAttendeeStatus(id));
    }
    for (final id in memberIds) {
      if (!updatedList.contains(id)) {
        updatedList.add(id);
        updatedMap[id] = AttendanceStatus.active;
      }
    }
    state = state!.copyWith(
      attendees: updatedList,
      attendeeStatusMap: updatedMap,
    );
    _syncToHistory(state);
  }

  void removeAttendee(String memberId) {
    if (state == null) return;
    final updatedList = state!.attendees.where((id) => id != memberId).toList();
    final updatedMap = Map<String, AttendanceStatus>.from(state!.attendeeStatusMap);
    updatedMap.remove(memberId);
    state = state!.copyWith(
      attendees: updatedList,
      attendeeStatusMap: updatedMap,
    );
    _syncToHistory(state);
  }

  void startNewSessionWithAttendees({
    required List<String> attendeeIds,
    required int courtCount,
    int startCourtNumber = 1,
    required MatchMode matchMode,
    MatchFormat matchFormat = MatchFormat.regular,
    MatchType matchType = MatchType.normal,
    PartnerMode partnerMode = PartnerMode.rotation,
    List<List<String>> fixedPairs = const [],
  }) {
    if (state == null) return;
    final Map<String, AttendanceStatus> statusMap = {};
    for (final id in attendeeIds) {
      statusMap[id] = state!.attendeeStatusMap[id] ?? AttendanceStatus.active;
    }

    state = state!.copyWith(
      attendees: attendeeIds,
      attendeeStatusMap: statusMap,
      courtCount: courtCount,
      startCourtNumber: startCourtNumber,
      matchMode: matchMode,
      matchFormat: matchFormat,
      matchType: matchType,
      partnerMode: partnerMode,
      fixedPairs: fixedPairs,
      currentRound: 1,
    );
    _syncToHistory(state);
  }

  void toggleAttendee(String memberId) {
    if (state == null) return;
    final attendees = List<String>.from(state!.attendees);
    final updatedMap = Map<String, AttendanceStatus>.from(state!.attendeeStatusMap);

    if (attendees.contains(memberId)) {
      attendees.remove(memberId);
      updatedMap.remove(memberId);
    } else {
      attendees.add(memberId);
      updatedMap[memberId] = AttendanceStatus.active;
    }

    state = state!.copyWith(
      attendees: attendees,
      attendeeStatusMap: updatedMap,
    );
    _syncToHistory(state);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, GameSession?>(
  SessionNotifier.new,
);

class SelectedRoundNotifier extends Notifier<int> {
  bool _hasLocalMutation = false;

  @override
  int build() {
    _loadFromStorageAsync();
    return 1;
  }

  Future<void> _loadFromStorageAsync() async {
    await restoreFromStorage(respectLocalMutation: true);
  }

  Future<void> restoreFromStorage({bool respectLocalMutation = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(kSelectedRoundStorageKey);
      if (saved != null && saved >= 1) {
        if (respectLocalMutation && _hasLocalMutation) return;
        state = saved;
      }
    } catch (_) {}
  }

  void setRound(int r) {
    _hasLocalMutation = true;
    state = r;
    ref.read(sessionProvider.notifier).updateCurrentRound(r);
    _persistRound(r);
  }

  Future<void> _persistRound(int r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kSelectedRoundStorageKey, r);
    } catch (_) {}
  }
}

final selectedRoundProvider = NotifierProvider<SelectedRoundNotifier, int>(
  SelectedRoundNotifier.new,
);

// ==========================================
// 4. 경기 목록 관리 (세션별 & 클럽별 영구 아카이브 캐시 + 로컬 스토리지 자동 복구)
// ==========================================

/// 경기 목록 관리 Notifier
class MatchesNotifier extends Notifier<List<GameMatch>> {
  final Map<String, List<GameMatch>> _clubMatchesCache = {};
  final Map<String, List<GameMatch>> _sessionMatchesArchive = {
    for (final entry in MockData.initialArchivedMatches.entries)
      entry.key: List<GameMatch>.from(entry.value),
  };
  bool _hasLocalMutation = false;

  @override
  List<GameMatch> build() {
    _loadFromStorageAsync();
    return [];
  }

  Future<void> _loadFromStorageAsync() async {
    await restoreFromStorage(respectLocalMutation: true);
  }

  /// 로컬 스토리지(SharedPreferences)에서 경기 대진표/점수/상태 복원 (모바일 새로고침 100% 복구)
  Future<void> restoreFromStorage({
    bool respectLocalMutation = false,
    String? targetSessionId,
    String? targetClubId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kSessionMatchesArchiveStorageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is List) {
            final parsedList = <GameMatch>[];
            for (final item in (entry.value as List)) {
              if (item is Map<String, dynamic>) {
                final id = (item['id'] as String?) ?? '';
                if (id.isNotEmpty) {
                  parsedList.add(GameMatch.fromMap(item, id: id));
                }
              }
            }
            if (!respectLocalMutation || !_hasLocalMutation) {
              _sessionMatchesArchive[entry.key] = parsedList;
            }
          }
        }
        if (respectLocalMutation && _hasLocalMutation) return;
        final activeSessionId = targetSessionId ?? ref.read(sessionProvider)?.id;
        final String activeClubId =
            targetClubId ?? (ref.read(currentClubIdProvider) as String? ?? 'club_mega');
        if (activeSessionId != null && _sessionMatchesArchive.containsKey(activeSessionId)) {
          final restored = List<GameMatch>.from(_sessionMatchesArchive[activeSessionId]!);
          _clubMatchesCache[activeClubId] = restored;
          state = restored;
        }
      }
    } catch (_) {}
  }

  Future<void> _persistMatchesArchive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = <String, dynamic>{};
      for (final entry in _sessionMatchesArchive.entries) {
        serializable[entry.key] =
            entry.value.map((m) => {'id': m.id, ...m.toMap()}).toList();
      }
      await prefs.setString(kSessionMatchesArchiveStorageKey, jsonEncode(serializable));
    } catch (_) {}
  }

  void _saveCurrentSessionMatches(List<GameMatch> matches) {
    _hasLocalMutation = true;
    final currentSession = ref.read(sessionProvider);
    final currentClubId = ref.read(currentClubIdProvider);
    _clubMatchesCache[currentClubId] = matches;
    if (currentSession != null) {
      _sessionMatchesArchive[currentSession.id] = matches;
    }
    _persistMatchesArchive();
  }

  /// 특정 세션(진행 모임 또는 지난 모임)의 전체 경기 전적 조회
  List<GameMatch> getMatchesForSession(String sessionId) {
    final currentSession = ref.read(sessionProvider);
    if (currentSession != null && currentSession.id == sessionId && state.isNotEmpty) {
      return state;
    }
    return _sessionMatchesArchive[sessionId] ?? const [];
  }

  /// 특정 세션 선택 시 해당 세션의 경기 기록 로드
  void loadMatchesForSession(String sessionId, {String? clubId}) {
    _hasLocalMutation = true;
    final loaded = _sessionMatchesArchive[sessionId] ?? const <GameMatch>[];
    state = List<GameMatch>.from(loaded);
    if (clubId != null) {
      _clubMatchesCache[clubId] = state;
    }
    final activeSession = ref.read(sessionProvider);
    final initialRound = (activeSession != null && activeSession.id == sessionId)
        ? activeSession.currentRound
        : 1;
    ref.read(selectedRoundProvider.notifier).setRound(initialRound);
  }

  /// [모임 기록 영구 삭제] 시 해당 세션의 경기 기록도 함께 삭제
  void deleteMatchesForSession(String sessionId) {
    _hasLocalMutation = true;
    _sessionMatchesArchive.remove(sessionId);
    final currentSession = ref.read(sessionProvider);
    if (currentSession?.id == sessionId) {
      state = [];
    }
    _persistMatchesArchive();
  }

  /// 클럽 전환 시 해당 클럽의 대진표로 스위치
  void loadMatchesForClub(String clubId) {
    _hasLocalMutation = true;
    final currentSession = ref.read(sessionProvider);
    if (currentSession != null) {
      _sessionMatchesArchive[currentSession.id] = state;
      _clubMatchesCache[currentSession.clubId] = state;
    }

    if (currentSession != null && currentSession.clubId == clubId) {
      state = _sessionMatchesArchive[currentSession.id] ?? _clubMatchesCache[clubId] ?? [];
    } else if (_clubMatchesCache.containsKey(clubId) && _clubMatchesCache[clubId]!.isNotEmpty) {
      state = _clubMatchesCache[clubId]!;
    } else {
      state = [];
    }

    ref.read(selectedRoundProvider.notifier).setRound(1);
  }

  /// 참석자 명단 및 코트 설정으로 새 세션 시작 및 1라운드 대진표 생성
  void startNewSessionAndGenerate({
    required List<String> attendeeIds,
    required int courtCount,
    int startCourtNumber = 1,
    required MatchMode matchMode,
    MatchFormat matchFormat = MatchFormat.regular,
    MatchType matchType = MatchType.normal,
    PartnerMode partnerMode = PartnerMode.rotation,
    List<List<String>> fixedPairs = const [],
  }) {
    final currentSession = ref.read(sessionProvider);
    if (currentSession == null) return;

    // 0. 직전 세션 & 대진 설정값을 로컬 저장소(SharedPreferences)에 자동 저장
    ref.read(sessionPreferencesProvider.notifier).saveSessionSettings(
          matchFormat: matchFormat,
          courtCount: courtCount,
          startCourtNumber: startCourtNumber,
          matchMode: matchMode,
          matchType: matchType,
          partnerMode: partnerMode,
          fixedPairs: fixedPairs,
        );

    // 1. 세션 상태 업데이트
    ref.read(sessionProvider.notifier).startNewSessionWithAttendees(
          attendeeIds: attendeeIds,
          courtCount: courtCount,
          startCourtNumber: startCourtNumber,
          matchMode: matchMode,
          matchFormat: matchFormat,
          matchType: matchType,
          partnerMode: partnerMode,
          fixedPairs: fixedPairs,
        );

    final updatedSession = ref.read(sessionProvider)!;
    final members = ref.read(membersProvider);
    final generator = ref.read(matchGeneratorServiceProvider);

    // 2. 1라운드 대진표 생성
    final round1Matches = generator.generateRoundMatches(
      session: updatedSession,
      allMembers: members,
      existingMatches: [],
      targetRound: 1,
    );

    state = round1Matches;
    _saveCurrentSessionMatches(round1Matches);
    ref.read(selectedRoundProvider.notifier).setRound(1);

    // 3. 대진표 화면(Tab 2)으로 즉시 화면 전환
    ref.read(currentTabProvider.notifier).setTab(2);
  }

  /// 특정 라운드 대진표 자동 생성
  /// - 이미 완료(isFinished)되었거나 진행 중(playing / 점수 입력됨)인 경기는 절대 초기화되지 않고 완전 고정(Lock) 처리
  /// - 현재 출석부의 출전 가능 인원(휴식/조퇴 제외, 신규 게스트 포함)을 실시간 감지하여 반영
  void generateMatchesForRound(int targetRound) {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final members = ref.read(membersProvider);
    final generator = ref.read(matchGeneratorServiceProvider);

    final previousMatches = state.where((m) => m.round < targetRound).toList();
    final lockedInTargetRound = state
        .where(
          (m) =>
              m.round == targetRound &&
              (m.isFinished ||
                  m.status == MatchStatus.playing ||
                  m.scoreA > 0 ||
                  m.scoreB > 0),
        )
        .toList();

    if (lockedInTargetRound.isEmpty) {
      final newMatches = generator.generateRoundMatches(
        session: session,
        allMembers: members,
        existingMatches: previousMatches,
        targetRound: targetRound,
      );

      state = [
        ...state.where((m) => m.round != targetRound),
        ...newMatches,
      ];
      _saveCurrentSessionMatches(state);
      ref.read(selectedRoundProvider.notifier).setRound(targetRound);
      return;
    }

    // 해당 라운드에 이미 완료되었거나 진행 중인 경기가 있는 경우:
    // 완료/진행 중 코트는 완전 고정(Lock)하고, 비어 있거나 대기 중인 코트만 현재 출석 가능 인원으로 편성
    final lockedCourts = lockedInTargetRound.map((m) => m.courtNumber).toSet();
    final lockedPlayers = lockedInTargetRound.expand((m) => m.allPlayerIds).toSet();
    final startCourt = session.startCourtNumber;
    final allCourtNumbers = List.generate(session.courtCount, (i) => startCourt + i);
    final openCourts = allCourtNumbers.where((c) => !lockedCourts.contains(c)).toList();

    final availableAttendees = session.activeAttendees
        .where((id) => !lockedPlayers.contains(id))
        .toList();

    final openCourtMatches = <GameMatch>[];
    if (openCourts.isNotEmpty && availableAttendees.length >= 4) {
      final tempSession = session.copyWith(
        attendees: availableAttendees,
        attendeeStatusMap: {
          for (final id in availableAttendees) id: AttendanceStatus.active,
        },
        courtCount: openCourts.length,
        startCourtNumber: openCourts.first,
      );
      final generated = generator.generateRoundMatches(
        session: tempSession,
        allMembers: members,
        existingMatches: [...previousMatches, ...lockedInTargetRound],
        targetRound: targetRound,
      );
      for (int i = 0; i < generated.length && i < openCourts.length; i++) {
        final assignedCourt = openCourts[i];
        openCourtMatches.add(
          generated[i].copyWith(
            id: 'smart_r${targetRound}_c${assignedCourt}_${DateTime.now().millisecondsSinceEpoch}_$i',
            courtNumber: assignedCourt,
          ),
        );
      }
    }

    state = [
      ...state.where((m) => m.round != targetRound),
      ...lockedInTargetRound,
      ...openCourtMatches,
    ];
    _saveCurrentSessionMatches(state);
    ref.read(selectedRoundProvider.notifier).setRound(targetRound);
  }

  /// [🔄 다음 라운드 스마트 편성]:
  /// - 이미 완료되었거나 진행 중인 경기 기록은 100% Lock 보존하고,
  ///   다음 라운드(또는 아직 시작되지 않은 최신 라운드)를 현재 출석 가능 인원(휴식/조퇴 제외, 신규 게스트 포함)으로 스마트 편성
  int smartGenerateNextRound() {
    if (state.isEmpty) {
      generateMatchesForRound(1);
      return 1;
    }
    final maxRound = state.map((m) => m.round).reduce((a, b) => a > b ? a : b);
    final maxRoundHasLocked = state.any(
      (m) =>
          m.round == maxRound &&
          (m.isFinished ||
              m.status == MatchStatus.playing ||
              m.scoreA > 0 ||
              m.scoreB > 0),
    );
    final targetRound = maxRoundHasLocked ? maxRound + 1 : maxRound;
    generateMatchesForRound(targetRound);
    return targetRound;
  }

  /// 코트 번호 변경 및 스왑(Swap) 처리
  /// - 빈 코트로 변경 시: 해당 매치가 새 코트 번호로 이동
  /// - 이미 다른 매치가 진행/배정 중인 코트 선택 시: 두 코트의 경기 배치가 서로 맞바꿈(Swap) 처리
  ({bool swapped, int oldCourt, int newCourt}) updateCourtNumber(
    String matchId,
    int newCourtNumber,
  ) {
    final generator = ref.read(matchGeneratorServiceProvider);
    final result = generator.changeOrSwapCourt(
      matches: state,
      matchId: matchId,
      targetCourtNumber: newCourtNumber,
    );
    state = result.updatedMatches;
    _saveCurrentSessionMatches(state);
    return (
      swapped: result.swapped,
      oldCourt: result.oldCourt,
      newCourt: result.newCourt,
    );
  }

  /// 점수 업데이트
  void updateScore(String matchId, int scoreA, int scoreB, {MatchStatus? status}) {
    state = state.map((m) {
      if (m.id == matchId) {
        return m.copyWith(
          scoreA: scoreA.clamp(0, 99),
          scoreB: scoreB.clamp(0, 99),
          status: status ?? m.status,
        );
      }
      return m;
    }).toList();
    _saveCurrentSessionMatches(state);
  }

  /// 경기 상태 토글 (pending -> playing -> finished -> pending)
  void cycleMatchStatus(String matchId) {
    state = state.map((m) {
      if (m.id == matchId) {
        MatchStatus next;
        switch (m.status) {
          case MatchStatus.pending:
            next = MatchStatus.playing;
            break;
          case MatchStatus.playing:
            next = MatchStatus.finished;
            break;
          case MatchStatus.finished:
            next = MatchStatus.pending;
            break;
        }
        return m.copyWith(status: next);
      }
      return m;
    }).toList();
    _saveCurrentSessionMatches(state);
  }

  /// 원클릭 대체 선수 치환
  void replacePlayer({
    required String matchId,
    required String outPlayerId,
    required String inPlayerId,
  }) {
    final generator = ref.read(matchGeneratorServiceProvider);
    state = state.map((m) {
      if (m.id == matchId) {
        return generator.replacePlayerInMatch(
          match: m,
          outPlayerId: outPlayerId,
          substitutePlayerId: inPlayerId,
        );
      }
      return m;
    }).toList();
    _saveCurrentSessionMatches(state);
  }

  /// 경기자 수동 교체 (Player Swap)
  bool swapPlayers({
    required String targetMatchId,
    required String targetPlayerId,
    String? otherMatchId,
    required String otherPlayerId,
  }) {
    final targetMatch = state.firstWhere(
      (m) => m.id == targetMatchId,
      orElse: () => state.first,
    );
    if (targetMatch.isFinished) return false;

    if (otherMatchId != null) {
      final otherMatch = state.firstWhere(
        (m) => m.id == otherMatchId,
        orElse: () => state.first,
      );
      if (otherMatch.isFinished) return false;
    }

    state = state.map((m) {
      if (m.id == targetMatchId) {
        if (otherMatchId == targetMatchId) {
          String swapId(String id) {
            if (id == targetPlayerId) return otherPlayerId;
            if (id == otherPlayerId) return targetPlayerId;
            return id;
          }
          return m.copyWith(
            teamA: m.teamA.map(swapId).toList(),
            teamB: m.teamB.map(swapId).toList(),
          );
        }
        final newTeamA = m.teamA.map((id) => id == targetPlayerId ? otherPlayerId : id).toList();
        final newTeamB = m.teamB.map((id) => id == targetPlayerId ? otherPlayerId : id).toList();
        return m.copyWith(teamA: newTeamA, teamB: newTeamB);
      } else if (otherMatchId != null && m.id == otherMatchId) {
        final newTeamA = m.teamA.map((id) => id == otherPlayerId ? targetPlayerId : id).toList();
        final newTeamB = m.teamB.map((id) => id == otherPlayerId ? targetPlayerId : id).toList();
        return m.copyWith(teamA: newTeamA, teamB: newTeamB);
      }
      return m;
    }).toList();

    _saveCurrentSessionMatches(state);
    return true;
  }

  /// 특별 매치 수동 생성 (+ 수동 코트 추가)
  void addCustomMatch(GameMatch newMatch) {
    state = [...state, newMatch];
    _saveCurrentSessionMatches(state);
  }

  /// [실시간 코트 증감] 코트 추가(+):
  /// - 세션 운영 코트 수를 1개 증가시키고 새로 추가된 코트 번호를 반환
  /// - 현재 라운드에는 새 빈 코트 슬롯이 생성되며, 다음 라운드 생성 시 늘어난 코트 수만큼 자동 배정
  int addCourtSlot() {
    final session = ref.read(sessionProvider);
    if (session == null) return 1;
    final newCount = (session.courtCount + 1).clamp(1, 15);
    ref.read(sessionProvider.notifier).updateCourtCount(newCount);
    return session.startCourtNumber + newCount - 1;
  }

  /// [실시간 코트 증감] 배정된 경기가 없는 빈 코트 우선 제거(-):
  /// - 빈 코트를 닫고 세션 코트 수를 1개 축소
  /// - 만약 중간 번호의 빈 코트가 제거되고 마지막 코트에 경기가 있다면 빈 코트 번호로 당겨서 배정 유지
  /// - 이전 완료된 라운드의 경기 기록은 손실 없이 안전하게 보존
  int? removeEmptyCourtSlot({
    required int currentRound,
    int? targetEmptyCourt,
  }) {
    final session = ref.read(sessionProvider);
    if (session == null || session.courtCount <= 1) return null;

    final startCourt = session.startCourtNumber;
    final endCourt = startCourt + session.courtCount - 1;
    final activeCourts = List.generate(session.courtCount, (i) => startCourt + i);
    final roundMatches = state.where((m) => m.round == currentRound).toList();
    final occupiedCourts = roundMatches.map((m) => m.courtNumber).toSet();

    final emptyCourts = activeCourts.where((c) => !occupiedCourts.contains(c)).toList();
    if (emptyCourts.isEmpty && targetEmptyCourt == null) return null;

    final courtToRemove = targetEmptyCourt ?? emptyCourts.last;

    // 제거 대상 빈 코트가 마지막 코트(endCourt)보다 앞 번호이고 endCourt에 현재 라운드 경기가 있다면 빈 슬롯으로 이동
    if (courtToRemove < endCourt && occupiedCourts.contains(endCourt)) {
      state = state.map((m) {
        if (m.round == currentRound && m.courtNumber == endCourt) {
          return m.copyWith(courtNumber: courtToRemove);
        }
        return m;
      }).toList();
      _saveCurrentSessionMatches(state);
    }

    ref.read(sessionProvider.notifier).updateCourtCount(session.courtCount - 1);
    return courtToRemove;
  }

  /// [실시간 코트 증감] 진행/배정 중인 코트를 닫을 때 해당 경기를 취소하여 선수들을 대기 인원으로 전환 후 코트 축소
  /// - 이전 완료된 라운드(round < target.round) 및 이미 완료된 경기(isFinished)는 절대 삭제되지 않고 보존됨
  void cancelMatchAndReduceCourt({
    required String matchId,
    bool reduceCourtCount = true,
  }) {
    final targetIndex = state.indexWhere((m) => m.id == matchId);
    if (targetIndex == -1) return;
    final targetMatch = state[targetIndex];
    if (targetMatch.isFinished) return;

    final session = ref.read(sessionProvider);
    final updated = state.where((m) => m.id != matchId).toList();

    if (reduceCourtCount && session != null && session.courtCount > 1) {
      final endCourt = session.startCourtNumber + session.courtCount - 1;
      if (targetMatch.courtNumber < endCourt) {
        // 마지막 코트(endCourt)에 있던 현재 라운드 경기를 닫힌 코트 번호로 당겨 코트 범위 유지
        state = updated.map((m) {
          if (m.round == targetMatch.round && m.courtNumber == endCourt) {
            return m.copyWith(courtNumber: targetMatch.courtNumber);
          }
          return m;
        }).toList();
      } else {
        state = updated;
      }
      ref.read(sessionProvider.notifier).updateCourtCount(session.courtCount - 1);
    } else {
      state = updated;
    }

    _saveCurrentSessionMatches(state);
  }

  /// [실시간 코트 증감] 진행/배정 중인 코트의 경기를 다른 빈 코트 슬롯으로 이동한 뒤 코트 축소
  void moveMatchToEmptyCourtAndReduce({
    required String matchId,
    required int targetEmptyCourt,
  }) {
    updateCourtNumber(matchId, targetEmptyCourt);
    final session = ref.read(sessionProvider);
    if (session != null && session.courtCount > 1) {
      ref.read(sessionProvider.notifier).updateCourtCount(session.courtCount - 1);
    }
    _saveCurrentSessionMatches(state);
  }

  /// 빈 코트 슬롯에 현재 대기(휴식) 중인 인원 4명을 즉시 자동 매칭하여 투입
  GameMatch? autoAssignWaitingToEmptyCourt({
    required int round,
    required int courtNumber,
  }) {
    final session = ref.read(sessionProvider);
    if (session == null) return null;

    final allMembers = ref.read(membersProvider);
    final roundMatches = state.where((m) => m.round == round).toList();
    final playingIds = roundMatches.expand((m) => m.allPlayerIds).toSet();

    final waitingIds = session.activeAttendees
        .where((id) => !playingIds.contains(id))
        .toList();
    if (waitingIds.length < 4) return null;

    final tempSession = session.copyWith(
      attendees: waitingIds,
      attendeeStatusMap: {
        for (final id in waitingIds) id: AttendanceStatus.active,
      },
      courtCount: 1,
      startCourtNumber: courtNumber,
    );
    final generator = ref.read(matchGeneratorServiceProvider);
    final generated = generator.generateRoundMatches(
      session: tempSession,
      allMembers: allMembers,
      existingMatches: state.where((m) => m.round < round).toList(),
      targetRound: round,
    );
    if (generated.isEmpty) return null;

    final newMatch = generated.first.copyWith(
      id: 'auto_slot_r${round}_c${courtNumber}_${DateTime.now().millisecondsSinceEpoch}',
      courtNumber: courtNumber,
    );
    state = [...state, newMatch];
    _saveCurrentSessionMatches(state);
    return newMatch;
  }

  /// [남은 라운드 재편성]:
  /// - 경기 중 조퇴·지각·휴식 발생 시, 이미 완료된 코트 기록(isFinished)과 이전 라운드 기록은 100% 보존하고
  ///   대기 중인 코트 및 남은 라운드만 현재 출석 가능 인원(activeAttendees, 신규 게스트 포함)으로 다시 배정
  int reshuffleRemainingMatches({int? targetRound}) {
    final session = ref.read(sessionProvider);
    if (session == null) return 0;

    final allMembers = ref.read(membersProvider);
    final generator = ref.read(matchGeneratorServiceProvider);
    final int currentRound =
        targetRound ?? (ref.read(selectedRoundProvider) as int? ?? 1);

    final currentRoundMatches = state.where((m) => m.round == currentRound).toList();
    final int maxExistingRound = state.isEmpty
        ? currentRound
        : state.map((m) => m.round).reduce((a, b) => a > b ? a : b);

    // 현재 라운드의 모든 코트가 이미 종료(finished)되었고 다음 라운드가 아직 없다면 다음 라운드를 새로 배정
    final bool allCurrentFinished = currentRoundMatches.isNotEmpty &&
        currentRoundMatches.every((m) => m.isFinished);

    final int startReshuffleRound =
        (allCurrentFinished && maxExistingRound == currentRound)
            ? currentRound + 1
            : currentRound;
    final int endReshuffleRound =
        maxExistingRound > startReshuffleRound ? maxExistingRound : startReshuffleRound;

    // 1. startReshuffleRound 이전의 모든 경기 보존
    final List<GameMatch> updatedMatches =
        state.where((m) => m.round < startReshuffleRound).toList();
    int regeneratedCount = 0;

    // 2. startReshuffleRound부터 endReshuffleRound까지 완료된 코트는 보존하고 미완료(대기) 코트만 현재 출석 인원으로 재편성
    for (int r = startReshuffleRound; r <= endReshuffleRound; r++) {
      final preservedInRound = state
          .where((m) => m.round == r && m.isFinished)
          .toList();
      updatedMatches.addAll(preservedInRound);

      final lockedCourts = preservedInRound.map((m) => m.courtNumber).toSet();
      final lockedPlayers = preservedInRound.expand((m) => m.allPlayerIds).toSet();

      final startCourt = session.startCourtNumber;
      final allCourtNumbers =
          List.generate(session.courtCount, (i) => startCourt + i);
      final openCourts =
          allCourtNumbers.where((c) => !lockedCourts.contains(c)).toList();

      if (openCourts.isEmpty) continue;

      final availableAttendees = session.activeAttendees
          .where((id) => !lockedPlayers.contains(id))
          .toList();
      if (availableAttendees.length < 4) continue;

      final tempSession = session.copyWith(
        attendees: availableAttendees,
        attendeeStatusMap: {
          for (final id in availableAttendees) id: AttendanceStatus.active,
        },
        courtCount: openCourts.length,
        startCourtNumber: openCourts.first,
      );

      final generated = generator.generateRoundMatches(
        session: tempSession,
        allMembers: allMembers,
        existingMatches: updatedMatches,
        targetRound: r,
      );

      for (int i = 0; i < generated.length && i < openCourts.length; i++) {
        final assignedCourt = openCourts[i];
        updatedMatches.add(
          generated[i].copyWith(
            id: 'reshuffle_r${r}_c${assignedCourt}_${DateTime.now().millisecondsSinceEpoch}_$i',
            courtNumber: assignedCourt,
          ),
        );
        regeneratedCount++;
      }
    }

    state = updatedMatches;
    _saveCurrentSessionMatches(state);
    ref.read(selectedRoundProvider.notifier).setRound(startReshuffleRound);
    return regeneratedCount;
  }
}

final matchesProvider = NotifierProvider<MatchesNotifier, List<GameMatch>>(
  MatchesNotifier.new,
);

// ============================================================================
// 연간/월별 회비 납부 현황표 & 클럽 기본 회비 정책/회칙 상태 관리 (영구 저장 지원)
// ============================================================================

const String kClubFeePoliciesStorageKey = 'cockmatch_club_fee_policies_v1';
const String kFeeLedgerStorageKey = 'cockmatch_fee_ledger_v1';

class ClubFeePoliciesNotifier extends Notifier<Map<String, ClubFeePolicy>> {
  @override
  Map<String, ClubFeePolicy> build() {
    _loadFromStorageAsync();
    return Map<String, ClubFeePolicy>.from(MockData.initialClubFeePolicies);
  }

  Future<void> _loadFromStorageAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kClubFeePoliciesStorageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final loaded = Map<String, ClubFeePolicy>.from(state);
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            loaded[entry.key] = ClubFeePolicy.fromJson(
              entry.value as Map<String, dynamic>,
            );
          }
        }
        state = loaded;
      }
    } catch (_) {
      // 테스트 또는 스토리지 미초기화 환경 폴백
    }
  }

  Future<void> _persist(Map<String, ClubFeePolicy> current) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = {
        for (final e in current.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(kClubFeePoliciesStorageKey, jsonEncode(serializable));
    } catch (_) {}
  }

  Future<void> updatePolicy(ClubFeePolicy updated) async {
    final next = {...state, updated.clubId: updated};
    state = next;
    await _persist(next);
  }

  Future<void> updateRulesAndMemo(String clubId, String rulesAndMemo) async {
    final existing = state[clubId] ?? ClubFeePolicy(clubId: clubId);
    final updated = existing.copyWith(rulesAndMemo: rulesAndMemo);
    await updatePolicy(updated);
  }
}

final clubFeePoliciesProvider =
    NotifierProvider<ClubFeePoliciesNotifier, Map<String, ClubFeePolicy>>(
  ClubFeePoliciesNotifier.new,
);

/// 현재 선택된 클럽의 기본 회비 정책 및 입금 계좌/회칙 Provider
final currentClubFeePolicyProvider = Provider<ClubFeePolicy>((ref) {
  final clubId = ref.watch(currentClubIdProvider);
  final policies = ref.watch(clubFeePoliciesProvider);
  return policies[clubId] ?? ClubFeePolicy(clubId: clubId);
});

/// 연간/월별 회비 납부 매트릭스 셀 상태 관리 Notifier
class FeeLedgerNotifier extends Notifier<Map<String, MonthlyFeeRecord>> {
  @override
  Map<String, MonthlyFeeRecord> build() {
    _loadFromStorageAsync();
    return MockData.buildInitialFeeLedgerMap();
  }

  Future<void> _loadFromStorageAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kFeeLedgerStorageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final loaded = Map<String, MonthlyFeeRecord>.from(state);
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            loaded[entry.key] = MonthlyFeeRecord.fromJson(
              entry.value as Map<String, dynamic>,
            );
          }
        }
        state = loaded;
      }
    } catch (_) {}
  }

  Future<void> _persist(Map<String, MonthlyFeeRecord> current) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = {
        for (final e in current.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(kFeeLedgerStorageKey, jsonEncode(serializable));
    } catch (_) {}
  }

  /// 특정 회원의 특정 연·월 납부 상태 및 입금일/메모 저장
  Future<void> updateCellRecord({
    required String clubId,
    required int year,
    required String memberId,
    required int month,
    required MonthlyFeeRecord record,
  }) async {
    final key = FeeLedgerCalculator.buildCellKey(
      clubId: clubId,
      year: year,
      memberId: memberId,
      month: month,
    );
    final next = {...state, key: record};
    state = next;

    // 2026년 9월(당월) 상태 변경 시 회원 프로필의 당월 feeStatus와도 자동 동기화
    if (year == 2026 && month == 9) {
      ref.read(membersProvider.notifier).updateFeeStatus(memberId, record.status);
    }

    await _persist(next);
  }

  /// 셀 클릭 시 상태 원터치 토글: [완납(녹색 체크)] ↔ [미납(붉은 점)] ↔ [면제·휴면(회색 대시)]
  Future<FeeStatus> cycleCellStatus({
    required String clubId,
    required int year,
    required Member member,
    required int month,
    required ClubFeePolicy policy,
  }) async {
    final currentRec = FeeLedgerCalculator.resolveCellRecord(
      ledgerMap: state,
      clubId: clubId,
      year: year,
      month: month,
      member: member,
      policy: policy,
    );
    final FeeStatus nextStatus = switch (currentRec.status) {
      FeeStatus.paid => FeeStatus.unpaid,
      FeeStatus.unpaid => FeeStatus.exempt,
      FeeStatus.exempt => FeeStatus.paid,
    };
    final standardFee =
        FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);
    final now = DateTime.now();
    final todayStr =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';

    final updatedRecord = MonthlyFeeRecord(
      status: nextStatus,
      paidAmount: nextStatus == FeeStatus.paid ? standardFee : 0,
      paidDate: nextStatus == FeeStatus.paid ? (currentRec.paidDate ?? todayStr) : null,
      memo: currentRec.memo,
      isManualOverride: true,
    );
    await updateCellRecord(
      clubId: clubId,
      year: year,
      memberId: member.id,
      month: month,
      record: updatedRecord,
    );
    return nextStatus;
  }

  /// 특정 회원의 연간(1~12월) 또는 상반기(1~6월)/하반기(7~12월) 회비 일괄 완납 처리 ([1년 일괄 완납])
  Future<int> markMemberPeriodAllPaid({
    required String clubId,
    required int year,
    required Member member,
    required ClubFeePolicy policy,
    int startMonth = 1,
    int endMonth = 12,
    String? paidDate,
    String? memo,
  }) async {
    final next = Map<String, MonthlyFeeRecord>.from(state);
    final standardFee =
        FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);
    final effectiveFee = standardFee > 0 ? standardFee : policy.defaultMonthlyFee;
    final now = DateTime.now();
    final effectiveDate = paidDate ??
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final effectiveMemo = memo ??
        (startMonth == 1 && endMonth == 12
            ? '1년 일괄 완납'
            : '$startMonth~$endMonth월 일괄 완납');

    int updatedCount = 0;
    for (int m = startMonth; m <= endMonth; m++) {
      final key = FeeLedgerCalculator.buildCellKey(
        clubId: clubId,
        year: year,
        memberId: member.id,
        month: m,
      );
      next[key] = MonthlyFeeRecord(
        status: FeeStatus.paid,
        paidAmount: effectiveFee,
        paidDate: effectiveDate,
        memo: effectiveMemo,
        isManualOverride: true,
      );
      if (year == 2026 && m == 9) {
        ref.read(membersProvider.notifier).updateFeeStatus(member.id, FeeStatus.paid);
      }
      updatedCount++;
    }

    state = next;
    await _persist(next);
    return updatedCount;
  }

  /// 수동 오버라이드를 해제하고 회원 프로필(면제/휴면/기본액) 자동 연동 상태로 복원
  Future<void> resetCellToAutoDefault({
    required String clubId,
    required int year,
    required String memberId,
    required int month,
  }) async {
    final key = FeeLedgerCalculator.buildCellKey(
      clubId: clubId,
      year: year,
      memberId: memberId,
      month: month,
    );
    final next = Map<String, MonthlyFeeRecord>.from(state)..remove(key);
    state = next;
    await _persist(next);
  }

  /// 특정 월의 미납 활동 회원 전원을 일괄 완납 처리
  Future<int> markMonthAllPaid({
    required String clubId,
    required int year,
    required int month,
    required List<Member> members,
    required ClubFeePolicy policy,
    required String paidDate,
  }) async {
    final next = Map<String, MonthlyFeeRecord>.from(state);
    int updatedCount = 0;

    for (final member in members) {
      if (member.isGuest) continue;
      final currentRec = FeeLedgerCalculator.resolveCellRecord(
        ledgerMap: next,
        clubId: clubId,
        year: year,
        month: month,
        member: member,
        policy: policy,
      );
      if (currentRec.status == FeeStatus.unpaid) {
        final key = FeeLedgerCalculator.buildCellKey(
          clubId: clubId,
          year: year,
          memberId: member.id,
          month: month,
        );
        final standardFee =
            FeeLedgerCalculator.getMemberStandardMonthlyFee(member, policy);
        next[key] = MonthlyFeeRecord(
          status: FeeStatus.paid,
          paidAmount: standardFee,
          paidDate: paidDate,
          memo: '일괄 완납 처리',
          isManualOverride: true,
        );
        if (year == 2026 && month == 9) {
          ref.read(membersProvider.notifier).updateFeeStatus(member.id, FeeStatus.paid);
        }
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      state = next;
      await _persist(next);
    }
    return updatedCount;
  }
}

final feeLedgerProvider =
    NotifierProvider<FeeLedgerNotifier, Map<String, MonthlyFeeRecord>>(
  FeeLedgerNotifier.new,
);

// ============================================================================
// [PRO 장부] 특별 행사/정기모임 정산 금전출납부 상태 관리 (영구 저장 지원)
// ============================================================================

const String kClubEventsStorageKey = 'cockmatch_club_events_v1';

class ClubEventsNotifier extends Notifier<List<ClubEvent>> {
  @override
  List<ClubEvent> build() {
    _loadFromStorageAsync();
    return List<ClubEvent>.from(MockData.initialClubEvents);
  }

  Future<void> _loadFromStorageAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kClubEventsStorageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final loaded = <ClubEvent>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            loaded.add(ClubEvent.fromMap(item));
          }
        }
        if (loaded.isNotEmpty) {
          state = loaded;
        }
      }
    } catch (_) {}
  }

  Future<void> _persist(List<ClubEvent> current) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = current.map((e) => e.toMap()).toList();
      await prefs.setString(kClubEventsStorageKey, jsonEncode(list));
    } catch (_) {}
  }

  ClubEvent createEvent({
    required String clubId,
    required String title,
    required String eventDate,
    String? memo,
    String? linkedSessionId,
    List<EventExpenseItem> initialItems = const [],
  }) {
    final newEvent = ClubEvent(
      id: 'event_${clubId}_${DateTime.now().millisecondsSinceEpoch}',
      clubId: clubId,
      title: title.trim(),
      eventDate: eventDate.trim(),
      memo: memo?.trim(),
      linkedSessionId: linkedSessionId,
      items: initialItems,
      createdAt: DateTime.now(),
    );
    final next = [newEvent, ...state];
    state = next;
    _persist(next);
    return newEvent;
  }

  void updateEvent(ClubEvent event) {
    final next = state.map((e) => e.id == event.id ? event : e).toList();
    state = next;
    _persist(next);
  }

  void deleteEvent(String eventId) {
    final next = state.where((e) => e.id != eventId).toList();
    state = next;
    _persist(next);
  }

  void addItem(String eventId, EventExpenseItem item) {
    final next = state.map((event) {
      if (event.id == eventId) {
        return event.copyWith(items: [...event.items, item]);
      }
      return event;
    }).toList();
    state = next;
    _persist(next);
  }

  void updateItem(String eventId, EventExpenseItem updatedItem) {
    final next = state.map((event) {
      if (event.id == eventId) {
        final updatedItems = event.items
            .map((item) => item.id == updatedItem.id ? updatedItem : item)
            .toList();
        return event.copyWith(items: updatedItems);
      }
      return event;
    }).toList();
    state = next;
    _persist(next);
  }

  void deleteItem(String eventId, String itemId) {
    final next = state.map((event) {
      if (event.id == eventId) {
        return event.copyWith(
          items: event.items.where((i) => i.id != itemId).toList(),
        );
      }
      return event;
    }).toList();
    state = next;
    _persist(next);
  }

  /// 일정/모임 세션 데이터로부터 행사비 출납부 원클릭 생성/불러오기
  ClubEvent importFromSession({
    required GameSession session,
    required List<Member> members,
  }) {
    final collected = session.calculatePaidFee(members);
    final count = session.attendees.length;
    final now = DateTime.now();
    final eventId = 'event_${session.clubId}_${now.millisecondsSinceEpoch}';

    final items = <EventExpenseItem>[];
    if (collected > 0) {
      items.add(
        EventExpenseItem(
          id: 'item_${now.millisecondsSinceEpoch}',
          eventId: eventId,
          title: '모임 참가비 수납 ($count명 참석)',
          amount: collected,
          isIncome: true,
          date: session.sessionDate,
          memo: '일정/모임 회비 수납 내역 자동 집계',
          createdAt: now,
        ),
      );
    }

    final newEvent = ClubEvent(
      id: eventId,
      clubId: session.clubId,
      title: (session.title != null && session.title!.trim().isNotEmpty)
          ? session.title!.trim()
          : '${session.sessionDate} 정기모임 정산',
      eventDate: session.sessionDate,
      linkedSessionId: session.id,
      memo: '일정/모임(${session.displayTitle}) 자동 연동',
      items: items,
      createdAt: now,
    );

    final next = [newEvent, ...state];
    state = next;
    _persist(next);
    return newEvent;
  }
}

final clubEventsProvider =
    NotifierProvider<ClubEventsNotifier, List<ClubEvent>>(
  ClubEventsNotifier.new,
);

/// 현재 선택된 클럽에 등록된 행사/모임 출납부 목록 Provider
final currentClubEventsProvider = Provider<List<ClubEvent>>((ref) {
  final clubId = ref.watch(currentClubIdProvider);
  final allEvents = ref.watch(clubEventsProvider);
  return allEvents.where((e) => e.clubId == clubId).toList();
});