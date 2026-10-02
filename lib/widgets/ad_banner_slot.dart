import 'package:flutter/material.dart';

/// 비회원 웹 뷰어 및 화면용 스폰서 / 애드센스 광고 배너 슬롯 위젯
enum BannerPlacement {
  top('상단 스폰서/광고 배너'),
  bottom('하단 스폰서/광고 배너');

  final String label;
  const BannerPlacement(this.label);
}

/// 화면 최하단 고정 모바일 표준 띠배너 광고 컨테이너 (320x50 규격, 바닥 0px 밀착)
class BottomAdBannerArea extends StatelessWidget {
  final Key? bannerKey;
  final String? label;
  final VoidCallback? onTap;

  const BottomAdBannerArea({
    super.key,
    this.bannerKey,
    this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: bannerKey ?? const Key('bottom_sticky_ad_banner'),
      width: double.infinity,
      height: 50,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 0.8),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.ad_units_rounded,
                size: 15,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                label ?? '배너 광고 영역 (320x50)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    if (placement == BannerPlacement.bottom) {
      return BottomAdBannerArea(
        label: sponsorName != null
            ? '[스폰서] $sponsorName'
            : '하단 스폰서/광고 배너 (320x50)',
        onTap: onTap,
      );
    }

    return Container(
      width: double.infinity,
      height: 50,
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
