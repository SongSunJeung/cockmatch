import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../core/constants/enums.dart';
import 'member.dart';

/// 클럽 기본 회비 정책 및 입금 계좌 + 회칙/메모 모델
class ClubFeePolicy {
  final String clubId;
  final int defaultMonthlyFee; // 기본 월 회비 (예: 30000)
  final int paymentDueDay; // 정기 납부 마감일 (예: 25 -> 매월 25일)
  final String bankName; // 은행명 (예: 카카오뱅크)
  final String accountNumber; // 계좌번호 (예: 3333-01-2345678)
  final String accountHolder; // 예금주 (예: 김민수(메가배드민턴))
  final String rulesAndMemo; // 클럽 회비 회칙 & 메모란 (아코디언 영구 저장)

  const ClubFeePolicy({
    required this.clubId,
    this.defaultMonthlyFee = 30000,
    this.paymentDueDay = 25,
    this.bankName = '카카오뱅크',
    this.accountNumber = '3333-01-5829104',
    this.accountHolder = '정수진(총무)',
    this.rulesAndMemo = defaultRulesText,
  });

  static const String defaultRulesText =
      '1. 정기 월 회비: 월 30,000원 (매월 25일 납부 마감)\n'
      '2. 가족/부부 할인 기준: 직계가족·부부 동반 가입 시 1인당 월 20,000원 차등 적용\n'
      '3. 휴면(휴회) 규정: 부상·출장 등으로 최소 1개월 이상 사전 휴회 신청 시 해당 월 회비 자동 면제\n'
      '4. 임원 면제 규정: 회장·총무 등 클럽 핵심 운영진은 회칙 제12조에 의거 월 회비 면제\n'
      '5. 미납 제재 안내: 연속 3개월 이상 미납 시 정기모임 대진 배정 보류 및 운영진 개별 안내';

  String get formattedDefaultFee => '${NumberFormat('#,###').format(defaultMonthlyFee)}원';

  String get formattedDueDay => '매월 $paymentDueDay일';

  String get formattedBankAccount =>
      '$bankName $accountNumber (예금주: $accountHolder)';

  ClubFeePolicy copyWith({
    String? clubId,
    int? defaultMonthlyFee,
    int? paymentDueDay,
    String? bankName,
    String? accountNumber,
    String? accountHolder,
    String? rulesAndMemo,
  }) {
    return ClubFeePolicy(
      clubId: clubId ?? this.clubId,
      defaultMonthlyFee: defaultMonthlyFee ?? this.defaultMonthlyFee,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountHolder: accountHolder ?? this.accountHolder,
      rulesAndMemo: rulesAndMemo ?? this.rulesAndMemo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clubId': clubId,
      'defaultMonthlyFee': defaultMonthlyFee,
      'paymentDueDay': paymentDueDay,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountHolder': accountHolder,
      'rulesAndMemo': rulesAndMemo,
    };
  }

  factory ClubFeePolicy.fromJson(Map<String, dynamic> json) {
    return ClubFeePolicy(
      clubId: json['clubId'] as String? ?? 'club_mega',
      defaultMonthlyFee: json['defaultMonthlyFee'] as int? ?? 30000,
      paymentDueDay: json['paymentDueDay'] as int? ?? 25,
      bankName: json['bankName'] as String? ?? '카카오뱅크',
      accountNumber: json['accountNumber'] as String? ?? '3333-01-5829104',
      accountHolder: json['accountHolder'] as String? ?? '정수진(총무)',
      rulesAndMemo: json['rulesAndMemo'] as String? ?? defaultRulesText,
    );
  }
}

/// 개별 회원의 특정 연·월 회비 납부 셀 상세 기록
class MonthlyFeeRecord {
  final FeeStatus status; // paid(완납), unpaid(미납), exempt(면제/휴면)
  final int? paidAmount; // 실제 납부 금액 (null이면 회원 기준 월 회비 적용)
  final String? paidDate; // 입금일자 (예: 2026.09.18)
  final String? memo; // 메모 (예: 자동이체, 가족할인 적용, 엘보 부상 휴회 등)
  final bool isManualOverride; // 총무가 직접 셀을 탭하여 상태를 지정했는지 여부

  const MonthlyFeeRecord({
    required this.status,
    this.paidAmount,
    this.paidDate,
    this.memo,
    this.isManualOverride = false,
  });

  MonthlyFeeRecord copyWith({
    FeeStatus? status,
    int? paidAmount,
    bool clearPaidAmount = false,
    String? paidDate,
    bool clearPaidDate = false,
    String? memo,
    bool clearMemo = false,
    bool? isManualOverride,
  }) {
    return MonthlyFeeRecord(
      status: status ?? this.status,
      paidAmount: clearPaidAmount ? null : (paidAmount ?? this.paidAmount),
      paidDate: clearPaidDate ? null : (paidDate ?? this.paidDate),
      memo: clearMemo ? null : (memo ?? this.memo),
      isManualOverride: isManualOverride ?? this.isManualOverride,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'paidAmount': paidAmount,
      'paidDate': paidDate,
      'memo': memo,
      'isManualOverride': isManualOverride,
    };
  }

  factory MonthlyFeeRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? FeeStatus.unpaid.name;
    final parsedStatus = FeeStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => FeeStatus.unpaid,
    );
    return MonthlyFeeRecord(
      status: parsedStatus,
      paidAmount: json['paidAmount'] as int?,
      paidDate: json['paidDate'] as String?,
      memo: json['memo'] as String?,
      isManualOverride: json['isManualOverride'] as bool? ?? false,
    );
  }
}

/// 연간/월별 회비 납부 현황표 상단 조회 필터
enum FeeLedgerFilter {
  all('전체 보기'),
  currentMonthUnpaid('당월 미납자만 보기'),
  exemptOrResting('휴면/면제 회원만 보기'),
  familyDiscount('👨‍👩‍👧 가족할인 회원');

  final String label;
  const FeeLedgerFilter(this.label);
}

/// 특정 월의 회비 수납 대시보드 통계 요약
class MonthlyFeeSummary {
  final int year;
  final int month;
  final List<Member> paidMembers;
  final List<Member> unpaidMembers;
  final List<Member> exemptMembers;
  final int totalCollectedAmount;
  final int totalExpectedAmount;

  const MonthlyFeeSummary({
    required this.year,
    required this.month,
    required this.paidMembers,
    required this.unpaidMembers,
    required this.exemptMembers,
    required this.totalCollectedAmount,
    required this.totalExpectedAmount,
  });

  int get paidCount => paidMembers.length;
  int get unpaidCount => unpaidMembers.length;
  int get exemptCount => exemptMembers.length;
  int get billableCount => paidCount + unpaidCount;

  /// 당월 수납률 (0.0 ~ 100.0)
  double get collectionRate {
    if (billableCount <= 0) return 100.0;
    return (paidCount / billableCount) * 100.0;
  }

  /// 당월 미납 총액 (목표 수납 총액 - 실제 수납 총액)
  int get totalUnpaidAmount =>
      (totalExpectedAmount - totalCollectedAmount).clamp(0, 999999999);

  String get formattedCollectedAmount =>
      '${NumberFormat('#,###').format(totalCollectedAmount)}원';

  String get formattedExpectedAmount =>
      '${NumberFormat('#,###').format(totalExpectedAmount)}원';

  String get formattedUnpaidAmount =>
      '${NumberFormat('#,###').format(totalUnpaidAmount)}원';
}

/// 연간/월별 회비 납부 현황표 계산 및 프로필 자동 연동 유틸리티
class FeeLedgerCalculator {
  static final NumberFormat _currencyFmt = NumberFormat('#,###');

  static String formatWon(int amount) => '${_currencyFmt.format(amount)}원';

  /// 장부 맵 키 생성 (`clubId_year_memberId_month`)
  static String buildCellKey({
    required String clubId,
    required int year,
    required String memberId,
    required int month,
  }) {
    return '${clubId}_${year}_${memberId}_$month';
  }

  /// 회원 프로필과 클럽 기본 회비 정책을 연동하여 [월 회비 기준액] 계산
  static int getMemberStandardMonthlyFee(Member member, ClubFeePolicy policy) {
    final isExemptPolicy = member.feePolicy == FeePolicyType.exempt ||
        member.feeStatus == FeeStatus.exempt;
    if (isExemptPolicy && member.isPermanentExempt) {
      return 0;
    }
    if (member.feePolicy == FeePolicyType.discounted) {
      return member.customFeeAmount ?? policy.defaultMonthlyFee;
    }
    return policy.defaultMonthlyFee;
  }

  /// 회원 프로필 기반 [월 회비 기준액] 서브 라벨 (예: '가족할인', '영구면제', '기본회비')
  static String getMemberFeePolicySubLabel(Member member, ClubFeePolicy policy) {
    if (member.status == MemberStatus.resting) {
      return '휴면(휴회)';
    }
    if (member.feePolicy == FeePolicyType.exempt ||
        member.feeStatus == FeeStatus.exempt) {
      if (member.isPermanentExempt) {
        return '영구 면제';
      }
      if (member.exemptStartDate != null &&
          member.exemptStartDate!.trim().isNotEmpty &&
          member.exemptUntilDate != null &&
          member.exemptUntilDate!.trim().isNotEmpty) {
        return '${member.exemptStartDate}~${member.exemptUntilDate} 면제';
      }
      return member.exemptUntilDate != null
          ? '~${member.exemptUntilDate} 면제'
          : '기간 면제';
    }
    if (member.feePolicy == FeePolicyType.discounted) {
      return member.customFeeLabel?.trim().isNotEmpty == true
          ? member.customFeeLabel!.trim()
          : '차등/할인';
    }
    return '기본 회비';
  }

  /// 가족할인 / 차등할인 회원 여부 판별
  static bool isFamilyDiscountMember(Member member, ClubFeePolicy policy) {
    if (member.feePolicy == FeePolicyType.discounted) return true;
    if (member.customFeeLabel != null &&
        member.customFeeLabel!.contains('가족')) {
      return true;
    }
    if (member.customFeeAmount != null &&
        member.customFeeAmount! > 0 &&
        member.customFeeAmount! < policy.defaultMonthlyFee) {
      return true;
    }
    return false;
  }

  /// 날짜 문자열('2026.09.01' 또는 '2026-09-01')에서 (year * 100 + month) 정수 추출
  static int? _parseYearMonth(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    final cleaned = dateStr.trim().replaceAll('-', '.').replaceAll('/', '.');
    final parts = cleaned.split('.');
    if (parts.length < 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return null;
    return y * 100 + m;
  }

  /// 회원 프로필의 [면제 기간] 또는 [휴면(휴회) 기간]에 속하는 월인지 자동 판별
  /// - 해당 월이 자동 면제/휴면 대상이면 그 사유 문자열을 반환하고, 아니면 null 반환
  static String? resolveAutoExemptReason(Member member, int year, int month) {
    final targetYm = year * 100 + month;

    // 1. 회비 면제 정책 (영구 면제 또는 기간 지정 면제)
    if (member.feePolicy == FeePolicyType.exempt ||
        member.feeStatus == FeeStatus.exempt) {
      if (member.isPermanentExempt) {
        return member.isExecutive
            ? '${member.displayRoleLabel} 회비 면제'
            : '영구 회비 면제';
      }
      final startYm = _parseYearMonth(member.exemptStartDate);
      final untilYm = _parseYearMonth(member.exemptUntilDate);
      final afterStart = startYm == null || targetYm >= startYm;
      final beforeEnd = untilYm == null || targetYm <= untilYm;
      if (afterStart && beforeEnd) {
        if (member.exemptStartDate != null &&
            member.exemptStartDate!.trim().isNotEmpty &&
            member.exemptUntilDate != null &&
            member.exemptUntilDate!.trim().isNotEmpty) {
          return '기간 면제 (${member.exemptStartDate}~${member.exemptUntilDate})';
        }
        return member.exemptUntilDate != null
            ? '기간 면제 (~${member.exemptUntilDate})'
            : '기간 지정 면제';
      }
    }

    // 2. 휴면(휴회) 기간 자동 연동
    final startYm = _parseYearMonth(member.restingStartDate);
    final returnYm = _parseYearMonth(member.restingReturnDate);

    if (startYm != null && returnYm != null) {
      if (targetYm >= startYm && targetYm <= returnYm) {
        final reason = member.restingReason?.trim();
        return reason != null && reason.isNotEmpty
            ? '휴회 기간 ($reason)'
            : '휴회 기간 (${member.restingStartDate}~${member.restingReturnDate})';
      }
    } else if (startYm != null && member.status == MemberStatus.resting) {
      if (targetYm >= startYm) {
        final reason = member.restingReason?.trim();
        return reason != null && reason.isNotEmpty
            ? '휴면 중 ($reason)'
            : '휴면 중 (${member.restingStartDate}~)';
      }
    } else if (member.status == MemberStatus.resting) {
      final reason = member.restingReason?.trim();
      return reason != null && reason.isNotEmpty ? '휴면 중 ($reason)' : '휴면(휴회) 회원';
    }

    return null;
  }

  /// 특정 회원의 (year, month) 최종 납부 상태 레코드 반환
  /// - 총무가 수동 오버라이드한 레코드가 있으면 최우선 적용
  /// - 회원 프로필상 면제/휴면 기간에 해당하면 시스템이 자동으로 '면제/휴면(FeeStatus.exempt)' 세팅
  /// - 저장된 레코드가 있으면 해당 레코드 반환
  static MonthlyFeeRecord resolveCellRecord({
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required String clubId,
    required int year,
    required int month,
    required Member member,
    required ClubFeePolicy policy,
  }) {
    final key = buildCellKey(
      clubId: clubId,
      year: year,
      memberId: member.id,
      month: month,
    );
    final stored = ledgerMap[key];

    if (stored != null && stored.isManualOverride) {
      return stored;
    }

    final autoExemptReason = resolveAutoExemptReason(member, year, month);
    if (autoExemptReason != null) {
      return MonthlyFeeRecord(
        status: FeeStatus.exempt,
        paidAmount: 0,
        paidDate: stored?.paidDate,
        memo: stored?.memo ?? autoExemptReason,
        isManualOverride: false,
      );
    }

    if (stored != null) {
      return stored;
    }

    // 기본값: 미납 (단, 9월 등 기준월에서 member.feeStatus가 완납이면 반영)
    final standardFee = getMemberStandardMonthlyFee(member, policy);
    return MonthlyFeeRecord(
      status: FeeStatus.unpaid,
      paidAmount: standardFee,
    );
  }

  /// 회원이 특정 연도에 실제로 납부해야 할 월별 납부 인정 금액 반환
  static int resolveMonthPaidAmount({
    required MonthlyFeeRecord record,
    required Member member,
    required ClubFeePolicy policy,
  }) {
    if (record.status != FeeStatus.paid) return 0;
    return record.paidAmount ?? getMemberStandardMonthlyFee(member, policy);
  }

  /// 회원의 1월~12월 [연간 납부 합계] 계산
  static int calculateMemberAnnualTotal({
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required String clubId,
    required int year,
    required Member member,
    required ClubFeePolicy policy,
  }) {
    int sum = 0;
    for (int m = 1; m <= 12; m++) {
      final rec = resolveCellRecord(
        ledgerMap: ledgerMap,
        clubId: clubId,
        year: year,
        month: m,
        member: member,
        policy: policy,
      );
      sum += resolveMonthPaidAmount(
        record: rec,
        member: member,
        policy: policy,
      );
    }
    return sum;
  }

  /// 회원의 1월~12월 중 완납 개월 수 계산
  static int calculateMemberPaidMonthsCount({
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required String clubId,
    required int year,
    required Member member,
    required ClubFeePolicy policy,
  }) {
    int count = 0;
    for (int m = 1; m <= 12; m++) {
      final rec = resolveCellRecord(
        ledgerMap: ledgerMap,
        clubId: clubId,
        year: year,
        month: m,
        member: member,
        policy: policy,
      );
      if (rec.status == FeeStatus.paid) count++;
    }
    return count;
  }

  /// 특정 연·월의 전체 클럽 회비 수납 통계 요약 계산
  static MonthlyFeeSummary calculateMonthlySummary({
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required String clubId,
    required int year,
    required int month,
    required List<Member> members,
    required ClubFeePolicy policy,
  }) {
    final paidMembers = <Member>[];
    final unpaidMembers = <Member>[];
    final exemptMembers = <Member>[];
    int totalCollected = 0;
    int totalExpected = 0;

    for (final member in members) {
      if (member.isGuest) continue;
      final rec = resolveCellRecord(
        ledgerMap: ledgerMap,
        clubId: clubId,
        year: year,
        month: month,
        member: member,
        policy: policy,
      );
      final standardFee = getMemberStandardMonthlyFee(member, policy);

      switch (rec.status) {
        case FeeStatus.paid:
          paidMembers.add(member);
          final paidAmt = rec.paidAmount ?? standardFee;
          totalCollected += paidAmt;
          totalExpected += paidAmt;
          break;
        case FeeStatus.unpaid:
          unpaidMembers.add(member);
          totalExpected += standardFee;
          break;
        case FeeStatus.exempt:
          exemptMembers.add(member);
          break;
      }
    }

    return MonthlyFeeSummary(
      year: year,
      month: month,
      paidMembers: paidMembers,
      unpaidMembers: unpaidMembers,
      exemptMembers: exemptMembers,
      totalCollectedAmount: totalCollected,
      totalExpectedAmount: totalExpected,
    );
  }

  /// [📢 미납자 카톡 독려 문구 복사] 정중한 안내 메시지 생성
  static String buildKakaoUnpaidReminderMessage({
    required String clubName,
    required int year,
    required int month,
    required MonthlyFeeSummary summary,
    required ClubFeePolicy policy,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📢 [$clubName] $year년 $month월 정기 회비 납부 안내');
    buffer.writeln('');
    buffer.writeln('안녕하세요, $clubName 총무입니다. 😊');
    buffer.writeln('즐겁고 원활한 클럽 운영을 위해 $month월 정기 회비 납부를 정중히 안내해 드립니다.');
    buffer.writeln('');
    buffer.writeln('💳 [회비 입금 계좌 안내]');
    buffer.writeln('• 은행/계좌: ${policy.bankName} ${policy.accountNumber}');
    buffer.writeln('• 예금주: ${policy.accountHolder}');
    buffer.writeln('• 기본 월 회비: ${policy.formattedDefaultFee} (차등/가족할인 대상자는 해당 금액)');
    buffer.writeln('• 정기 납부 마감일: 매월 ${policy.paymentDueDay}일');
    buffer.writeln('');

    if (summary.unpaidMembers.isEmpty) {
      buffer.writeln('🎉 현재 $month월 대상 회원 전원 완납되었습니다! 협조해 주셔서 감사합니다.');
    } else {
      buffer.writeln('📌 [$month월 미납 확인 대상 회원 (${summary.unpaidCount}명)]');
      final formattedNames = summary.unpaidMembers.map((m) {
        final fee = getMemberStandardMonthlyFee(m, policy);
        if (m.feePolicy == FeePolicyType.discounted) {
          return '${m.name}(${formatWon(fee)})';
        }
        return m.name;
      }).join(', ');
      buffer.writeln(formattedNames);
      buffer.writeln('');
      buffer.writeln('※ 이미 입금하셨거나 자동이체 내역 확인이 필요하신 회원님께서는 총무에게 말씀해 주시면 즉시 반영하겠습니다. 감사합니다! 🏸');
    }

    return buffer.toString().trim();
  }

  /// [📊 엑셀 다운로드] 1월~12월 연간 장부 CSV 문자열 생성
  static String buildAnnualLedgerCsvString({
    required String clubName,
    required String clubId,
    required int year,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
  }) {
    final rows = <List<dynamic>>[];

    // 상단 메타 헤더
    rows.add([
      '$clubName $year년 연간/월별 회비 납부 현황표',
      '기본 월 회비: ${policy.formattedDefaultFee}',
      '납부 마감일: ${policy.formattedDueDay}',
      '입금 계좌: ${policy.formattedBankAccount}',
    ]);
    rows.add([]);

    // 테이블 컬럼 헤더
    rows.add([
      '이름',
      '직책',
      '활동상태',
      '급수',
      '회비구분',
      '월회비기준액',
      for (int m = 1; m <= 12; m++) '$m월',
      '연간납부개월',
      '연간납부합계',
      '비고(면제/휴면사유)',
    ]);

    int grandTotalAnnual = 0;

    for (final member in members) {
      if (member.isGuest) continue;
      final standardFee = getMemberStandardMonthlyFee(member, policy);
      final policySubLabel = getMemberFeePolicySubLabel(member, policy);
      final monthCells = <String>[];
      int memberAnnualTotal = 0;
      int paidMonths = 0;

      for (int m = 1; m <= 12; m++) {
        final rec = resolveCellRecord(
          ledgerMap: ledgerMap,
          clubId: clubId,
          year: year,
          month: m,
          member: member,
          policy: policy,
        );
        switch (rec.status) {
          case FeeStatus.paid:
            final amt = resolveMonthPaidAmount(
              record: rec,
              member: member,
              policy: policy,
            );
            memberAnnualTotal += amt;
            paidMonths++;
            monthCells.add('완납(${_currencyFmt.format(amt)})');
            break;
          case FeeStatus.unpaid:
            monthCells.add('미납');
            break;
          case FeeStatus.exempt:
            monthCells.add('면제/휴면');
            break;
        }
      }

      grandTotalAnnual += memberAnnualTotal;

      rows.add([
        member.name,
        member.displayRoleLabel,
        member.status.label,
        member.tier.label,
        policySubLabel,
        standardFee,
        ...monthCells,
        '$paidMonths개월',
        memberAnnualTotal,
        member.restingReason ?? member.memo ?? '',
      ]);
    }

    // 하단 합계 행
    final monthlyTotals = <String>[];
    for (int m = 1; m <= 12; m++) {
      final summary = calculateMonthlySummary(
        ledgerMap: ledgerMap,
        clubId: clubId,
        year: year,
        month: m,
        members: members,
        policy: policy,
      );
      monthlyTotals.add(
        '수납 ${summary.formattedCollectedAmount} (${summary.paidCount}명)',
      );
    }

    rows.add([
      '월별 수납 합계',
      '-',
      '-',
      '-',
      '-',
      '-',
      ...monthlyTotals,
      '-',
      grandTotalAnnual,
      '',
    ]);

    return csv.encode(rows);
  }

  /// [📊 엑셀 다운로드] 한글 깨짐 방지용 UTF-8 BOM 바이트 배열 생성
  static Uint8List buildAnnualLedgerCsvBytes({
    required String clubName,
    required String clubId,
    required int year,
    required List<Member> members,
    required Map<String, MonthlyFeeRecord> ledgerMap,
    required ClubFeePolicy policy,
  }) {
    final csvString = buildAnnualLedgerCsvString(
      clubName: clubName,
      clubId: clubId,
      year: year,
      members: members,
      ledgerMap: ledgerMap,
      policy: policy,
    );
    final utf8Bytes = utf8.encode(csvString);
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8Bytes]);
  }
}
