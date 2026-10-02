import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

/// 게스트 즉시 추가 다이얼로그 (일회성 참석자)
///
/// 모바일 가상 키보드 오픈 시 키보드 인셋 대응 및 자동 스크롤(Scrollable.ensureVisible)을 지원하여,
/// 상단 잘림과 텍스트필드 가림 문제를 방지합니다.
class GuestAddDialog extends ConsumerStatefulWidget {
  final String clubId;
  final void Function(Member newGuest)? onGuestAdded;

  const GuestAddDialog({
    super.key,
    required this.clubId,
    this.onGuestAdded,
  });

  @override
  ConsumerState<GuestAddDialog> createState() => _GuestAddDialogState();
}

class _GuestAddDialogState extends ConsumerState<GuestAddDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _clubCtrl;
  late final TextEditingController _phoneCtrl;

  late final FocusNode _nameFocusNode;
  late final FocusNode _clubFocusNode;
  late final FocusNode _phoneFocusNode;

  late final ScrollController _scrollController;

  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _clubKey = GlobalKey();
  final GlobalKey _phoneKey = GlobalKey();

  Gender _selectedGender = Gender.male;
  Tier _selectedTier = Tier.novice;
  FeeStatus _selectedFeeStatus = FeeStatus.paid;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _clubCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();

    _nameFocusNode = FocusNode();
    _clubFocusNode = FocusNode();
    _phoneFocusNode = FocusNode();

    _scrollController = ScrollController();

    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus) {
        _scrollToKey(_nameKey);
      }
    });

    _clubFocusNode.addListener(() {
      if (_clubFocusNode.hasFocus) {
        _scrollToKey(_clubKey);
      }
    });

    _phoneFocusNode.addListener(() {
      if (_phoneFocusNode.hasFocus) {
        _scrollToKey(_phoneKey);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _clubCtrl.dispose();
    _phoneCtrl.dispose();

    _nameFocusNode.dispose();
    _clubFocusNode.dispose();
    _phoneFocusNode.dispose();

    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        final targetContext = key.currentContext;
        if (targetContext != null && targetContext.mounted) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: 0.5,
          );
        }
      });
    });
  }

  void _handleSubmit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('게스트 이름을 입력해 주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final newGuest = Member(
      id: 'guest_${const Uuid().v4().substring(0, 8)}',
      clubId: widget.clubId,
      name: name,
      gender: _selectedGender,
      tier: _selectedTier,
      isGuest: true,
      feeStatus: _selectedFeeStatus,
      homeClub: _clubCtrl.text.trim().isEmpty ? '게스트' : _clubCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      status: MemberStatus.active,
    );

    if (widget.onGuestAdded != null) {
      widget.onGuestAdded!(newGuest);
    } else {
      ref.read(membersProvider.notifier).addMember(newGuest);
      ref.read(sessionProvider.notifier).addAttendee(newGuest.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('게스트 $name 님이 일정/모임에 추가되었습니다!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 헤더 (아이콘 + 타이틀 + 닫기 버튼)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelMint.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: AppTheme.primaryMint,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '게스트 즉시 추가',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '오늘 모임에만 참가하는 일회성 게스트입니다.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. 이름 입력 필드
              TextField(
                key: _nameKey,
                controller: _nameCtrl,
                focusNode: _nameFocusNode,
                enableInteractiveSelection: true,
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                ),
                decoration: InputDecoration(
                  labelText: '이름 (필수)',
                  hintText: '예: 홍길동',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onTap: () => _scrollToKey(_nameKey),
              ),
              const SizedBox(height: 12),

              // 3. 성별 선택
              Row(
                children: [
                  const Text('성별: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('남성', style: TextStyle(fontSize: 12)),
                    selected: _selectedGender == Gender.male,
                    selectedColor: AppTheme.pastelPeriwinkle,
                    onSelected: (val) => setState(() => _selectedGender = Gender.male),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('여성', style: TextStyle(fontSize: 12)),
                    selected: _selectedGender == Gender.female,
                    selectedColor: AppTheme.pastelRose,
                    onSelected: (val) => setState(() => _selectedGender = Gender.female),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 4. 급수 선택 드롭다운 & 빠른 선택 칩 (초심, D조, C조, B조, A조, S조)
              Row(
                children: [
                  const Text('급수: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  DropdownButton<Tier>(
                    value: _selectedTier,
                    items: Tier.values.map((t) {
                      return DropdownMenuItem(value: t, child: Text(t.label));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedTier = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Tier.novice,
                  Tier.d,
                  Tier.c,
                  Tier.b,
                  Tier.a,
                  Tier.s,
                ].map((tierOption) {
                  final isSelected = _selectedTier == tierOption;
                  return ChoiceChip(
                    key: Key('guest_form_tier_chip_${tierOption.code}'),
                    label: Text(
                      tierOption.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.getTierTextColor(tierOption),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryDark,
                    backgroundColor: AppTheme.getTierBgColor(tierOption),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _selectedTier = tierOption),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // 5. 원소속 클럽 입력 필드
              TextField(
                key: _clubKey,
                controller: _clubCtrl,
                focusNode: _clubFocusNode,
                enableInteractiveSelection: true,
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                ),
                decoration: InputDecoration(
                  labelText: '원소속 클럽 (선택, 예: 마포콕)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onTap: () => _scrollToKey(_clubKey),
              ),
              const SizedBox(height: 12),

              // 6. 연락처 입력 필드
              TextField(
                key: _phoneKey,
                controller: _phoneCtrl,
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                enableInteractiveSelection: true,
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                ),
                onChanged: (_) => setState(() {}),
                onTap: () => _scrollToKey(_phoneKey),
                decoration: InputDecoration(
                  labelText: '연락처 (선택)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _phoneCtrl.text.isNotEmpty
                      ? IconButton(
                          tooltip: '연락처 지우기',
                          icon: const Icon(Icons.clear_rounded, size: 18, color: AppTheme.textMuted),
                          onPressed: () {
                            _phoneCtrl.clear();
                            setState(() {});
                          },
                        )
                      : IconButton(
                          tooltip: '클립보드에서 붙여넣기',
                          icon: const Icon(Icons.content_paste_rounded, size: 18, color: AppTheme.primaryDark),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            final text = data?.text?.trim();
                            if (text != null && text.isNotEmpty) {
                              _phoneCtrl.text = text;
                              setState(() {});
                            }
                          },
                        ),
                ),
              ),
              const SizedBox(height: 14),

              // 7. 참가비 납부 상태 (완납 / 미납 / 면제)
              const Text('참가비 납부 상태', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: FeeStatus.values.map((statusOption) {
                  final isSelected = _selectedFeeStatus == statusOption;
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
                          if (val) setState(() => _selectedFeeStatus = statusOption);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // 8. 하단 버튼 영역 (취소 / 추가하기)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryMint,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _handleSubmit,
                    child: const Text(
                      '추가하기',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
}
