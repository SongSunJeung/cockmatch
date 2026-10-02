import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/providers.dart';

/// 텍스트 복사/붙여넣기를 통한 회원 대량 일괄 등록 팝업 다이얼로그
///
/// 가상 키보드 오픈 시 인셋에 유연하게 대응하며,
/// 백엔드(Firebase/Supabase) 교체에 대비해 파싱 서비스 및 상태 로직을 독립 분리합니다.
class BatchMemberAddDialog extends ConsumerStatefulWidget {
  final String? initialText;

  const BatchMemberAddDialog({
    super.key,
    this.initialText,
  });

  @override
  ConsumerState<BatchMemberAddDialog> createState() => _BatchMemberAddDialogState();
}

class _BatchMemberAddDialogState extends ConsumerState<BatchMemberAddDialog> {
  late final TextEditingController _batchCtrl;

  @override
  void initState() {
    super.initState();
    _batchCtrl = TextEditingController(
      text: widget.initialText ??
          '''김영수 남 A 정회원
이정민 여 B조 010-2345-6789 총무
박현우 남 C 준회원
최유나 여 초심''',
    );
  }

  @override
  void dispose() {
    _batchCtrl.dispose();
    super.dispose();
  }

  void _handleBatchSubmit() {
    final text = _batchCtrl.text.trim();
    if (text.isEmpty) return;

    final currentClubId = ref.read(currentClubIdProvider);
    final clubService = ref.read(clubServiceProvider);
    final parsed = clubService.parseBatchMembersText(
      text,
      defaultClubId: currentClubId,
    );

    if (parsed.isNotEmpty) {
      ref.read(membersProvider.notifier).addBatch(parsed);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${parsed.length}명의 회원이 일괄 등록되었습니다!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('인식 가능한 회원 정보가 없습니다. 이름 형식을 확인해 주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 헤더 (아이콘 + 타이틀)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelMint.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.playlist_add_check_rounded,
                      color: AppTheme.primaryMint,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '명단 텍스트 대량 등록',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: AppTheme.textDark,
                      ),
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
              const SizedBox(height: 12),

              // 2. 입력 형식 가이드 안내 문구
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '카카오톡 단체방이나 엑셀에서 복사한 명단을 아래에 붙여넣으세요.\n줄마다 "이름 성별 급수 [전화번호] [정회원/준회원/직책]" 형식으로 자동 인식됩니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 3. 다중 라인 입력 필드 (키보드 인셋 대응 및 고정 여백)
              TextField(
                controller: _batchCtrl,
                enableInteractiveSelection: true,
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState),
                maxLines: 7,
                minLines: 4,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 13, height: 1.4),
                decoration: InputDecoration(
                  hintText: '예:\n홍길동 남 A 정회원\n김민수 여 B 010-1234-5678 총무\n이초심 남 초심 준회원',
                  hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primaryMint, width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 4. 하단 액션 버튼 영역 (취소 / 일괄 파싱 & 등록)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '취소',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryMint,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      '일괄 파싱 & 등록',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: _handleBatchSubmit,
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
