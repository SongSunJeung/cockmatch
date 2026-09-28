import 'dart:convert';

/// [PRO 장부] 행사비/모임비 금전출납부의 개별 수입/지출 내역 모델
class EventExpenseItem {
  final String id;
  final String eventId;
  final String title;
  final int amount;
  final bool isIncome; // true: 수입, false: 지출
  final String date;
  final String? memo;
  final String? receiptBase64;
  final String? receiptFileName;
  final DateTime createdAt;

  const EventExpenseItem({
    required this.id,
    required this.eventId,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.date,
    this.memo,
    this.receiptBase64,
    this.receiptFileName,
    required this.createdAt,
  });

  bool get hasReceipt =>
      receiptBase64 != null && receiptBase64!.trim().isNotEmpty;

  EventExpenseItem copyWith({
    String? id,
    String? eventId,
    String? title,
    int? amount,
    bool? isIncome,
    String? date,
    String? memo,
    String? receiptBase64,
    String? receiptFileName,
    DateTime? createdAt,
  }) {
    return EventExpenseItem(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      isIncome: isIncome ?? this.isIncome,
      date: date ?? this.date,
      memo: memo ?? this.memo,
      receiptBase64: receiptBase64 ?? this.receiptBase64,
      receiptFileName: receiptFileName ?? this.receiptFileName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'eventId': eventId,
      'title': title,
      'amount': amount,
      'isIncome': isIncome,
      'date': date,
      'memo': memo,
      'receiptBase64': receiptBase64,
      'receiptFileName': receiptFileName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory EventExpenseItem.fromMap(Map<String, dynamic> map) {
    return EventExpenseItem(
      id: map['id'] as String? ?? '',
      eventId: map['eventId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      isIncome: map['isIncome'] as bool? ?? false,
      date: map['date'] as String? ?? '',
      memo: map['memo'] as String?,
      receiptBase64: map['receiptBase64'] as String?,
      receiptFileName: map['receiptFileName'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory EventExpenseItem.fromJson(String source) =>
      EventExpenseItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// [PRO 장부] 특별 행사 / 정기 모임 정산 단위 (행사비/모임비 금전출납부)
class ClubEvent {
  final String id;
  final String clubId;
  final String title;
  final String eventDate;
  final String? linkedSessionId;
  final String? memo;
  final List<EventExpenseItem> items;
  final DateTime createdAt;

  const ClubEvent({
    required this.id,
    required this.clubId,
    required this.title,
    required this.eventDate,
    this.linkedSessionId,
    this.memo,
    this.items = const [],
    required this.createdAt,
  });

  int get totalIncome => items
      .where((i) => i.isIncome)
      .fold<int>(0, (sum, i) => sum + i.amount);

  int get totalExpense => items
      .where((i) => !i.isIncome)
      .fold<int>(0, (sum, i) => sum + i.amount);

  int get balance => totalIncome - totalExpense;

  int get incomeCount => items.where((i) => i.isIncome).length;
  int get expenseCount => items.where((i) => !i.isIncome).length;

  ClubEvent copyWith({
    String? id,
    String? clubId,
    String? title,
    String? eventDate,
    String? linkedSessionId,
    String? memo,
    List<EventExpenseItem>? items,
    DateTime? createdAt,
  }) {
    return ClubEvent(
      id: id ?? this.id,
      clubId: clubId ?? this.clubId,
      title: title ?? this.title,
      eventDate: eventDate ?? this.eventDate,
      linkedSessionId: linkedSessionId ?? this.linkedSessionId,
      memo: memo ?? this.memo,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clubId': clubId,
      'title': title,
      'eventDate': eventDate,
      'linkedSessionId': linkedSessionId,
      'memo': memo,
      'items': items.map((i) => i.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ClubEvent.fromMap(Map<String, dynamic> map) {
    return ClubEvent(
      id: map['id'] as String? ?? '',
      clubId: map['clubId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      eventDate: map['eventDate'] as String? ?? '',
      linkedSessionId: map['linkedSessionId'] as String?,
      memo: map['memo'] as String?,
      items: (map['items'] as List<dynamic>?)
              ?.map((item) =>
                  EventExpenseItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ClubEvent.fromJson(String source) =>
      ClubEvent.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// [PRO 장부] 행사비 출납부 정산 및 CSV/Excel 내보내기 헬퍼
class EventExpenseCalculator {
  EventExpenseCalculator._();

  static String buildEventCsvString(ClubEvent event) {
    final buffer = StringBuffer();
    buffer.writeln('구분,일자,항목명,금액(원),메모,영수증증빙');
    for (final item in event.items) {
      final typeStr = item.isIncome ? '수입' : '지출';
      final amountStr = item.amount.toString();
      final memoStr = (item.memo ?? '').replaceAll('"', '""');
      final receiptStr = item.hasReceipt ? '증빙첨부' : '-';
      buffer.writeln(
        '"$typeStr","${item.date}","${item.title.replaceAll('"', '""')}",$amountStr,"$memoStr","$receiptStr"',
      );
    }
    buffer.writeln('');
    buffer.writeln('요약,,,총 수입,${event.totalIncome},');
    buffer.writeln('요약,,,총 지출,${event.totalExpense},');
    buffer.writeln('요약,,,최종 잔액,${event.balance},');
    return buffer.toString();
  }

  static List<int> buildEventCsvBytes(ClubEvent event) {
    final csvStr = buildEventCsvString(event);
    final bom = [0xEF, 0xBB, 0xBF];
    final encoded = utf8.encode(csvStr);
    return [...bom, ...encoded];
  }
}
