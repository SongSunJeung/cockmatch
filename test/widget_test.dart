import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cockmatch/main.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('CockMatchApp reordered navigation, phone UI, unpaid SMS, and session archive smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 앱 실행 시 초기(기본) 화면: 출석부 탭 (Index 1) & [진행 모임] / [지난 모임] 히스토리 표시 확인
    expect(find.text('출석부'), findsOneWidget);
    expect(find.text('오늘 모임 & 출석부'), findsOneWidget);
    expect(find.text('+ 새 모임 시작하기'), findsOneWidget);
    expect(find.text('[진행 모임]'), findsOneWidget);
    expect(find.text('[지난 모임]'), findsOneWidget);
    expect(find.text('2026.09.22 화요 정기 모임'), findsOneWidget);

    // [지난 모임] 카드를 탭하여 이전 모임의 출석부, 회비 정산 내역, 경기 전적 조회 확인
    final archivedCard = find.text('2026.09.22 화요 정기 모임');
    await tester.ensureVisible(archivedCard);
    await tester.pumpAndSettle();
    await tester.tap(archivedCard);
    await tester.pumpAndSettle();

    expect(find.text('회비 수납 현황'), findsOneWidget);
    expect(find.text('미납자 안내 문자 발송'), findsOneWidget);
    expect(find.textContaining('모임 경기 전적'), findsOneWidget);

    // 출석부 상단 필터 & 정렬(기본값: 급수순 A -> 초심) 확인
    expect(find.text('⇅ 급수순 (A -> 초심)'), findsOneWidget);
    expect(find.text('급수: 전체 ▾'), findsWidgets);
    expect(find.text('회원 구분: 전체 ▾'), findsWidgets);
    expect(find.text('성별: 전체 ▾'), findsWidgets);
    expect(find.text('출전'), findsWidgets);
    expect(find.text('휴식'), findsWidgets);
    expect(find.text('조퇴'), findsWidgets);
    expect(find.text('미납자만'), findsOneWidget);
    expect(find.text('완납'), findsWidgets);
    expect(find.text('면제'), findsWidgets);

    // 아래로 스크롤하여 출석부 참석자 리스트 렌더링 후 별도 전화기 아이콘 없이 전화번호 텍스트가 표시되는지 확인
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.phone_in_talk_rounded), findsNothing);
    expect(find.text('010-1111-2222'), findsWidgets);

    // 출석부 정렬 옵션 변경: [급수순 (A -> 초심)] -> [회비 상태순 (미납자 최우선 정렬)] -> [급수순 (A -> 초심)]
    await tester.tap(find.text('⇅ 급수순 (A -> 초심)'));
    await tester.pumpAndSettle();
    expect(find.text('급수순 (A -> 초심) [기본]'), findsOneWidget);
    expect(find.text('이름순 (가나다)'), findsOneWidget);
    expect(find.text('출전 상태순 (출전 -> 휴식 -> 조퇴)'), findsOneWidget);
    expect(find.text('회비 상태순 (미납자 최우선 정렬)'), findsOneWidget);
    await tester.tap(find.text('회비 상태순 (미납자 최우선 정렬)'));
    await tester.pumpAndSettle();
    expect(find.text('⇅ 회비 상태순'), findsOneWidget);

    await tester.tap(find.text('⇅ 회비 상태순'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('급수순 (A -> 초심) [기본]'));
    await tester.pumpAndSettle();
    expect(find.text('⇅ 급수순 (A -> 초심)'), findsOneWidget);

    // 복합 필터링(AND) 테스트: [급수: A조] + [출전] + [완납] 동시 선택
    await tester.tap(find.text('급수: 전체 ▾').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A조').last);
    await tester.pumpAndSettle();
    expect(find.text('급수: A조 ▾'), findsOneWidget);

    await tester.tap(find.text('출전').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완납').first);
    await tester.pumpAndSettle();

    // [필터 초기화] 클릭 시 출석부 필터 전체 초기화 확인
    await tester.tap(find.text('필터 초기화').last);
    await tester.pumpAndSettle();
    expect(find.text('급수: A조 ▾'), findsNothing);

    // 다시 위로 스크롤하여 모임 목록으로 복귀 후 데이터 보존 및 지난 모임 카드 삭제 다이얼로그 확인
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모임 목록'));
    await tester.pumpAndSettle();
    expect(find.text('2026.09.22 화요 정기 모임'), findsOneWidget);

    // '지난 모임' 카드 우측 삭제 아이콘 클릭 시 확인 다이얼로그 노출 검증
    final deleteArchiveBtn = find.byTooltip('지난 모임 기록 삭제');
    expect(deleteArchiveBtn, findsWidgets);
    await tester.tap(deleteArchiveBtn.first);
    await tester.pumpAndSettle();
    expect(
      find.text('모임 기록을 완전히 삭제하시겠습니까? (출석 및 경기 전적이 영구 삭제됩니다)'),
      findsOneWidget,
    );
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('2026.09.22 화요 정기 모임'), findsOneWidget);

    // 2. 0번 탭: 회원명부 (기본 회원 DB 관리 & 전화번호 텍스트 탭/단체문자 기능 & 정렬 기본값 이름 가나다순)
    final memberTabIcon = find.byIcon(Icons.people_alt_rounded);
    expect(memberTabIcon, findsOneWidget);
    await tester.tap(memberTabIcon);
    await tester.pumpAndSettle();

    // 회원명부 화면: 기본 정렬 '⇅ 이름순 (가나다)' 및 가나다순 최상단 회원(강호동: 010-6666-7777, 가족할인 20,000원 뱃지) 노출 확인
    expect(find.text('메가 배드민턴 클럽'), findsOneWidget);
    expect(find.byTooltip('신규 회원 직접 등록'), findsOneWidget);
    expect(find.byTooltip('단체 문자 발송'), findsOneWidget);
    expect(find.text('단체 문자 발송'), findsOneWidget);
    expect(find.byIcon(Icons.phone_in_talk_rounded), findsNothing);
    expect(find.text('⇅ 이름순 (가나다)'), findsOneWidget);
    expect(find.text('010-6666-7777'), findsOneWidget);
    expect(find.text('가족할인 20,000원'), findsOneWidget);

    // 신규 회원 등록 모달 오픈 -> [회원 활동 상태], [회원 등급 / 직책] 커스텀 직접 추가, [회비 부과 기준] UI 검증
    await tester.tap(find.byTooltip('신규 회원 직접 등록'));
    await tester.pumpAndSettle();
    expect(find.text('활동 회원 (기본값)'), findsOneWidget);
    expect(find.text('휴면(휴회) 회원'), findsOneWidget);
    expect(find.text('기본 회비 부과'), findsOneWidget);
    expect(find.text('차등/할인 금액 지정'), findsOneWidget);
    expect(find.text('회비 면제'), findsOneWidget);

    // [휴면(휴회) 회원] 선택 시 휴면 시작일, 복귀 예정일, 휴면 사유 입력란 및 휴회 면제 안내 노출 확인
    await tester.tap(find.text('휴면(휴회) 회원'));
    await tester.pumpAndSettle();
    expect(find.text('휴면 시작일'), findsOneWidget);
    expect(find.text('복귀 예정일 (선택)'), findsOneWidget);
    expect(find.text('휴면 사유'), findsOneWidget);
    expect(find.textContaining('휴회 면제'), findsWidgets);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 회원명부 정렬 변경: [급수순 (상위 급수 우선: A -> 초심)] 선택 시 A조 회원(안세영: 010-1111-2222) 최상단 정렬 확인
    await tester.tap(find.text('⇅ 이름순 (가나다)'));
    await tester.pumpAndSettle();
    expect(find.text('이름순 (가나다) [기본]'), findsOneWidget);
    expect(find.text('급수순 (상위 급수 우선: A -> 초심)'), findsOneWidget);
    expect(find.text('회원 구분순 (운영진 -> 정회원 -> 준회원)'), findsOneWidget);
    expect(find.text('최근 등록순'), findsOneWidget);
    await tester.tap(find.text('급수순 (상위 급수 우선: A -> 초심)'));
    await tester.pumpAndSettle();
    expect(find.text('⇅ 급수순 (A -> 초심)'), findsOneWidget);
    expect(find.text('010-1111-2222'), findsOneWidget);

    // 다시 [최근 등록순]으로 정렬하여 이후 CSV 신규 등록 회원이 최상단에 표시되도록 전환
    await tester.tap(find.text('⇅ 급수순 (A -> 초심)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 등록순'));
    await tester.pumpAndSettle();
    expect(find.text('⇅ 최근 등록순'), findsOneWidget);

    expect(find.text('급수: 전체 ▾'), findsOneWidget);
    expect(find.text('회원 구분: 전체 ▾'), findsOneWidget);
    expect(find.text('성별: 전체 ▾'), findsOneWidget);

    // 드롭다운 1) [급수] 선택 -> '급수: B조 ▾'로 변경 확인
    await tester.tap(find.text('급수: 전체 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B조').last);
    await tester.pumpAndSettle();
    expect(find.text('급수: B조 ▾'), findsOneWidget);

    // 드롭다운 2) [회원 구분] 선택 -> '회원 구분: 운영진 ▾'로 변경 확인
    await tester.tap(find.text('회원 구분: 전체 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('운영진').last);
    await tester.pumpAndSettle();
    expect(find.text('회원 구분: 운영진 ▾'), findsOneWidget);

    // 드롭다운 3) [성별] 선택 -> '성별: 여성 ▾'로 변경 및 AND 결합 필터링 확인
    await tester.tap(find.text('성별: 전체 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여성').last);
    await tester.pumpAndSettle();
    expect(find.text('성별: 여성 ▾'), findsOneWidget);

    // 필터 초기화 버튼 클릭 시 3종 드롭다운 모두 기본값('전체 ▾')으로 복원되고 정렬 상태는 유지됨 확인
    await tester.tap(find.text('필터 초기화'));
    await tester.pumpAndSettle();
    expect(find.text('급수: 전체 ▾'), findsOneWidget);
    expect(find.text('회원 구분: 전체 ▾'), findsOneWidget);
    expect(find.text('성별: 전체 ▾'), findsOneWidget);
    expect(find.text('⇅ 최근 등록순'), findsOneWidget);

    // 2-2. 회원명부 우측 상단 '더보기 메뉴' -> [CSV로 회원 대량 등록] 및 [회원명부 CSV 다운로드] 검증
    final moreMenuBtn = find.byTooltip('더보기 메뉴');
    expect(moreMenuBtn, findsOneWidget);
    await tester.tap(moreMenuBtn);
    await tester.pumpAndSettle();

    expect(find.text('CSV로 회원 대량 등록'), findsOneWidget);
    expect(find.text('회원명부 CSV 다운로드'), findsOneWidget);

    // [CSV로 회원 대량 등록] 클릭 -> 표준 템플릿 링크 및 미리보기 팝업(총 N명 검출) 흐름 확인
    await tester.tap(find.text('CSV로 회원 대량 등록'));
    await tester.pumpAndSettle();

    expect(find.text('표준 템플릿 CSV 다운로드'), findsOneWidget);
    expect(find.text('헤더 컬럼: 이름, 전화번호, 성별, 급수, 회원구분, 메모'), findsOneWidget);

    // 직접 입력 토글을 열어 유효 행 + 중복 전화번호 + 오류 행이 포함된 CSV로 미리보기 팝업 검증
    await tester.tap(find.text('또는 CSV 텍스트 직접 붙여넣기 / 미리보기 검증'));
    await tester.pumpAndSettle();

    final csvInputField = find.byType(TextField).last;
    await tester.enterText(
      csvInputField,
      '이름,전화번호,성별,급수,회원구분,메모\n'
      '안세영,01011112222,여,A,운영진(회장),전화번호중복갱신\n'
      '최신규,01099998888,남,B조,정회원,신규등록테스트\n'
      ',01077776666,남,C,정회원,이름누락오류\n'
      '김오류,01055554444,여,Z급,준회원,급수오류',
    );
    await tester.pumpAndSettle();

    final openPreviewBtn = find.text('CSV 파싱 및 미리보기 팝업 열기');
    await tester.ensureVisible(openPreviewBtn);
    await tester.pumpAndSettle();
    await tester.tap(openPreviewBtn);
    await tester.pumpAndSettle();

    // 미리보기 팝업 (총 4명 검출): 유효 2명 / 오류 2건 / 중복 1명 검출 확인
    expect(find.text('미리보기 팝업 (총 4명 검출)'), findsOneWidget);
    expect(find.text('유효한 행 (2)'), findsOneWidget);
    expect(find.text('오류 행 (2)'), findsOneWidget);
    expect(find.textContaining('기존에 동일한 전화번호가 있을 경우 (1명 검출):'), findsOneWidget);
    expect(find.text('기존 정보 덮어쓰기'), findsOneWidget);
    expect(find.text('건너뛰기'), findsOneWidget);

    // [등록 완료] 클릭 시 유효 행 반영 확인
    await tester.tap(find.text('등록 완료'));
    await tester.pumpAndSettle();
    expect(find.text('최신규'), findsOneWidget);

    // [회원명부 CSV 다운로드] 팝업 열기 및 파일명 형식("메가배드민턴_회원명부_YYYYMMDD.csv") 확인
    await tester.tap(find.byTooltip('더보기 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('회원명부 CSV 다운로드'));
    await tester.pumpAndSettle();

    expect(find.textContaining('메가배드민턴_회원명부_'), findsOneWidget);
    expect(find.textContaining('UTF-8 BOM 적용'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 3. 2번 탭: 대진표 (코트 배정 및 실시간 점수 기록)
    final bracketTabIcon = find.byIcon(Icons.sports_tennis_rounded);
    expect(bracketTabIcon, findsOneWidget);
    await tester.tap(bracketTabIcon);
    await tester.pumpAndSettle();

    // 대진표 화면 (세션 미시작 상태)
    expect(find.text('대진표'), findsOneWidget);
    expect(find.text('진행 중인 모임 세션이 없습니다'), findsWidgets);
    final startFromAttendanceBtn = find.text('출석부에서 새 모임 시작하기');
    expect(startFromAttendanceBtn, findsOneWidget);

    // 대진표 화면에서 출석부 바로가기 터치 시 출석부 탭(Index 1)으로 복귀 검증
    await tester.tap(startFromAttendanceBtn);
    await tester.pumpAndSettle();
    expect(find.text('오늘 모임 & 출석부'), findsOneWidget);

    // 4. 3번 탭(4번째 탭): 웹뷰어 (라이브 전광판 & 완료 리포트)
    final viewerTabIcon = find.byIcon(Icons.visibility_rounded);
    expect(viewerTabIcon, findsOneWidget);
    await tester.tap(viewerTabIcon);
    await tester.pumpAndSettle();

    // 상단 공유 버튼 확인: [웹 링크 복사] & [결과 요약 텍스트 복사]
    expect(find.text('웹 링크 복사'), findsOneWidget);
    expect(find.text('결과 요약 텍스트 복사'), findsOneWidget);

    // 진행 중 [실시간 코트 전광판] & 하단 대기자/휴식자 명단 확인
    expect(find.text('실시간 코트 전광판'), findsWidgets);
    expect(find.text('다음 라운드 대기자 / 휴식자 명단'), findsOneWidget);

    // [모임 완료 결과 리포트] 전환 시 2개 서브 탭([종합 순위 & 리포트] / [라운드별 스코어]) 및 [순위 결정 기준 안내] 확인
    await tester.tap(find.text('모임 완료 결과 리포트'));
    await tester.pumpAndSettle();

    expect(find.text('종합 순위 & 리포트'), findsOneWidget);
    expect(find.text('라운드별 스코어'), findsOneWidget);
    expect(find.textContaining('순위 결정 기준 안내'), findsOneWidget);

    // 경기 방식 전환: 풀리그전 (팀 기준) -> 토너먼트 (최종 트리) 확인
    await tester.tap(find.text('풀리그전 (팀 기준)'));
    await tester.pumpAndSettle();
    expect(find.text('풀리그전 팀별 순위표 (팀 기준)'), findsOneWidget);

    await tester.tap(find.text('토너먼트'));
    await tester.pumpAndSettle();
    expect(find.text('토너먼트 최종 트리 (진출 단계 기준)'), findsOneWidget);

    // [라운드별 스코어] 서브 탭 전환 -> 라운드 필터 칩(전체, 1R, 2R) 및 WIN 뱃지 확인
    await tester.tap(find.text('라운드별 스코어'));
    await tester.pumpAndSettle();
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('1R'), findsWidgets);
    expect(find.text('WIN'), findsWidgets);
  });

  testWidgets('오늘 모임 세션 & 대진 설정 바텀시트: 직전 설정값 자동 기억(Persistence) 및 [설정 초기화] 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 0. [+ 새 모임 시작하기]를 통해 모임 생성 후 출석부 진입
    await tester.tap(find.text('+ 새 모임 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('새 모임 시작하기'), findsOneWidget);
    expect(find.text('설정 초기화'), findsOneWidget);

    await tester.tap(find.textContaining('다음: 모임 정보 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('다음: 참석자 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('모임 시작 & 출석부 열기'));
    await tester.pumpAndSettle();

    // 출석부 하단 [대진 설정 & 이동] 버튼 클릭 -> '오늘 모임 세션 & 대진 설정' 바텀시트 오픈
    final startSessionBtn = find.text('대진 설정 & 이동');
    expect(startSessionBtn, findsOneWidget);
    await tester.tap(startSessionBtn);
    await tester.pumpAndSettle();

    expect(find.text('오늘 모임 세션 & 대진 설정'), findsOneWidget);
    expect(find.byKey(const Key('reset_session_settings_button')), findsOneWidget);
    expect(find.text('설정 초기화'), findsOneWidget);

    // 1. 설정값 변경: [풀리그전], [5번 코트 시작], [통합 밸런스 매칭], [전원 고정 페어 (복식팀 대전)]
    await tester.tap(find.text('풀리그전'));
    await tester.pumpAndSettle();

    final startCourt5Chip = find.text('5번 코트 시작');
    await tester.ensureVisible(startCourt5Chip);
    await tester.pumpAndSettle();
    await tester.tap(startCourt5Chip);
    await tester.pumpAndSettle();

    expect(find.text('5번부터'), findsOneWidget);

    final balanceModeCard = find.text('통합 밸런스 매칭');
    await tester.ensureVisible(balanceModeCard);
    await tester.pumpAndSettle();
    await tester.tap(balanceModeCard);
    await tester.pumpAndSettle();

    final fixedPartnerBtn = find.text('전원 고정 페어 (복식팀 대전)');
    await tester.ensureVisible(fixedPartnerBtn);
    await tester.pumpAndSettle();
    await tester.tap(fixedPartnerBtn);
    await tester.pumpAndSettle();

    expect(find.text('복식 페어 편성 목록'), findsOneWidget);

    // 2. 바텀시트를 닫았다가 다시 열어도 직전 설정값이 그대로 유지되는지 검증
    Navigator.of(tester.element(find.text('오늘 모임 세션 & 대진 설정'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(startSessionBtn);
    await tester.pumpAndSettle();

    expect(find.text('직전 설정 기억됨'), findsOneWidget);
    expect(find.text('5번부터'), findsOneWidget);
    expect(find.text('복식 페어 편성 목록'), findsOneWidget);

    // 3. 상단 우측 [설정 초기화] 버튼 클릭 시 기본 권장 설정으로 즉시 리셋되는지 검증
    final resetBtn = find.byKey(const Key('reset_session_settings_button'));
    await tester.ensureVisible(resetBtn);
    await tester.pumpAndSettle();
    await tester.tap(resetBtn);
    await tester.pumpAndSettle();

    expect(find.text('기본 권장 설정'), findsOneWidget);
    expect(find.text('1번부터'), findsOneWidget);
    expect(find.text('복식 페어 편성 목록'), findsNothing);
    expect(find.text('+ 특정 고정 페어 추가'), findsOneWidget);
  });
}
