import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/club.dart';
import '../../../models/fee_ledger.dart';
import '../../../models/game_session.dart';
import '../../../models/member.dart';

/// 회비 미납 안내 메시지 미리보기 및 편집 다이얼로그
///
/// 미납자 명단 및 안내 문구를 사전에 확인/수정하고,
/// [문구 복사]로 카카오톡 등에 전달하거나 [문자 앱 열기]로 일괄 SMS를 발송할 수 있습니다.
class UnpaidFeeGuideDialog extends StatefulWidget {
  final GameSession session;
  final Club currentClub;
  final List<Member> unpaidMembers;
  final ClubFeePolicy feePolicy;

  const UnpaidFeeGuideDialog({
    super.key,
    required this.session,
    required this.currentClub,
    required this.unpaidMembers,
    required this.feePolicy,
  });

  @override
  State<UnpaidFeeGuideDialog> createState() => _UnpaidFeeGuideDialogState();
}

class _UnpaidFeeGuideDialogState extends State<UnpaidFeeGuideDialog> {
  late final TextEditingController _messageCtrl;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _messageCtrl = TextEditingController(text: _generateDefaultMessage());
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 기본 안내 템플릿 생성
  String _generateDefaultMessage() {
    final clubName = widget.currentClub.clubName;
    final dateStr = widget.session.sessionDate.replaceAll('-', '.');
    final unpaidNames = widget.unpaidMembers.map((m) => m.name).join(', ');
    final accountInfo = widget.feePolicy.accountNumber.trim().isNotEmpty
        ? widget.feePolicy.formattedBankAccount
        : '클럽 계좌 또는 총무 문의';

    return '[$clubName] $dateStr 정기 모임 회비 안내\n\n'
        '미납 인원: $unpaidNames\n'
        '입금 계좌: $accountInfo\n\n'
        '확인 후 입금 부탁드립니다.';
  }

  /// 수신 대상 요약 문자열 (예: "박지성, 안세영 외 0명 (총 2명)")
  String _getRecipientsSummary() {
    final count = widget.unpaidMembers.length;
    if (count == 0) return '미납자 없음 (총 0명)';
    if (count == 1) return '${widget.unpaidMembers.first.name} (총 1명)';
    final firstTwo = widget.unpaidMembers.take(2).map((m) => m.name).join(', ');
    final remaining = count - 2;
    if (remaining > 0) {
      return '$firstTwo 외 $remaining명 (총 $count명)';
    }
    return '$firstTwo (총 $count명)';
  }

  /// [문구 복사] 버튼 핸들러
  Future<void> _handleCopy() async {
    final text = _messageCtrl.text;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('안내 문구가 복사되었습니다. 카카오톡 등에 붙여넣기 하세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// [문자 앱 열기] 버튼 핸들러
  Future<void> _handleOpenSms() async {
    final phones = widget.unpaidMembers
        .map((m) => (m.phoneNumber ?? '').replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty)
        .toList();
    final message = _messageCtrl.text;

    if (phones.isEmpty) {
      await Clipboard.setData(ClipboardData(text: message));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('미납자의 등록된 전화번호가 없습니다. [문구 복사] 후 카카오톡으로 전송해 주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final recipients = phones.join(',');
    final smsUri = Uri.parse('sms:$recipients?body=${Uri.encodeComponent(message)}');

    try {
      final launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await Clipboard.setData(ClipboardData(text: '$recipients\n$message'));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('미납자 ${phones.length}명 번호와 문구를 클립보드에 복사했습니다.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('미납자 ${phones.length}명에게 입금 안내 문자 앱을 열었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: '$recipients\n$message'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('미납자 ${phones.length}명 번호와 문구를 클립보드에 복사했습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phonesCount = widget.unpaidMembers
        .map((m) => (m.phoneNumber ?? '').replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty)
        .length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
              // 1. 헤더: 아이콘 + 제목 + 닫기(X) 아이콘
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelCoral.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_rounded,
                      color: AppTheme.pastelCoralDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '회비 미납 안내 메시지',
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
              const SizedBox(height: 14),

              // 2. 수신 대상 안내 박스
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceGrey,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          size: 16,
                          color: AppTheme.primaryDark,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '수신 대상: ${_getRecipientsSummary()}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '전화번호 등록: $phonesCount / ${widget.unpaidMembers.length}명 '
                      '${phonesCount < widget.unpaidMembers.length ? "(연락처 없는 회원은 카카오톡으로 공유)" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        color: phonesCount < widget.unpaidMembers.length
                            ? AppTheme.pastelCoralDark
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. 메시지 편집창 (TextFormField)
              const Text(
                '안내 메시지 내용 (편집 가능)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _messageCtrl,
                minLines: 5,
                maxLines: 8,
                enableInteractiveSelection: true,
                contextMenuBuilder: (context, editableTextState) =>
                    AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: editableTextState,
                ),
                style: const TextStyle(fontSize: 13, height: 1.45, color: AppTheme.textDark),
                decoration: InputDecoration(
                  hintText: '미납 안내 문구를 입력해 주세요.',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primaryDark, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 4. 하단 액션 버튼 (3종: 닫기, 문구 복사, 문자 앱 열기)
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _handleCopy,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text(
                      '문구 복사',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryDark,
                      side: const BorderSide(color: AppTheme.primaryDark),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _handleOpenSms,
                    icon: const Icon(Icons.sms_rounded, size: 16),
                    label: const Text(
                      '문자 앱 열기',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
