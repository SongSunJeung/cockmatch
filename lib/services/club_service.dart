import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// CSV 업로드 시 기존 동일 전화번호 회원 중복 처리 옵션
enum CsvDuplicatePolicy {
  overwrite('기존 정보 덮어쓰기'),
  skip('건너뛰기');

  final String label;
  const CsvDuplicatePolicy(this.label);
}

/// CSV 개별 행 파싱 및 유효성 검증 결과 모델
class CsvParsedRow {
  final int rowNumber; // CSV 내 데이터 행 번호 (1부터 시작)
  final String rawName;
  final String rawPhone;
  final String rawGender;
  final String rawTier;
  final String rawMemberType;
  final String rawMemo;
  final Member? member;
  final List<String> errors;
  final bool isDuplicatePhone;
  final Member? existingMember;

  const CsvParsedRow({
    required this.rowNumber,
    required this.rawName,
    required this.rawPhone,
    required this.rawGender,
    required this.rawTier,
    required this.rawMemberType,
    required this.rawMemo,
    this.member,
    this.errors = const [],
    this.isDuplicatePhone = false,
    this.existingMember,
  });

  bool get isValid => errors.isEmpty && member != null;
  String get errorSummary => errors.join(', ');
}

/// CSV 전체 파싱 및 사전 검증 요약 결과 모델
class CsvImportAnalysisResult {
  final List<CsvParsedRow> rows;

  const CsvImportAnalysisResult({required this.rows});

  /// 총 검출된 데이터 행 수
  int get totalDetectedCount => rows.length;

  /// 유효한 행 목록
  List<CsvParsedRow> get validRows => rows.where((r) => r.isValid).toList();

  /// 오류가 있는 행 목록 (필수값 누락, 잘못된 급수/성별/전화번호 등)
  List<CsvParsedRow> get errorRows => rows.where((r) => !r.isValid).toList();

  /// 유효한 행 중 기존 전화번호와 중복되는 행 목록
  List<CsvParsedRow> get duplicateRows =>
      validRows.where((r) => r.isDuplicatePhone).toList();
}

/// 클럽 및 회원 풀 관리 비즈니스 로직 서비스
class ClubService {
  static const _uuid = Uuid();

  /// 표준 CSV 헤더 컬럼 규격
  static const List<String> standardCsvHeaders = [
    '이름',
    '전화번호',
    '성별',
    '급수',
    '회원구분',
    '메모',
  ];

  /// UTF-8 BOM 바이트 시퀀스 (엑셀 한글 깨짐 방지용)
  static const List<int> utf8Bom = [0xEF, 0xBB, 0xBF];

  /// 회원 목록 다중 조건 필터링 및 정렬 (기본값: 이름 가나다순)
  List<Member> filterMembers(List<Member> members, MemberFilter filter) {
    final filtered = members.where((member) => filter.matches(member)).toList();
    return sortMembers(filtered, sortBy: filter.sortBy);
  }

  /// 회원명부 목록 정렬
  /// - nameAsc: 이름순 (가나다 ㄱ -> ㅎ) [기본]
  /// - tierDesc: 급수순 (상위 급수 우선: A -> 초심)
  /// - gradeFirst: 회원 구분순 (운영진 -> 정회원 -> 준회원)
  /// - recentRegistered: 최근 등록순 (최신 가입/등록 우선)
  List<Member> sortMembers(
    List<Member> members, {
    MemberSortBy sortBy = MemberSortBy.nameAsc,
  }) {
    final sorted = List<Member>.from(members);
    switch (sortBy) {
      case MemberSortBy.nameAsc:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case MemberSortBy.tierDesc:
        sorted.sort((a, b) {
          final diff = b.tierWeight.compareTo(a.tierWeight);
          return diff != 0 ? diff : a.name.compareTo(b.name);
        });
        break;
      case MemberSortBy.gradeFirst:
        sorted.sort((a, b) {
          final gradeDiff = a.grade.index.compareTo(b.grade.index);
          if (gradeDiff != 0) return gradeDiff;
          final roleDiff = a.role.index.compareTo(b.role.index);
          if (roleDiff != 0) return roleDiff;
          return a.name.compareTo(b.name);
        });
        break;
      case MemberSortBy.recentRegistered:
        final indexMap = <String, int>{
          for (int i = 0; i < members.length; i++) members[i].id: i,
        };
        sorted.sort((a, b) {
          final aTime = a.createdAt ?? a.joinedAt;
          final bTime = b.createdAt ?? b.joinedAt;
          if (aTime != null && bTime != null) {
            final timeDiff = bTime.compareTo(aTime);
            if (timeDiff != 0) return timeDiff;
          } else if (bTime != null) {
            return 1;
          } else if (aTime != null) {
            return -1;
          }
          return (indexMap[a.id] ?? 0).compareTo(indexMap[b.id] ?? 0);
        });
        break;
      case MemberSortBy.tierAsc:
        sorted.sort((a, b) {
          final diff = a.tierWeight.compareTo(b.tierWeight);
          return diff != 0 ? diff : a.name.compareTo(b.name);
        });
        break;
      case MemberSortBy.roleFirst:
        sorted.sort((a, b) {
          final diff = a.role.index.compareTo(b.role.index);
          return diff != 0 ? diff : a.name.compareTo(b.name);
        });
        break;
    }
    return sorted;
  }

  /// 출석부 참석자 목록 정렬
  /// - tierDesc: 급수순 (A -> 초심) [기본]
  /// - nameAsc: 이름순 (가나다)
  /// - attendanceStatus: 출전 상태순 (출전 -> 휴식 -> 조퇴)
  /// - feeUnpaidFirst: 회비 상태순 (미납자 최우선 정렬: 미납 -> 완납 -> 면제)
  List<Member> sortAttendanceMembers(
    List<Member> members,
    GameSession session, {
    AttendanceSortBy sortBy = AttendanceSortBy.tierDesc,
  }) {
    final sorted = List<Member>.from(members);
    int feePriority(FeeStatus status) {
      return switch (status) {
        FeeStatus.unpaid => 0,
        FeeStatus.paid => 1,
        FeeStatus.exempt => 2,
      };
    }

    switch (sortBy) {
      case AttendanceSortBy.tierDesc:
        sorted.sort((a, b) {
          final diff = b.tierWeight.compareTo(a.tierWeight);
          return diff != 0 ? diff : a.name.compareTo(b.name);
        });
        break;
      case AttendanceSortBy.nameAsc:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case AttendanceSortBy.attendanceStatus:
        sorted.sort((a, b) {
          final statusA = session.getAttendeeStatus(a.id).index;
          final statusB = session.getAttendeeStatus(b.id).index;
          final statusDiff = statusA.compareTo(statusB);
          if (statusDiff != 0) return statusDiff;
          final tierDiff = b.tierWeight.compareTo(a.tierWeight);
          return tierDiff != 0 ? tierDiff : a.name.compareTo(b.name);
        });
        break;
      case AttendanceSortBy.feeUnpaidFirst:
        sorted.sort((a, b) {
          final feeA = feePriority(session.getAttendeeFeeStatus(a));
          final feeB = feePriority(session.getAttendeeFeeStatus(b));
          final feeDiff = feeA.compareTo(feeB);
          if (feeDiff != 0) return feeDiff;
          final tierDiff = b.tierWeight.compareTo(a.tierWeight);
          return tierDiff != 0 ? tierDiff : a.name.compareTo(b.name);
        });
        break;
    }
    return sorted;
  }

  /// 전화번호 정규화 (하이픈 유무 무관하게 010-XXXX-XXXX 형식으로 변환)
  /// - 빈 문자열이면 null 반환
  /// - 유효하지 않은 전화번호 형식이면 FormatException 발생 또는 null 처리
  static String? normalizePhoneNumber(String? rawPhone, {bool strict = false}) {
    if (rawPhone == null) return null;
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) return null;

    // 숫자만 추출
    String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    // 엑셀에서 앞자리 0이 생략된 경우 (예: 1012345678 -> 01012345678)
    if (digits.length == 10 && digits.startsWith('10')) {
      digits = '0$digits';
    }

    // 010-XXXX-XXXX (11자리) 또는 01X-XXX-XXXX (10자리)
    if (digits.length == 11 && digits.startsWith('01')) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, 11)}';
    } else if (digits.length == 10 && digits.startsWith('01')) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6, 10)}';
    }

    if (strict) {
      throw const FormatException('잘못된 전화번호 형식');
    }
    return trimmed;
  }

  /// CSV 파일명 생성 ("메가배드민턴_회원명부_YYYYMMDD.csv")
  String buildExportFileName(String clubName, {DateTime? date}) {
    final targetDate = date ?? DateTime.now();
    final yyyy = targetDate.year.toString();
    final mm = targetDate.month.toString().padLeft(2, '0');
    final dd = targetDate.day.toString().padLeft(2, '0');

    // 예: '메가 배드민턴 클럽' -> '메가배드민턴'
    String cleanClub = clubName
        .replaceAll(RegExp(r'\s*클럽$'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    if (cleanClub.isEmpty) {
      cleanClub = '배드민턴클럽';
    }
    return '${cleanClub}_회원명부_$yyyy$mm$dd.csv';
  }

  /// 표준 템플릿 CSV 문자열 생성
  String generateStandardTemplateCsvString() {
    final rows = <List<dynamic>>[
      standardCsvHeaders,
      ['홍길동', '010-1234-5678', '남', 'A', '운영진(회장)', '창립 멤버'],
      ['김민수', '01098765432', '남성', 'B조', '운영진(총무)', '회비 관리'],
      ['이영희', '010-5555-7777', '여', 'C', '정회원', '화/목 참석'],
      ['박초심', '010-3333-4444', '여성', '초심', '준회원', '신입 레슨생'],
    ];
    return csv.encode(rows);
  }

  /// 표준 템플릿 CSV UTF-8 BOM 바이트 배열 생성
  Uint8List generateStandardTemplateCsvBytes() {
    final csvStr = generateStandardTemplateCsvString();
    final encoded = utf8.encode(csvStr);
    return Uint8List.fromList([...utf8Bom, ...encoded]);
  }

  /// 현재 등록된 회원 목록을 표준 규격 CSV 문자열로 변환
  String exportMembersToCsvString(List<Member> members) {
    final rows = <List<dynamic>>[
      standardCsvHeaders,
    ];

    for (final m in members) {
      final phoneStr = normalizePhoneNumber(m.phoneNumber) ?? (m.phoneNumber ?? '');
      final genderStr = m.gender == Gender.female ? '여' : '남';
      final tierStr = m.tier == Tier.novice ? '초심' : m.tier.code;

      String memberTypeStr;
      if (m.role.isExecutive) {
        memberTypeStr = '운영진(${m.role.label})';
      } else if (m.role == MemberRole.associate) {
        memberTypeStr = '준회원';
      } else {
        memberTypeStr = '정회원';
      }

      final memoStr = (m.memo != null && m.memo!.trim().isNotEmpty)
          ? m.memo!.trim()
          : '';

      rows.add([
        m.name,
        phoneStr,
        genderStr,
        tierStr,
        memberTypeStr,
        memoStr,
      ]);
    }

    return csv.encode(rows);
  }

  /// 현재 등록된 회원 목록을 UTF-8 BOM이 포함된 CSV 바이트 배열로 변환
  Uint8List exportMembersToCsvBytes(List<Member> members) {
    final csvStr = exportMembersToCsvString(members);
    final encoded = utf8.encode(csvStr);
    return Uint8List.fromList([...utf8Bom, ...encoded]);
  }

  /// UTF-8 (BOM 포함 가능) 바이트 배열에서 CSV 문자열 디코딩
  String decodeCsvBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 표준 규격 CSV 문자열 파싱 및 유효성/중복 사전 검증 (미리보기 팝업용)
  CsvImportAnalysisResult analyzeCsvContent(
    String rawCsvContent, {
    required String clubId,
    required List<Member> existingClubMembers,
  }) {
    String cleaned = rawCsvContent;
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1);
    }

    if (cleaned.trim().isEmpty) {
      return const CsvImportAnalysisResult(rows: []);
    }

    // 줄바꿈 정규화 후 CSV 디코딩
    final normalizedCsv = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final decodedRows = csv.decode(normalizedCsv);
    if (decodedRows.isEmpty) {
      return const CsvImportAnalysisResult(rows: []);
    }

    // 첫 행이 헤더인지 판별 ('이름', '성명', '전화번호', '급수' 등 포함 여부)
    int startRowIndex = 0;
    Map<String, int> colMap = {
      'name': 0,
      'phone': 1,
      'gender': 2,
      'tier': 3,
      'memberType': 4,
      'memo': 5,
    };

    final firstRowCells =
        decodedRows.first.map((e) => (e?.toString() ?? '').trim()).toList();
    final isHeaderRow = firstRowCells.any(
      (c) =>
          c == '이름' ||
          c == '성명' ||
          c == '전화번호' ||
          c == '연락처' ||
          c == '급수' ||
          c == '회원구분' ||
          c.toLowerCase() == 'name',
    );

    if (isHeaderRow) {
      startRowIndex = 1;
      colMap = {};
      for (int i = 0; i < firstRowCells.length; i++) {
        final h = firstRowCells[i].replaceAll(' ', '');
        if (h == '이름' || h == '성명' || h.toLowerCase() == 'name') {
          colMap['name'] = i;
        } else if (h == '전화번호' || h == '연락처' || h == '휴대폰' || h.toLowerCase() == 'phone') {
          colMap['phone'] = i;
        } else if (h == '성별' || h.toLowerCase() == 'gender') {
          colMap['gender'] = i;
        } else if (h == '급수' || h == '조' || h.toLowerCase() == 'tier') {
          colMap['tier'] = i;
        } else if (h == '회원구분' || h == '등급' || h == '직책' || h == '구분') {
          colMap['memberType'] = i;
        } else if (h == '메모' || h == '비고' || h.toLowerCase() == 'memo') {
          colMap['memo'] = i;
        }
      }
      // 기본 인덱스 보완
      colMap.putIfAbsent('name', () => 0);
      colMap.putIfAbsent('phone', () => 1);
      colMap.putIfAbsent('gender', () => 2);
      colMap.putIfAbsent('tier', () => 3);
      colMap.putIfAbsent('memberType', () => 4);
      colMap.putIfAbsent('memo', () => 5);
    }

    // 기존 클럽 회원의 정규화된 전화번호 맵 구성
    final Map<String, Member> existingByPhone = {};
    for (final m in existingClubMembers) {
      final norm = normalizePhoneNumber(m.phoneNumber);
      if (norm != null && norm.isNotEmpty) {
        existingByPhone[norm] = m;
      }
    }

    final parsedRows = <CsvParsedRow>[];
    int dataRowNum = 0;

    for (int r = startRowIndex; r < decodedRows.length; r++) {
      final row = decodedRows[r];
      final cells = row.map((e) => (e?.toString() ?? '').trim()).toList();

      // 모든 셀이 비어있는 빈 줄은 건너뜀
      if (cells.every((c) => c.isEmpty)) {
        continue;
      }

      dataRowNum++;

      String getCell(String key) {
        final idx = colMap[key] ?? -1;
        if (idx >= 0 && idx < cells.length) {
          return cells[idx];
        }
        return '';
      }

      final rawName = getCell('name');
      final rawPhone = getCell('phone');
      final rawGender = getCell('gender');
      final rawTier = getCell('tier');
      final rawMemberType = getCell('memberType');
      final rawMemo = getCell('memo');

      final errors = <String>[];

      // 1) 이름 필수 검증
      if (rawName.isEmpty) {
        errors.add('필수값(이름) 누락');
      }

      // 2) 전화번호 정규화 및 형식 검증
      String? normalizedPhone;
      if (rawPhone.isNotEmpty) {
        try {
          normalizedPhone = normalizePhoneNumber(rawPhone, strict: true);
        } on FormatException {
          errors.add('잘못된 전화번호($rawPhone)');
        }
      }

      // 3) 성별 검증 (남 / 여 / 남성 / 여성 / M / F, 미입력 시 남)
      Gender gender = Gender.male;
      if (rawGender.isNotEmpty) {
        final g = rawGender.trim().toLowerCase();
        if (g == '남' || g == '남성' || g == '남자' || g == 'm' || g == 'male') {
          gender = Gender.male;
        } else if (g == '여' || g == '여성' || g == '여자' || g == 'f' || g == 'female') {
          gender = Gender.female;
        } else {
          errors.add('잘못된 성별($rawGender)');
        }
      }

      // 4) 급수 검증 (S, A, B, C, D, 초심 / S조, A조, B조 등, 미입력 시 초심)
      Tier tier = Tier.novice;
      if (rawTier.isNotEmpty) {
        final t = rawTier.trim().toUpperCase().replaceAll('조', '').replaceAll('급', '').trim();
        if (t == 'S') {
          tier = Tier.s;
        } else if (t == 'A') {
          tier = Tier.a;
        } else if (t == 'B') {
          tier = Tier.b;
        } else if (t == 'C') {
          tier = Tier.c;
        } else if (t == 'D') {
          tier = Tier.d;
        } else if (t == '초심' ||
            t == '초심자' ||
            t == '왕초심' ||
            t == '초보' ||
            t == 'NOVICE') {
          tier = Tier.novice;
        } else {
          errors.add('잘못된 급수($rawTier)');
        }
      }

      // 5) 회원구분 검증 (운영진[회장/부회장/총무/경기이사], 정회원, 준회원, 기본값 정회원)
      MemberRole role = MemberRole.member;
      if (rawMemberType.isNotEmpty) {
        final mt = rawMemberType.trim();
        if (mt == '정회원' || mt == '일반' || mt == '일반회원' || mt == '회원') {
          role = MemberRole.member;
        } else if (mt == '준회원' || mt.toLowerCase() == 'associate') {
          role = MemberRole.associate;
        } else if (mt.contains('부회장')) {
          role = MemberRole.vicePresident;
        } else if (mt.contains('회장')) {
          role = MemberRole.president;
        } else if (mt.contains('총무')) {
          role = MemberRole.manager;
        } else if (mt.contains('경기이사') || mt.contains('이사')) {
          role = MemberRole.matchDirector;
        } else if (mt == '운영진' || mt.startsWith('운영진')) {
          role = MemberRole.manager;
        } else {
          errors.add('잘못된 회원구분($rawMemberType)');
        }
      }

      final existingDup =
          (normalizedPhone != null && normalizedPhone.isNotEmpty)
              ? existingByPhone[normalizedPhone]
              : null;

      Member? createdMember;
      if (errors.isEmpty) {
        createdMember = Member(
          id: existingDup?.id ?? _uuid.v4(),
          clubId: clubId,
          name: rawName,
          gender: gender,
          tier: tier,
          role: role,
          status: existingDup?.status ?? MemberStatus.active,
          feeStatus: existingDup?.feeStatus ?? FeeStatus.unpaid,
          phoneNumber: normalizedPhone,
          memo: rawMemo.isNotEmpty ? rawMemo : existingDup?.memo,
          homeClub: existingDup?.homeClub,
          joinedAt: existingDup?.joinedAt ?? DateTime.now(),
        );
      }

      parsedRows.add(
        CsvParsedRow(
          rowNumber: dataRowNum,
          rawName: rawName,
          rawPhone: normalizedPhone ?? rawPhone,
          rawGender: rawGender.isEmpty ? gender.label : rawGender,
          rawTier: rawTier.isEmpty ? tier.label : rawTier,
          rawMemberType: rawMemberType.isEmpty ? '정회원' : rawMemberType,
          rawMemo: rawMemo,
          member: createdMember,
          errors: errors,
          isDuplicatePhone: existingDup != null,
          existingMember: existingDup,
        ),
      );
    }

    return CsvImportAnalysisResult(rows: parsedRows);
  }

  /// 텍스트 복사/붙여넣기를 통한 대량 회원 파싱
  /// 지원 예시:
  /// - "홍길동" (이름만 입력 시 기본값 초심/남성/정회원 적용)
  /// - "김민수 남 A"
  /// - "이영희 F B조 010-1234-5678"
  /// - "박찬호 남 C 게스트"
  List<Member> parseBatchMembersText(
    String rawText, {
    String? defaultClubId,
  }) {
    final lines = rawText.split(RegExp(r'\r?\n'));
    final result = <Member>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 쉼표나 공백으로 토큰 분리
      final tokens = line
          .replaceAll(',', ' ')
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

      if (tokens.isEmpty) continue;

      final name = tokens[0];
      Gender gender = Gender.male;
      Tier tier = Tier.novice;
      MemberRole role = MemberRole.member;
      bool isGuest = false;
      String? phoneNumber;

      for (int i = 1; i < tokens.length; i++) {
        final token = tokens[i].trim();
        final lower = token.toLowerCase();

        // 전화번호 확인 (숫자 및 하이픈)
        if (RegExp(r'^01[0-9]-?[0-9]{3,4}-?[0-9]{4}$').hasMatch(token)) {
          phoneNumber = normalizePhoneNumber(token);
          continue;
        }

        // 게스트 여부 확인
        if (lower == '게스트' || lower == 'guest') {
          isGuest = true;
          continue;
        }

        // 회원 등급 / 직책 확인
        if (token == '준회원' || lower == 'associate') {
          role = MemberRole.associate;
          continue;
        }
        if (token == '정회원' || token == '회원') {
          role = MemberRole.member;
          continue;
        }
        if (token == '회장') {
          role = MemberRole.president;
          continue;
        }
        if (token == '부회장') {
          role = MemberRole.vicePresident;
          continue;
        }
        if (token == '총무') {
          role = MemberRole.manager;
          continue;
        }
        if (token == '경기이사') {
          role = MemberRole.matchDirector;
          continue;
        }

        // 성별 확인
        if (token == '남' || token == '남성' || lower == 'm' || lower == 'male') {
          gender = Gender.male;
          continue;
        }
        if (token == '여' || token == '여성' || lower == 'f' || lower == 'female') {
          gender = Gender.female;
          continue;
        }

        // 급수 확인
        final parsedTier = Tier.fromString(token);
        if (parsedTier != Tier.novice || token.contains('초심') || lower.contains('novice')) {
          tier = parsedTier;
          continue;
        }
      }

      result.add(
        Member(
          id: _uuid.v4(),
          clubId: defaultClubId,
          name: name,
          gender: gender,
          tier: tier,
          role: role,
          isGuest: isGuest,
          phoneNumber: phoneNumber,
        ),
      );
    }

    return result;
  }

  /// 급수별 인원 수 통계 반환
  Map<Tier, int> getTierCounts(List<Member> members) {
    final map = <Tier, int>{for (var t in Tier.values) t: 0};
    for (final m in members) {
      map[m.tier] = (map[m.tier] ?? 0) + 1;
    }
    return map;
  }
}

