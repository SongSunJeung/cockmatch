/// 클럽(모임) 정보 모델
/// Firestore 경로: clubs/{clubId}
class Club {
  final String id;
  final String ownerId; // 모임장 UID
  final String clubName;
  final String? description; // 클럽 설명/모임 일정
  final int memberCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Club({
    required this.id,
    required this.ownerId,
    required this.clubName,
    this.description,
    this.memberCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore 저장용 Map 변환
  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'clubName': clubName,
      if (description != null) 'description': description,
      'memberCount': memberCount,
      'createdAt': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  /// Firestore 데이터로부터 인스턴스 복원
  factory Club.fromMap(Map<String, dynamic> map, {required String id}) {
    return Club(
      id: id,
      ownerId: (map['ownerId'] as String?) ?? '',
      clubName: (map['clubName'] as String?) ?? '이름 없는 클럽',
      description: map['description'] as String?,
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  Club copyWith({
    String? id,
    String? ownerId,
    String? clubName,
    String? description,
    int? memberCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Club(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      clubName: clubName ?? this.clubName,
      description: description ?? this.description,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Club && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Club(id: $id, name: $clubName, members: $memberCount, owner: $ownerId)';
  }
}
