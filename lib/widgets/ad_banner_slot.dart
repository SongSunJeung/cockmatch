import 'package:flutter/material.dart';

/// 비회원 웹 뷰어 및 화면용 스폰서 / 애드센스 광고 배너 슬롯 위젯
enum BannerPlacement {
  top('상단 스폰서/광고 배너'),
  bottom('하단 스폰서/광고 배너');

  final String label;
  const BannerPlacement(this.label);
}

class AdBannerSlot extends StatelessWidget {
  final BannerPlacement placement;
  final String? sponsorName;
  final String? sponsorImageUrl;
  final VoidCallback? onTap;

  const AdBannerSlot({
    super.key,
    required this.placement,
    this.sponsorName,
    this.sponsorImageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate 100
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFCBD5E1),
          style: BorderStyle.solid,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.campaign_outlined,
              size: 20,
              color: Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              sponsorName != null
                  ? '[스폰서] $sponsorName'
                  : '${placement.label} (Google AdSense / 지역 클럽 협찬 슬롯)',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
