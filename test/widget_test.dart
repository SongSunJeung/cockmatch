import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cockmatch/main.dart';
import 'package:cockmatch/core/theme/app_theme.dart';
import 'package:cockmatch/views/widgets/tournament_bracket_tree_widget.dart';
import 'package:cockmatch/views/club/club_member_pool_screen.dart';
import 'package:cockmatch/providers/providers.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('CockMatchApp reordered navigation, phone UI, unpaid SMS, and session archive smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 앱 실행 시 초기(기본) 화면: 모임/행사 탭 (Index 1) & 좌측 햄버거 메뉴 아이콘 노출 확인
    expect(find.byIcon(Icons.menu_rounded), findsWidgets);
    expect(find.text('오늘 모임 & 모임/행사'), findsOneWidget);
    expect(find.text('+ 새 모임 시작하기'), findsOneWidget);
    expect(find.text('[진행 모임]'), findsOneWidget);
    expect(find.text('[지난 모임]'), findsOneWidget);
    expect(find.text('2026.09.22 화요 정기 모임'), findsOneWidget);

    // [지난 모임] 카드를 탭하여 이전 모임의 출석부, 슬림 요약 바, 경기 전적 조회 확인
    final archivedCard = find.text('2026.09.22 화요 정기 모임');
    await tester.ensureVisible(archivedCard);
    await tester.pumpAndSettle();
    await tester.tap(archivedCard);
    await tester.pumpAndSettle();

    // 슬림 요약 대시보드(출석/수납 텍스트 및 미납자 안내 문자 IconButton) 확인
    expect(find.textContaining('출석'), findsWidgets);
    expect(find.textContaining('수납'), findsWidgets);
    expect(find.byKey(const Key('unpaid_guide_sms_button')), findsOneWidget);
    // 출석부 화면에서 '모임 경기 전적' 카드 및 상단 '모임 목록' 중복 버튼 제거 확인
    expect(find.textContaining('모임 경기 전적'), findsNothing);
    expect(find.text('모임 목록'), findsNothing);
    // '게스트 즉시 추가' 옆 개별 '문자 발송' 버튼이 제거되었는지 확인
    expect(find.text('게스트 즉시 추가'), findsOneWidget);
    expect(find.text('문자 발송'), findsNothing);

    // 출석부 상단 필터 버튼 및 상태 필터 칩 확인
    expect(find.byKey(const Key('attendance_filter_button')), findsOneWidget);
    expect(find.text('출전'), findsWidgets);
    expect(find.text('휴식'), findsWidgets);
    expect(find.text('조퇴'), findsWidgets);
    expect(find.text('미납'), findsWidgets);
    expect(find.text('완납'), findsWidgets);
    expect(find.text('면제'), findsWidgets);

    // 아래로 스크롤하여 출석부 참석자 리스트 렌더링 후 확인:
    // - 동그란 '남'/'여' 뱃지 아이콘 제거 확인
    // - 회비 수납 단일 순환 뱃지(완납 -> 미납 -> 면제 -> 완납) 동작 확인
    // - 회원 카드 탭(상세 정보 팝업: 전화 걸기 / 문자 보내기) & 롱프레스(다중 선택 문자 발송 바) 확인
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.phone_in_talk_rounded), findsNothing);
    expect(find.text('남'), findsNothing);
    expect(find.text('여'), findsNothing);
    expect(find.text('010-1111-2222'), findsWidgets);

    // 회원 카드 짧게 탭(Tap) -> 상세 정보 팝업(전화 걸기, 문자 보내기) 확인
    await tester.tap(find.text('안세영').first);
    await tester.pumpAndSettle();
    expect(find.text('전화 걸기'), findsOneWidget);
    expect(find.text('문자 보내기'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    // 회원 카드 길게 누르기(Long Press) -> 다중 선택 체크 모드 & "선택한 회원(1명) 문자 발송" 액션 바 확인
    await tester.longPress(find.text('안세영').first);
    await tester.pumpAndSettle();
    expect(find.text('선택한 회원(1명) 문자 발송'), findsOneWidget);
    await tester.tap(find.byTooltip('선택 모드 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 회원(1명) 문자 발송'), findsNothing);

    // 출석부 세부 필터 & 정렬 모달 바텀시트 열기
    await tester.tap(find.byKey(const Key('attendance_filter_button')));
    await tester.pumpAndSettle();
    expect(find.text('필터 및 정렬'), findsOneWidget);
    expect(find.text('급수순 (A -> 초심) [기본]'), findsOneWidget);
    expect(find.text('이름순 (가나다)'), findsOneWidget);
    expect(find.text('출전 상태순 (출전 -> 휴식 -> 조퇴)'), findsOneWidget);
    expect(find.text('회비 상태순 (미납자 최우선 정렬)'), findsOneWidget);

    // [회비 상태순 (미납자 최우선 정렬)] 선택 후 적용하기
    await tester.tap(find.text('회비 상태순 (미납자 최우선 정렬)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attendance_filter_apply_btn')));
    await tester.pumpAndSettle();
    expect(find.text('회비 상태순'), findsOneWidget);

    // 다시 필터 모달 열기 -> [급수순 (A -> 초심) [기본]] 복원 및 [급수: A조] 선택 후 적용하기
    await tester.tap(find.byKey(const Key('attendance_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('급수순 (A -> 초심) [기본]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A조').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attendance_filter_apply_btn')));
    await tester.pumpAndSettle();

    // 복합 필터링(AND) 테스트: [출전] + [완납] 동시 선택
    await tester.tap(find.text('출전').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완납').first);
    await tester.pumpAndSettle();

    // [필터 초기화] 클릭 시 출석부 필터 전체 초기화 확인
    await tester.tap(find.text('필터 초기화').last);
    await tester.pumpAndSettle();

    // 다시 위로 스크롤하여 우측 상단 팝업 메뉴로 모임 목록 복귀 후 데이터 보존 및 지난 모임 카드 삭제 다이얼로그 확인
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session_header_more_menu')));
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

    // 2. 좌측 햄버거 메뉴(Drawer)를 열어 0번 메뉴: [회원명부]로 이동
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    expect(find.text('회원명부'), findsOneWidget);
    await tester.tap(find.text('회원명부'));
    await tester.pumpAndSettle();

    // 회원명부 화면: 기본 정렬 '⇅ 이름순 (가나다)' 및 가나다순 최상단 회원(강호동: 010-6666-7777, 가족회원 뱃지) 노출 확인
    expect(find.text('메가 배드민턴 클럽'), findsOneWidget);
    expect(find.byTooltip('신규 회원 등록'), findsOneWidget);
    // 최상단 AppBar 우측 말풍선(문자) 아이콘 중복 제거 및 본문 리스트 상단 [단체 문자 발송] 단일 유지 확인
    expect(find.byTooltip('단체 문자 발송'), findsNothing);
    expect(find.text('단체 문자 발송'), findsOneWidget);
    expect(find.byIcon(Icons.phone_in_talk_rounded), findsNothing);
    expect(find.byKey(const Key('member_filter_button')), findsOneWidget);
    expect(find.text('010-6666-7777'), findsOneWidget);
    expect(find.text('가족회원'), findsOneWidget);
    // 회원 명부 카드 우측 급수 뱃지: 내부 점수 표기 없이 급수 명칭만 깔끔하게 노출되는지 확인
    expect(find.text('A조 (5점)'), findsNothing);
    expect(find.text('B조 (4점)'), findsNothing);
    expect(find.text('C조 (3점)'), findsNothing);
    expect(find.text('D조 (2점)'), findsNothing);
    expect(find.text('초심 (1점)'), findsNothing);
    expect(find.text('A조'), findsWidgets);

    // 신규 회원 등록 바텀시트 오픈 -> [1명씩 직접 등록] 선택 -> [회원 활동 상태]('활동 회원' 간소화), [회원 등급 / 직책] 커스텀 직접 추가, [회비 부과 기준] UI 검증
    await tester.tap(find.byTooltip('신규 회원 등록'));
    await tester.pumpAndSettle();
    expect(find.text('신규 회원 등록 방식 선택'), findsOneWidget);
    expect(find.text('텍스트 대량 등록'), findsOneWidget);
    expect(find.text('CSV 파일 업로드'), findsOneWidget);
    await tester.tap(find.text('1명씩 직접 등록'));
    await tester.pumpAndSettle();
    expect(find.text('활동 회원 (기본값)'), findsNothing);
    expect(find.text('활동 회원'), findsOneWidget);
    expect(find.text('휴면(휴회) 회원'), findsOneWidget);
    expect(find.text('기본 회비 부과'), findsOneWidget);
    expect(find.text('차등/할인 금액 지정'), findsOneWidget);
    expect(find.text('회비 면제'), findsOneWidget);

    // [회비 면제 -> 기간 지정 면제] 선택 시 [면제 시작일] ~ [면제 종료일] 입력 필드 노출 확인
    final exemptPolicyBtn = find.text('회비 면제');
    await tester.ensureVisible(exemptPolicyBtn);
    await tester.pumpAndSettle();
    await tester.tap(exemptPolicyBtn);
    await tester.pumpAndSettle();
    final periodExemptChip = find.text('기간 지정 면제');
    await tester.ensureVisible(periodExemptChip);
    await tester.pumpAndSettle();
    await tester.tap(periodExemptChip);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member_exempt_start_date_field')), findsOneWidget);
    expect(find.byKey(const Key('member_exempt_until_date_field')), findsOneWidget);
    expect(find.text('면제 시작일'), findsOneWidget);
    expect(find.text('면제 종료일'), findsOneWidget);

    // [휴면(휴회) 회원] 선택 시 휴면 시작일, 복귀 예정일, 휴면 사유 입력란 및 휴회 면제 안내 노출 확인
    final restingMemberBtn = find.text('휴면(휴회) 회원');
    await tester.ensureVisible(restingMemberBtn);
    await tester.pumpAndSettle();
    await tester.tap(restingMemberBtn);
    await tester.pumpAndSettle();
    expect(find.text('휴면 시작일'), findsOneWidget);
    expect(find.text('복귀 예정일 (선택)'), findsOneWidget);
    expect(find.text('휴면 사유'), findsOneWidget);
    expect(find.textContaining('휴회 면제'), findsWidgets);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 회원명부 세부 필터 & 정렬 모달 바텀시트 열기
    await tester.tap(find.byKey(const Key('member_filter_button')));
    await tester.pumpAndSettle();
    expect(find.text('필터 및 정렬'), findsOneWidget);
    expect(find.text('이름순 (가나다) [기본]'), findsOneWidget);
    expect(find.text('급수순 (상위 급수 우선: A -> 초심)'), findsOneWidget);
    expect(find.text('회원 구분순 (운영진 -> 정회원 -> 준회원)'), findsOneWidget);
    expect(find.text('최근 등록순'), findsOneWidget);

    // [급수순] 선택 후 적용하기 -> A조 회원(안세영: 010-1111-2222) 최상단 정렬 확인
    await tester.tap(find.text('급수순 (상위 급수 우선: A -> 초심)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member_filter_apply_btn')));
    await tester.pumpAndSettle();
    expect(find.text('급수순 (A -> 초심)'), findsOneWidget);
    expect(find.text('010-1111-2222'), findsOneWidget);

    // 다시 필터 모달 열기 -> [최근 등록순] + [급수: B조] + [회원 구분: 운영진] + [성별: 여성] 선택 후 적용
    await tester.tap(find.byKey(const Key('member_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 등록순'));
    await tester.pumpAndSettle();
    expect(find.text('S조'), findsWidgets);
    await tester.tap(find.text('B조').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('운영진').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('여성').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member_filter_apply_btn')));
    await tester.pumpAndSettle();

    // 상단 요약 바의 [필터 초기화] 클릭 시 세부 필터 초기화 확인
    await tester.tap(find.text('필터 초기화'));
    await tester.pumpAndSettle();

    // 다시 필터 모달을 열어 정렬을 [최근 등록순]으로 설정하여 이후 CSV 신규 등록 회원이 최상단에 표시되도록 설정
    await tester.tap(find.byKey(const Key('member_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 등록순').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member_filter_apply_btn')));
    await tester.pumpAndSettle();
    expect(find.text('최근 등록순'), findsWidgets);

    // 2-2. 회원명부 우측 상단 '더보기 메뉴' -> [회원명부 CSV 다운로드] 데이터 관리 메뉴 유지 확인
    final moreMenuBtn = find.byTooltip('더보기 메뉴');
    expect(moreMenuBtn, findsOneWidget);
    await tester.tap(moreMenuBtn);
    await tester.pumpAndSettle();

    expect(find.text('회원명부 CSV 다운로드'), findsOneWidget);
    // 메뉴 바깥 탭하여 닫기
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 신규 등록 바텀시트에서 [CSV 파일 업로드] 클릭 -> 표준 템플릿 링크 및 미리보기 팝업(총 N명 검출) 흐름 확인
    await tester.tap(find.byTooltip('신규 회원 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV 파일 업로드'));
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

    // 3. 좌측 햄버거 메뉴(Drawer)를 열어 2번 메뉴: [대진표]로 이동
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    expect(find.text('대진표'), findsOneWidget);
    await tester.tap(find.text('대진표'));
    await tester.pumpAndSettle();

    // 대진표 화면 (세션 미시작 상태)
    expect(find.text('진행 중인 모임 세션이 없습니다'), findsWidgets);
    final startFromAttendanceBtn = find.text('일정/모임에서 새 모임 시작하기');
    expect(startFromAttendanceBtn, findsOneWidget);

    // 대진표 화면에서 일정/모임 바로가기 터치 시 모임/행사 탭(Index 1)으로 복귀 검증
    await tester.tap(startFromAttendanceBtn);
    await tester.pumpAndSettle();
    expect(find.text('오늘 모임 & 모임/행사'), findsOneWidget);

    // 4. 좌측 햄버거 메뉴(Drawer)를 열어 3번 메뉴: [웹뷰어]로 이동
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    expect(find.text('웹뷰어'), findsOneWidget);
    await tester.tap(find.text('웹뷰어'));
    await tester.pumpAndSettle();

    // 상단 공유 버튼 및 모임 선택 드롭다운 확인: 대형 버튼 제거 및 상단바 공유 팝업 버튼 통합
    expect(find.byKey(const Key('web_viewer_share_popup_button')), findsOneWidget);
    expect(find.text('웹 링크 복사'), findsNothing);
    expect(find.text('결과 요약 텍스트 복사'), findsNothing);
    expect(find.byKey(const Key('viewer_session_selector_dropdown')), findsOneWidget);

    // 공유 아이콘 터치 시 팝업 메뉴([웹 링크 복사] & [결과 요약 텍스트 복사]) 노출 확인
    await tester.tap(find.byKey(const Key('web_viewer_share_popup_button')));
    await tester.pumpAndSettle();
    expect(find.text('웹 링크 복사'), findsOneWidget);
    expect(find.text('결과 요약 텍스트 복사'), findsOneWidget);
    await tester.tap(find.text('웹 링크 복사'));
    await tester.pumpAndSettle();


    // 진행 중 [실시간 코트 전광판] & 하단 대기자/휴식자 명단 확인
    expect(find.text('실시간 코트 전광판'), findsWidgets);
    expect(find.byKey(const Key('live_scoreboard_round_chips_scroll')), findsOneWidget);
    expect(find.text('대기'), findsNothing);
    expect(find.text('대기자 / 휴식자 명단'), findsOneWidget);

    // [경기 결과] 전환 시 진행 중 모임에서는 과거 모임 강제 전환 없이 '현재 경기가 진행 중입니다' Empty State 노출
    await tester.tap(find.text('경기 결과').first);
    await tester.pumpAndSettle();

    expect(find.text('현재 경기가 진행 중입니다'), findsOneWidget);
    expect(find.textContaining('운영진이 \'오늘 경기 종료\'를 확정하면'), findsOneWidget);
    expect(find.byKey(const Key('ongoing_session_goto_live_button')), findsOneWidget);

    // [실시간 코트 전광판 확인하기] 버튼 탭 시 실시간 코트 전광판으로 복귀
    await tester.tap(find.byKey(const Key('ongoing_session_goto_live_button')));
    await tester.pumpAndSettle();
    expect(find.text('대기자 / 휴식자 명단'), findsOneWidget);

    // 드롭다운에서 완료된 모임(2026.09.22 화요 정기 모임) 선택 시 [종합 순위] / [라운드별 스코어] 리포트 확인
    await tester.tap(find.byKey(const Key('viewer_session_selector_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2026.09.22').last);
    await tester.pumpAndSettle();

    expect(find.text('종합 순위'), findsOneWidget);
    expect(find.text('라운드별 스코어'), findsOneWidget);
    expect(find.textContaining('순위 결정 기준 안내'), findsOneWidget);

    // 로테이션 모임(MatchFormat.regular) 선택 시 [개인 순위] 테이블 자동 노출 및 토너먼트 미노출 검증
    expect(find.text('개인 순위'), findsOneWidget);
    expect(find.text('토너먼트'), findsNothing);

    // 드롭다운에서 토너먼트 모임(2026.09.15) 선택 시 토너먼트 최종 트리 확인
    await tester.tap(find.byKey(const Key('viewer_session_selector_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2026.09.15').last);
    await tester.pumpAndSettle();
    expect(find.text('토너먼트 최종 트리 (진출 단계 기준)'), findsOneWidget);

    // [라운드별 스코어] 서브 탭 전환 -> 라운드 필터 칩(전체, 1R, 2R), 완료된 경기 '완료' 뱃지 및 WIN 뱃지 확인
    await tester.tap(find.text('라운드별 스코어'));
    await tester.pumpAndSettle();
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('완료'), findsWidgets);
    expect(find.text('WIN'), findsWidgets);

    // 최하단으로 스크롤하여 [앱 다운로드 유도 배너] 플레이스홀더 노출 확인
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('web_viewer_app_download_banner')), findsOneWidget);
    expect(find.textContaining('공식 앱'), findsOneWidget);
    expect(find.textContaining('홈 화면에 추가하여 앱처럼 빠르게 실행하세요'), findsOneWidget);
  });

  testWidgets('오늘 모임 세션 & 대진 설정 바텀시트: 직전 설정값 자동 기억(Persistence) 및 [설정 초기화] 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 0. [+ 새 모임 시작하기]를 통해 모임 생성 후 일정/모임 진입
    await tester.tap(find.text('+ 새 모임 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('새 모임 시작하기'), findsOneWidget);
    expect(find.text('설정 초기화'), findsOneWidget);

    await tester.tap(find.textContaining('다음: 모임 정보 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('다음: 참석자 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('모임 시작 & 일정/모임 열기'));
    await tester.pumpAndSettle();

    // 일정/모임 하단 [대진표 설정수정] 버튼 클릭 -> '오늘 모임 세션 & 대진 설정' 바텀시트 오픈
    final startSessionBtn = find.text('대진표 설정수정');
    expect(startSessionBtn, findsOneWidget);
    await tester.tap(startSessionBtn);
    await tester.pumpAndSettle();

    expect(find.text('대진 생성 및 시작'), findsWidgets);
    expect(find.byKey(const Key('reset_session_settings_button')), findsOneWidget);
    expect(find.text('설정 초기화'), findsOneWidget);
    // 기본 화면에서 '시작 코트 번호 지정' 섹션이 제거되었는지 확인
    expect(find.text('시작 코트 번호 지정'), findsNothing);

    // 1. 설정값 변경: [풀리그전], [급수 밸런스], [고정 파트너]
    await tester.tap(find.text('풀리그전'));
    await tester.pumpAndSettle();

    final balanceModeCard = find.text('급수 밸런스');
    await tester.ensureVisible(balanceModeCard);
    await tester.pumpAndSettle();
    await tester.tap(balanceModeCard);
    await tester.pumpAndSettle();

    final fixedPartnerBtn = find.text('고정 파트너');
    await tester.ensureVisible(fixedPartnerBtn);
    await tester.pumpAndSettle();
    await tester.tap(fixedPartnerBtn);
    await tester.pumpAndSettle();

    expect(find.text('복식 페어 편성 목록'), findsOneWidget);

    // 2. 바텀시트를 닫았다가 다시 열어도 직전 설정값이 그대로 유지되는지 검증
    Navigator.of(tester.element(find.text('대진 생성 및 시작').first)).pop();
    await tester.pumpAndSettle();

    await tester.tap(startSessionBtn);
    await tester.pumpAndSettle();

    expect(find.text('직전 설정 기억됨'), findsOneWidget);
    expect(find.text('복식 페어 편성 목록'), findsOneWidget);

    // 3. 상단 우측 [설정 초기화] 버튼 클릭 시 기본 권장 설정으로 즉시 리셋되는지 검증
    final resetBtn = find.byKey(const Key('reset_session_settings_button'));
    await tester.ensureVisible(resetBtn);
    await tester.pumpAndSettle();
    await tester.tap(resetBtn);
    await tester.pumpAndSettle();

    expect(find.text('기본 권장 설정'), findsOneWidget);
    expect(find.text('복식 페어 편성 목록'), findsNothing);
    expect(find.text('+ 고정 파트너 추가'), findsOneWidget);
  });

  testWidgets('대진표 탭: 실시간 코트 증감([+ 코트 추가] / [- 코트 축소]), 빈 코트 슬롯 생성 및 축소 확인 다이얼로그 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. [+ 새 모임 시작하기]로 모임 생성 후 1라운드 대진 시작
    await tester.tap(find.text('+ 새 모임 시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('다음: 모임 정보 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('다음: 참석자 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('모임 시작 & 일정/모임 열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('대진표 설정수정'));
    await tester.pumpAndSettle();

    final balanceModeOption = find.text('급수 밸런스');
    await tester.ensureVisible(balanceModeOption);
    await tester.pumpAndSettle();
    await tester.tap(balanceModeOption);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_session_and_generate_button')));
    await tester.pumpAndSettle();

    expect(find.text('대진 생성 및 시작'), findsNothing);
    // 1) 진입 즉시 상단 스크롤 없이 [1 라운드] 탭과 [1번 코트], [2번 코트] 매칭 카드가 즉시 노출되는지 확인
    expect(find.text('1 라운드'), findsOneWidget);
    expect(find.text('1번 코트'), findsOneWidget);
    expect(find.text('2번 코트'), findsOneWidget);

    // 2) 상단 설정/통계 영역은 기본적으로 접힌 상태(Collapsed)이며 설정 아이콘 토글 버튼 제공 확인
    expect(find.byKey(const Key('toggle_operation_summary_button')), findsOneWidget);
    expect(find.text('출전 인원'), findsNothing);

    // 3) 상단 불필요 요소 제거 확인: 모임 경기 전적 버튼 제거, 5코트 변경은 운영 요약 내부로 이동
    expect(find.textContaining('모임 경기 전적'), findsNothing);
    expect(find.textContaining('🏟️'), findsNothing);
    expect(find.textContaining('(1~5번)'), findsNothing);
    expect(find.textContaining('급수합'), findsNothing);

    // [운영 요약 및 설정] 토글 클릭 -> 통계 박스 펼치기 및 '출전 인원' 명단 팝업 확인
    await tester.tap(find.byKey(const Key('toggle_operation_summary_button')));
    await tester.pumpAndSettle();
    expect(find.text('출전 인원'), findsOneWidget);
    expect(find.text('코트 수'), findsOneWidget);
    expect(find.text('5코트'), findsOneWidget);

    await tester.tap(find.text('출전 인원'));
    await tester.pumpAndSettle();
    expect(find.text('출전 인원 명단'), findsOneWidget);
    expect(find.text('안세영 (A조)'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 4) [코트 수] 카드 클릭 -> 코트 변경 다이얼로그 오픈 및 [+ 코트 추가] / [- 코트 축소] 확인
    await tester.tap(find.byKey(const Key('open_court_change_dialog_button')));
    await tester.pumpAndSettle();
    expect(find.text('실시간 운영 코트 변경'), findsOneWidget);
    expect(find.text('운영 코트 5면'), findsOneWidget);

    final increaseBtn = find.byKey(const Key('increase_court_button'));
    final decreaseBtn = find.byKey(const Key('decrease_court_button'));
    expect(increaseBtn, findsOneWidget);
    expect(decreaseBtn, findsOneWidget);

    // [+ 코트 추가] 클릭 -> 6코트 및 빈 코트 1면 반영 확인
    await tester.tap(increaseBtn);
    await tester.pumpAndSettle();
    expect(find.text('운영 코트 6면'), findsOneWidget);
    expect(find.text('빈 코트 1면'), findsWidgets);

    // 다이얼로그 닫고 아래로 스크롤하여 새로 생성된 '빈 코트 슬롯' 카드 노출 확인
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('6코트'), findsOneWidget);

    final courtScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('빈 코트 슬롯'),
      350.0,
      scrollable: courtScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('빈 코트 슬롯'), findsOneWidget);
    expect(find.text('배정된 경기가 없는 빈 코트 슬롯입니다'), findsOneWidget);

    // 다시 상단으로 스크롤하여 [6코트] 다이얼로그에서 [- 코트 축소] 클릭 -> 빈 코트 우선 제거 확인
    await tester.scrollUntilVisible(
      find.byKey(const Key('open_court_change_dialog_button')),
      -350.0,
      scrollable: courtScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_court_change_dialog_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decrease_court_button')));
    await tester.pumpAndSettle();
    expect(find.text('빈 코트 1면'), findsNothing);
    expect(find.text('운영 코트 5면'), findsOneWidget);

    // 5) 빈 코트가 없는 상태에서 [- 코트 축소] 클릭 -> 진행/배정 중인 코트 축소 확인 다이얼로그 호출 확인
    await tester.tap(find.byKey(const Key('decrease_court_button')));
    await tester.pumpAndSettle();
    expect(find.text('진행/배정 중인 코트 축소 확인'), findsOneWidget);
    expect(
      find.text('이전 완료된 라운드 및 완료된 경기 기록은 손실 없이 안전하게 보존됩니다.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reduce_court_to_waiting_button')), findsOneWidget);
    expect(find.byKey(const Key('reduce_court_move_slot_button')), findsOneWidget);

    // [대기 인원으로 전환 후 축소] 클릭 시 코트가 4면으로 축소되고 대기(휴식) 인원으로 전환되는지 확인
    await tester.tap(find.byKey(const Key('reduce_court_to_waiting_button')));
    await tester.pumpAndSettle();
    expect(find.text('진행/배정 중인 코트 축소 확인'), findsNothing);
    expect(find.text('4코트'), findsOneWidget);
    expect(find.text('현재 휴식 중: '), findsOneWidget);
  });

  testWidgets('출석부 화면: 가상 키보드 오픈(viewInsets.bottom > 0 또는 검색창 포커스) 시 하단 플로팅 바 자동 숨김 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 지난 모임 열기 -> 하단 플로팅 바('대진표 설정수정') 기본 노출 확인
    final archivedCard = find.text('2026.09.22 화요 정기 모임');
    await tester.ensureVisible(archivedCard);
    await tester.pumpAndSettle();
    await tester.tap(archivedCard);
    await tester.pumpAndSettle();

    expect(find.text('대진표 설정수정'), findsOneWidget);

    // 2. 가상 키보드 활성화 시뮬레이션 (viewInsets.bottom = 300) -> 플로팅 바 자동 숨김 확인
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.text('대진표 설정수정'), findsNothing);

    // 3. 가상 키보드 닫힘 시뮬레이션 (viewInsets.bottom = 0) -> 플로팅 바 재노출 확인
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('대진표 설정수정'), findsOneWidget);
  });

  testWidgets('Part 1~3 통합 검증: 대진표 안전장치/재편성, PRO 잠금 가드 & 연간 회비 현황표, 3화면 스와이프', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // [Part 3-1] 메인 3개 화면(회원명부 0 ↔ 출석부 1 ↔ 대진표 2) PageView 존재 확인
    expect(find.byKey(const Key('main_three_tab_page_view')), findsOneWidget);

    // [Part 3-2] 좌측 드로어 메뉴에서 브랜딩('쓸만한 민턴총무'), 클럽 드롭다운(▾), 메뉴 명칭('모임/행사', '금전출납부') 및 비구독자 안내 모달 노출 검증
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_brand_title')), findsOneWidget);
    expect(find.text('쓸만한 민턴총무'), findsOneWidget);
    expect(find.textContaining('진행 모임:'), findsNothing);
    expect(find.byKey(const Key('drawer_club_selector_button')), findsOneWidget);
    expect(find.byKey(const Key('drawer_club_dropdown_arrow')), findsOneWidget);
    expect(find.text('모임/행사'), findsWidgets);
    expect(find.text('모임 출석 체크 및 참가비 수납'), findsOneWidget);
    expect(find.text('금전출납부'), findsOneWidget);
    expect(find.text('월회비 · 일반운영비 · 행사 정산'), findsOneWidget);

    // 드로어 상단 클럽명('메가 배드민턴 클럽 ▾') 클릭 시 등록된 클럽 목록 및 '+ 새 모임/클럽 만들기' 메뉴 노출 확인
    await tester.tap(find.byKey(const Key('drawer_club_selector_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer_create_club_menu_item')), findsOneWidget);
    expect(find.text('+ 새 모임/클럽 만들기'), findsOneWidget);
    // 팝업 메뉴 닫기 (현재 클럽 재선택)
    await tester.tap(find.text('메가 배드민턴 클럽').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('금전출납부'));
    await tester.pumpAndSettle();

    // 비구독자 진입 차단 및 PRO 기능 안내 모달 확인
    expect(
      find.text('클럽 총무님을 위한 연간 회비 장부 및 미납 알림 기능 안내'),
      findsOneWidget,
    );

    // 모달에서 [PRO 구독 활성화 후 열기] 클릭 -> isProUser == true 전환 및 회비 현황표 오픈 확인
    await tester.tap(find.byKey(const Key('activate_pro_and_open_fee_ledger_button')));
    await tester.pumpAndSettle();

    // [Part 2] 금전출납부 핵심 UI 검증 (상단 아코디언 기본 접힘 & 슬림화, 2D 아이콘 및 버튼 너비 비율)
    expect(find.text('금전출납부'), findsWidgets);
    expect(find.text('클럽 통합 금전출납부'), findsNothing);
    expect(find.text('회비&계좌설정'), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet), findsWidgets);
    expect(find.byIcon(Icons.article), findsWidgets);
    expect(
      tester.getSize(find.byKey(const Key('toggle_fee_policy_button'))).width,
      greaterThan(tester.getSize(find.byKey(const Key('toggle_fee_rules_button'))).width),
    );
    expect(find.text('클럽 기본 회비 정책 & 입금 계좌 설정'), findsNothing);

    // [회비&계좌설정] 클릭 시 정책 및 계좌 카드 펼침 및 입금 계좌 우측 '수정' 버튼 확인
    await tester.tap(find.byKey(const Key('toggle_fee_policy_button')));
    await tester.pumpAndSettle();
    expect(find.text('클럽 기본 회비 정책 & 입금 계좌 설정'), findsOneWidget);
    expect(find.text('30,000원'), findsWidgets);
    expect(find.text('매월 25일'), findsOneWidget);
    expect(find.byKey(const Key('edit_bank_account_button')), findsOneWidget);
    expect(find.text('수정'), findsWidgets);
    // 다시 접기
    await tester.tap(find.byKey(const Key('toggle_fee_policy_button')));
    await tester.pumpAndSettle();
    expect(find.text('클럽 기본 회비 정책 & 입금 계좌 설정'), findsNothing);

    // [회비회칙] 아코디언 펼치기 및 '회칙 저장' 버튼 확인
    expect(find.text('회비회칙'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle_fee_rules_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save_fee_rules_button')), findsOneWidget);
    expect(find.text('회칙 저장'), findsOneWidget);
    expect(find.text('회칙/메모 영구 저장'), findsNothing);
    await tester.tap(find.byKey(const Key('toggle_fee_rules_button')));
    await tester.pumpAndSettle();

    // 상단 대시보드 통계(당월 수납액 · 당월 미납액), [👨‍👩‍👧 가족할인 회원] 필터, [가나다순 / 등록순 정렬] 토글 확인
    expect(find.textContaining('당월 수납액'), findsOneWidget);
    expect(find.textContaining('당월 미납액'), findsOneWidget);
    expect(find.textContaining('👨‍👩‍👧 가족할인 회원'), findsOneWidget);
    expect(find.byKey(const Key('toggle_fee_matrix_sort_button')), findsOneWidget);
    expect(find.text('가나다순 정렬'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle_fee_matrix_sort_button')));
    await tester.pumpAndSettle();
    expect(find.text('등록순 정렬'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toggle_fee_matrix_sort_button')));
    await tester.pumpAndSettle();
    expect(find.text('가나다순 정렬'), findsOneWidget);

    // 상단 우측 내보내기 심플 아이콘 버튼 클릭 시 4대 내보내기 바텀시트 노출 확인
    expect(find.byKey(const Key('fee_export_menu_button')), findsOneWidget);
    expect(find.byKey(const Key('fee_web_viewer_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fee_export_menu_button')));
    await tester.pumpAndSettle();
    expect(find.text('📢 당월 미납자 알림 문구 복사'), findsOneWidget);
    expect(find.text('📸 장부 이미지 내보내기'), findsOneWidget);
    expect(find.text('🔗 실시간 회비 웹뷰어 링크 복사'), findsOneWidget);
    expect(find.text('📊 엑셀 다운로드'), findsOneWidget);
    // 바텀시트 닫기
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // 상단 우측 [실시간 웹뷰어] 아이콘 버튼 진입 시 읽기 전용 뷰어 및 하단 배너 광고 슬롯 노출 확인
    await tester.tap(find.byKey(const Key('fee_web_viewer_button')));
    await tester.pumpAndSettle();
    expect(find.text('LIVE 읽기 전용 웹뷰어'), findsOneWidget);
    expect(find.textContaining('하단 스폰서/광고 배너'), findsOneWidget);
  });

  testWidgets('Part 1 대진표 안전장치: [현재 대진표 확인], 2단계 초기화 경고 모달, [남은 라운드 재편성] 및 상단 회비 칩 터치 필터링 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 모임/행사 상단 앱바 우측 '메가 배드민턴 클럽' 중복 칩 제거 확인
    expect(find.text('메가 배드민턴 클럽'), findsNothing);

    // 대진 기록이 있는 모임('2026.09.22 화요 정기 모임') 열기
    final archivedCard = find.text('2026.09.22 화요 정기 모임');
    await tester.ensureVisible(archivedCard);
    await tester.pumpAndSettle();
    await tester.tap(archivedCard);
    await tester.pumpAndSettle();

    // 1. [출석부] 상단 회비 수납 현황 카드 내 [연간/월별 회비 현황표 ->] 버튼이 삭제되었는지 및 슬림 대시보드(출석/수납/SMS 아이콘) 확인
    expect(find.textContaining('연간/월별 회비 현황표'), findsNothing);
    expect(find.textContaining('출석'), findsWidgets);
    expect(find.textContaining('수납'), findsWidgets);
    expect(find.byKey(const Key('unpaid_guide_sms_button')), findsOneWidget);

    // 1-2. [출석부] 필터 바 내 [미납] 필터 칩 터치 시 참석자 리스트 즉시 필터링 및 재터치 시 해제 검증
    final unpaidChip = find.text('미납');
    expect(unpaidChip, findsOneWidget);

    await tester.tap(unpaidChip);
    await tester.pumpAndSettle();
    // 필터 초기화 버튼이 노출되면 필터가 활성화된 상태임을 의미
    expect(find.text('필터 초기화'), findsOneWidget);

    // 같은 칩을 한 번 더 탭하면 필터가 해제되는지 확인
    await tester.tap(unpaidChip);
    await tester.pumpAndSettle();
    expect(find.text('필터 초기화'), findsNothing);

    // 2. 이미 대진표가 생성된 상태이므로 하단 기본 버튼이 [현재 대진표 확인] 및 [대진표 설정수정]으로 깔끔하게 표시되고 좌측 잘리는 텍스트('진행 대진...')가 제거되었는지 확인
    expect(find.text('현재 대진표 확인'), findsOneWidget);
    expect(find.text('대진표 설정수정'), findsOneWidget);
    expect(find.textContaining('진행 대진'), findsNothing);

    // 3. [대진표 설정수정] 모달 내부에서도 [📋 현재 대진표 이어보기], [남은 라운드 재편성], [대진표 전체 재편성] 분리 확인
    await tester.tap(find.text('대진표 설정수정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('continue_existing_bracket_button')), findsOneWidget);
    expect(find.byKey(const Key('reshuffle_remaining_rounds_button')), findsOneWidget);
    expect(find.text('대진표 전체 재편성'), findsOneWidget);

    // [대진표 전체 재편성] 클릭 시 2단계 파괴적 액션 방지 경고 모달 필수 노출 확인
    await tester.tap(find.text('대진표 전체 재편성'));
    await tester.pumpAndSettle();
    expect(
      find.text('⚠️ 경고: 이미 진행된 매칭과 입력된 경기 점수/기록이 모두 영구 삭제됩니다. 정말 새로 생성하시겠습니까?'),
      findsOneWidget,
    );
    expect(find.text('취소 (기존 유지)'), findsOneWidget);
    expect(find.text('기록 삭제 후 새로 생성'), findsOneWidget);

    // [취소 (기존 유지)] 클릭 시 기존 대진표 유지 확인
    await tester.tap(find.text('취소 (기존 유지)'));
    await tester.pumpAndSettle();

    // [📋 현재 대진표 이어보기] 클릭 시 기존 데이터 유실 없이 대진표 화면으로 즉시 이동 확인
    await tester.tap(find.byKey(const Key('continue_existing_bracket_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('court_header_live_viewer_button')), findsOneWidget);

    // 4. [대진표] 라운드 가시성 & 중복 버튼 제거 검증:
    // - '1 라운드' 옆에 '+ 라운드 추가' 버튼이 첫 화면에서 즉시 노출
    // - [다음 라운드 스마트 편성] 버튼 완전 제거 확인
    expect(find.text('1 라운드'), findsOneWidget);
    expect(find.byKey(const Key('court_add_round_button')), findsOneWidget);
    expect(find.text('+ 라운드 추가'), findsOneWidget);
    expect(find.text('+ 특별 매치 추가'), findsOneWidget);
    expect(find.text('🔄 다음 라운드 스마트 편성'), findsNothing);

    // 4-2. [대진표] 코트 점수 입력 필드 터치(포커스) 시 전체 선택(Select All) 및 숫자 입력 시 선행 '0' 자동 제거 검증
    final scoreFields = find.byType(TextField);
    expect(scoreFields, findsWidgets);
    await tester.tap(scoreFields.first);
    await tester.pumpAndSettle();
    final TextField tappedScoreField = tester.widget<TextField>(scoreFields.first);
    expect(tappedScoreField.controller?.selection.baseOffset, 0);
    expect(
      tappedScoreField.controller?.selection.extentOffset,
      tappedScoreField.controller?.text.length,
    );

    // 5. [남은 라운드 재편성] 및 [대진표 전체 재편성] 버튼이 '운영 요약 펼침' 안이 아닌 바깥에 즉시 노출되는지 확인
    final reshuffleBtn = find.byKey(const Key('court_reshuffle_remaining_button'));
    final courtResetBtn = find.byKey(const Key('court_reset_and_regenerate_button'));
    expect(reshuffleBtn, findsOneWidget);
    expect(courtResetBtn, findsOneWidget);

    // 6. [남은 라운드 재편성] 클릭 시 경고 팝업 필수 노출 검증
    await tester.tap(reshuffleBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('진행 중/완료된 경기는 유지되며, 대기 중인 라운드만 현재 출석 인원으로 재편성됩니다. 진행하시겠습니까?'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('court_cancel_reshuffle_button')), findsOneWidget);
    expect(find.byKey(const Key('court_confirm_reshuffle_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('court_cancel_reshuffle_button')));
    await tester.pumpAndSettle();

    // 7. [대진표 전체 재편성] 클릭 시 경고 팝업 필수 노출 검증
    await tester.tap(courtResetBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('⚠️ 완료된 경기 기록과 현재 점수가 모두 삭제됩니다. 처음부터 다시 생성하시겠습니까?'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('court_cancel_regenerate_button')), findsOneWidget);
    expect(find.byKey(const Key('court_confirm_regenerate_button')), findsOneWidget);

    // [취소] 클릭 시 기존 완료 경기 보존 확인
    await tester.tap(find.byKey(const Key('court_cancel_regenerate_button')));
    await tester.pumpAndSettle();
    expect(find.text('+ 라운드 추가'), findsOneWidget);
  });

  testWidgets('단일 퍼플 톤 원복, AppBar 좌측 페이지명 전환(회원 명부/출석부/대진표), 정중앙(Center) 3도트 인디케이터(● ○ ○) 정렬 검증', (WidgetTester tester) async {
    // 1. 시범 적용했던 5개 분기 컬러가 모두 해제되고 단일 시그니처 퍼플 톤으로 원복되었는지 검증
    expect(AppTheme.usePageSpecificAccentThemes, isFalse);
    for (int i = 0; i < 5; i++) {
      final p = AppTheme.getPagePalette(i);
      expect(p.primary, AppTheme.primaryDark);
      expect(p.secondary, AppTheme.primaryMint);
      expect(p.softTint, AppTheme.pastelPeriwinkle);
    }

    // 2. 3개 메인 스와이프 페이지 타이틀 및 3도트 인디케이터 문자열 검증
    expect(AppTheme.getMainPageTitle(0), '회원 명부');
    expect(AppTheme.getMainPageTitle(1), '모임/행사');
    expect(AppTheme.getMainPageTitle(2), '대진표');
    expect(AppTheme.buildDotIndicatorString(0), '● ○ ○');
    expect(AppTheme.buildDotIndicatorString(1), '○ ● ○');
    expect(AppTheme.buildDotIndicatorString(2), '○ ○ ●');

    // 3. 실제 앱 화면에서 스와이프/이동 시 AppBar 좌측 타이틀과 정중앙(Center) 고정 3도트 인디케이터가 동일한 절대 좌표(x, y)에 유지되는지 검증
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    final double screenCenterX = tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;

    // 기본 진입(Page 1 모임/행사): '모임/행사' + 정중앙 '○ ● ○'
    final title1Finder = find.byKey(const Key('app_bar_page_title_1'));
    final dot1Finder = find.byKey(const Key('top_page_dot_indicator_1'));
    expect(title1Finder, findsOneWidget);
    expect(dot1Finder, findsOneWidget);
    expect(find.text('모임/행사'), findsWidgets);
    expect(find.text('○ ● ○'), findsOneWidget);
    expect(tester.getCenter(dot1Finder).dx, closeTo(screenCenterX, 0.5));
    // 임시 텍스트 뱃지 완전 삭제 확인
    expect(find.textContaining('1/5 회원 명단'), findsNothing);
    expect(find.textContaining('SAGE 그린 활동 톤'), findsNothing);

    final Offset title1TopLeft = tester.getTopLeft(title1Finder);
    final Offset dot1TopLeft = tester.getTopLeft(dot1Finder);

    // 드로어로 Page 0(회원 명부) 이동: '회원 명부' + 정중앙 '● ○ ○'
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('회원명부'));
    await tester.pumpAndSettle();

    final title0Finder = find.byKey(const Key('app_bar_page_title_0'));
    final dot0Finder = find.byKey(const Key('top_page_dot_indicator_0'));
    expect(title0Finder, findsOneWidget);
    expect(dot0Finder, findsOneWidget);
    expect(find.text('회원 명부'), findsOneWidget);
    expect(find.text('● ○ ○'), findsOneWidget);
    expect(tester.getCenter(dot0Finder).dx, closeTo(screenCenterX, 0.5));
    expect(find.text('가족회원'), findsWidgets);
    expect(find.text('가족할인 20,000원'), findsNothing);

    final Offset title0TopLeft = tester.getTopLeft(title0Finder);
    final Offset dot0TopLeft = tester.getTopLeft(dot0Finder);
    expect(title0TopLeft, equals(title1TopLeft));
    expect(dot0TopLeft, equals(dot1TopLeft));

    // 회원 명부 카드 터치 -> 회원 상세 팝업 내 '특이사항:' 라벨 노출 확인 ('회비 정책:' 미노출)
    await tester.tap(find.text('강호동').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('특이사항:'), findsOneWidget);
    expect(find.textContaining('회비 정책:'), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    // 드로어로 Page 2(대진표) 이동: '대진표' + 정중앙 '○ ○ ●'
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('대진표').first);
    await tester.pumpAndSettle();

    final title2Finder = find.byKey(const Key('app_bar_page_title_2'));
    final dot2Finder = find.byKey(const Key('top_page_dot_indicator_2'));
    expect(title2Finder, findsOneWidget);
    expect(dot2Finder, findsOneWidget);
    expect(find.text('○ ○ ●'), findsOneWidget);
    expect(tester.getCenter(dot2Finder).dx, closeTo(screenCenterX, 0.5));

    final Offset title2TopLeft = tester.getTopLeft(title2Finder);
    final Offset dot2TopLeft = tester.getTopLeft(dot2Finder);
    expect(title2TopLeft, equals(title1TopLeft));
    expect(dot2TopLeft, equals(dot1TopLeft));
  });

  testWidgets('[월회비 관리 PRO] 금전출납부 타이틀, 기초이월 팝업 간소화, 전체 잔액 요약 헤더, 3개 탭([연간 월회비] | [일반운영비] | [행사/모임비]) 및 출납부 상세 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 드로어를 열어 [금전출납부] 클릭 -> PRO 활성화 후 진입
    await tester.tap(find.byTooltip('메뉴 열기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('금전출납부'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activate_pro_and_open_fee_ledger_button')));
    await tester.pumpAndSettle();

    // 0. 상단 헤더 타이틀 '금전출납부' 및 장부 전체 잔액 요약(클럽 총 잔액 = 기초이월 + 월회비 + 운영비 + 행사정산) 노출 확인
    expect(find.text('금전출납부'), findsWidgets);
    expect(find.text('클럽 통합 금전출납부'), findsNothing);
    expect(find.byKey(const Key('fee_export_menu_button')), findsOneWidget);
    expect(find.byKey(const Key('fee_web_viewer_button')), findsOneWidget);
    expect(find.byKey(const Key('ledger_total_balance_header_summary')), findsOneWidget);
    expect(find.text('클럽 총 잔액'), findsOneWidget);
    expect(find.text('기초이월'), findsOneWidget);
    expect(find.text('월회비'), findsOneWidget);
    expect(find.text('운영비'), findsOneWidget);
    expect(find.text('행사정산'), findsOneWidget);

    // 0-1. 기초이월 팝업창 간소화 검증: '기초 이월금 설정' 팝업에 '기초 이월금 (원)' 단일 필드만 존재하고 '일반운영비 보정액' 제거 확인
    await tester.tap(find.byKey(const Key('ledger_total_balance_header_summary')));
    await tester.pumpAndSettle();
    expect(find.text('기초 이월금 설정'), findsOneWidget);
    expect(find.byKey(const Key('base_carryover_balance_field')), findsOneWidget);
    expect(find.textContaining('일반운영비 보정액'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 1. 상단 서브탭 3개([연간 월회비] / [일반운영비] / [행사/모임비]) 및 상단 고정된 '월별 수납 요약' 행('[고정]' 뱃지 제거) 확인
    expect(find.byKey(const Key('subtab_annual_fee_ledger')), findsOneWidget);
    expect(find.byKey(const Key('subtab_general_operation_ledger')), findsOneWidget);
    expect(find.byKey(const Key('subtab_event_expense_ledger')), findsOneWidget);
    expect(find.text('연간 월회비'), findsOneWidget);
    expect(find.text('일반운영비'), findsOneWidget);
    expect(find.text('행사/모임비'), findsOneWidget);
    final pinnedSummaryFinder = find.byKey(const Key('pinned_monthly_summary_row'));
    expect(pinnedSummaryFinder, findsOneWidget);
    expect(find.text('월별 수납 요약'), findsOneWidget);
    expect(find.text('고정'), findsNothing);

    // 2. 좌측 회원명 터치 시 '회원 상세 카드' 팝업('특이사항:' 라벨) 및 전화/문자 버튼 노출 확인
    final memberTrigger = find.byKey(const Key('member_detail_trigger_m06')); // 강호동
    await tester.ensureVisible(memberTrigger);
    await tester.pumpAndSettle();
    // 상단 고정 행이 첫 번째 회원 행보다 위(작은 y좌표)에 위치하는지 확인
    expect(
      tester.getTopLeft(pinnedSummaryFinder).dy,
      lessThan(tester.getTopLeft(memberTrigger).dy),
    );

    await tester.tap(memberTrigger);
    await tester.pumpAndSettle();
    expect(find.textContaining('특이사항:'), findsOneWidget);
    expect(find.textContaining('회비 정책:'), findsNothing);
    expect(find.text('전화 걸기'), findsOneWidget);
    expect(find.text('문자 보내기'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    // 3. [그룹화 보기 ⌵] 토글 클릭 시 그룹별 섹션 헤더(운영진/가족회원/일반 정회원/휴면·면제) 노출 확인
    final groupToggleBtn = find.byKey(const Key('toggle_fee_matrix_grouping_button'));
    expect(groupToggleBtn, findsOneWidget);
    await tester.ensureVisible(groupToggleBtn);
    await tester.pumpAndSettle();
    await tester.tap(groupToggleBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group_header_exec')), findsOneWidget);
    expect(find.byKey(const Key('group_header_family')), findsOneWidget);
    expect(find.byKey(const Key('group_header_regular')), findsOneWidget);
    expect(find.byKey(const Key('group_header_resting_exempt')), findsOneWidget);

    // 4. [일반운영비] 탭 전환 시 일반운영비 출납 요약, 일상 지출/일반 수입 내역 및 내역등록 팝업 상단 '수입'/'지출' 탭 확인
    await tester.tap(find.byKey(const Key('subtab_general_operation_ledger')));
    await tester.pumpAndSettle();

    expect(find.text('일반운영비 출납 요약'), findsOneWidget);
    expect(find.text('일반운영비 입출금 내역'), findsOneWidget);
    expect(find.byKey(const Key('add_general_operation_item_btn')), findsOneWidget);
    expect(find.text('9월 구립체육관 정기 코트 대관료'), findsOneWidget);
    expect(find.text('공용 셔틀콕 5타 구매'), findsOneWidget);
    expect(find.text('신입 회원 가입비 수납 (2명)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_general_operation_item_btn')));
    await tester.pumpAndSettle();
    expect(find.text('일반운영비 내역 등록'), findsOneWidget);
    expect(find.byKey(const Key('general_op_dialog_tab_income')), findsOneWidget);
    expect(find.byKey(const Key('general_op_dialog_tab_expense')), findsOneWidget);
    expect(find.text('➕ 일반 수입 (가입비·찬조)'), findsNothing);
    expect(find.text('➖ 일상 지출 (대관·콕·비품)'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 5. [행사/모임비] 탭 전환 시 '행사 리스트', '모임/행사에서 가져오기', 드롭다운 선택형, 행사 수정(연필) 아이콘 및 다이얼로그, '입출금 상세 내역' 우측 [+ 내역 추가] 버튼 노출 확인
    await tester.tap(find.byKey(const Key('subtab_event_expense_ledger')));
    await tester.pumpAndSettle();

    expect(find.text('행사 리스트'), findsOneWidget);
    expect(find.text('행사비 / 모임비 정산 선택'), findsNothing);
    expect(find.byKey(const Key('create_club_event_button')), findsOneWidget);
    expect(find.byKey(const Key('import_session_event_button')), findsOneWidget);
    expect(find.text('모임/행사에서 가져오기'), findsOneWidget);
    expect(find.text('일정/모임에서 가져오기'), findsNothing);
    expect(find.byKey(const Key('club_event_selector_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('edit_club_event_button')), findsOneWidget);
    expect(find.byKey(const Key('delete_club_event_button')), findsOneWidget);
    expect(find.text('엑셀 다운로드 (CSV)'), findsNothing);
    expect(find.byKey(const Key('export_event_expense_csv_btn')), findsNothing);
    expect(find.byKey(const Key('add_event_expense_item_btn')), findsOneWidget);
    expect(find.text('입출금 상세 내역'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('add_event_expense_item_btn'))).dx,
      greaterThan(tester.getTopLeft(find.text('입출금 상세 내역')).dx),
    );
    expect(find.textContaining('2026년 가을 친선 교류전 및 정산'), findsWidgets);

    // 행사 카드 우측 수정(연필) 아이콘 클릭 -> 행사명 및 일자 수정 다이얼로그 연결 확인
    await tester.tap(find.byKey(const Key('edit_club_event_button')));
    await tester.pumpAndSettle();
    expect(find.text('행사/모임 정보 수정'), findsOneWidget);
    expect(find.byKey(const Key('edit_club_event_title_field')), findsOneWidget);
    expect(find.byKey(const Key('edit_club_event_date_field')), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('토너먼트 대회/행사 대진 운영 및 웹뷰어 브래킷 트리 연동 통합 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CockMatchApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. [+ 새 모임 시작하기] -> 모임 생성 및 일정/모임 진입
    await tester.tap(find.text('+ 새 모임 시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('다음: 모임 정보 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('다음: 참석자 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('모임 시작 & 일정/모임 열기'));
    await tester.pumpAndSettle();

    // 2. 대진 설정 바텀시트 오픈하여 경기 방식을 [토너먼트]로 선택 후 대진 생성
    final startSessionBtn = find.text('대진표 설정수정');
    expect(startSessionBtn, findsOneWidget);
    await tester.tap(startSessionBtn);
    await tester.pumpAndSettle();

    final tournamentOption = find.text('토너먼트');
    await tester.ensureVisible(tournamentOption);
    await tester.pumpAndSettle();
    await tester.tap(tournamentOption);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_session_and_generate_button')));
    await tester.pumpAndSettle();

    if (find.byKey(const Key('confirm_regenerate_bracket_button')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('confirm_regenerate_bracket_button')));
      await tester.pumpAndSettle();
    }

    // 3. 대진표 화면: 토너먼트 모드일 때 [ 🏆 전체 토너먼트 트리 보기 ] 단독 가로 버튼 노출 확인
    final openTreeBtn = find.byKey(const Key('open_tournament_tree_dialog_button'));
    expect(openTreeBtn, findsOneWidget);
    expect(find.textContaining('전체 토너먼트 트리 보기'), findsOneWidget);

    // 코트 매치 카드 상단에 토너먼트 라운드/경기 라벨 표시 확인 (예: [8강 1경기], [준결승 1경기], [결승전] 등)
    expect(find.textContaining('경기'), findsWidgets);

    // 4. [전체 토너먼트 트리 보기] 버튼 클릭 -> 팝업 다이얼로그 오픈 및 TournamentBracketTreeWidget 렌더링 확인
    await tester.tap(openTreeBtn);
    await tester.pumpAndSettle();

    expect(find.text('토너먼트 전체 브래킷 (트리 보기)'), findsOneWidget);
    expect(find.byType(TournamentBracketTreeWidget), findsOneWidget);
    expect(find.byTooltip('확대 (+)'), findsOneWidget);
    expect(find.byTooltip('축소 (-)'), findsOneWidget);
    expect(find.byTooltip('100% 원래 크기로 초기화'), findsOneWidget);

    // 줌/인/아웃/초기화 버튼 탭 동작 확인
    await tester.tap(find.byTooltip('확대 (+)'));
    await tester.pump();
    await tester.tap(find.byTooltip('축소 (-)'));
    await tester.pump();
    await tester.tap(find.byTooltip('100% 원래 크기로 초기화'));
    await tester.pump();

    // 다이얼로그 닫기 버튼 탭
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('토너먼트 전체 브래킷 (트리 보기)'), findsNothing);

    // 5. 드로어 메뉴 열어서 [웹뷰어]로 이동 -> 실시간 토너먼트 브래킷 트리(live_tournament_bracket_tree) 자동 렌더링 검증
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('웹뷰어'));
    await tester.pumpAndSettle();

    // 웹뷰어 화면에서 토너먼트 브래킷 트리가 메인 뷰로 자동 렌더링되는지 확인
    expect(find.byKey(const Key('live_tournament_bracket_tree')), findsOneWidget);
    expect(find.byType(TournamentBracketTreeWidget), findsOneWidget);
    expect(find.text('핀치 줌 & 자유 이동'), findsOneWidget);
    expect(find.text('두 손가락 확대/축소 및 상하좌우 드래그 지원'), findsOneWidget);
  });

  testWidgets('회원 명부 화면: 등록 회원이 0명일 때 빈 화면(Empty State) 디자인 및 등록 액션 버튼 연동 검증', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentClubMembersProvider.overrideWith((ref) => []),
          filteredMembersProvider.overrideWith((ref) => []),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ClubMemberPoolScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 전체 회원 0명 빈 화면 UI 확인
    expect(find.text('등록된 회원이 없습니다.'), findsOneWidget);
    expect(find.text('카카오톡 명단을 복사해 한 번에 등록해 보세요!'), findsOneWidget);
    expect(find.text('텍스트로 대량 등록하기'), findsOneWidget);
    expect(find.text('1명씩 직접 등록'), findsOneWidget);

    // 2. [📋 텍스트로 대량 등록하기] 탭 시 대량 등록 팝업 오픈 확인
    await tester.tap(find.text('텍스트로 대량 등록하기'));
    await tester.pumpAndSettle();
    expect(find.text('명단 텍스트 대량 등록'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 3. [1명씩 직접 등록] 탭 시 단일 회원 등록 팝업 오픈 확인
    await tester.tap(find.text('1명씩 직접 등록'));
    await tester.pumpAndSettle();
    expect(find.text('신규 회원 등록'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });
}
