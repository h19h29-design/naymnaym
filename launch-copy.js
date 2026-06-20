(() => {
  const replacements = new Map([
    ["한 입의 도전으로 레벨업!", "편식을 혼내지 않고, 한 입 도전으로 바꾸는 급식 코칭 앱"],
    [
      "오늘 급식에서 안 먹는 반찬을 누르면, 놓칠 수 있는 영양소를 알려주고 한 입 도전으로 건강한 식습관을 만들어가는 앱입니다.",
      "급식표 앱이 아닙니다. 실제 NEIS 급식 정보를 바탕으로 아이의 식습관 기록, 한 입 도전, 캐릭터 성장, 부모 리포트를 연결합니다."
    ],
    ["오늘 급식 확인", "한 입 도전"],
    ["학교별 오늘 식단과 월간 급식을 한눈에 확인합니다.", "안 먹는 반찬을 혼내지 않고 작은 시도로 기록합니다."],
    ["월간 급식 캘린더", "아이별 식습관 기록"],
    ["다가오는 메뉴를 미리 보고 한 달 식습관을 준비합니다.", "먹은 정도, 어려운 이유, 사진 기록을 아이별로 남깁니다."],
    ["칼로리와 영양정보", "부모 다자녀 리포트"],
    ["칼로리, 탄수화물, 단백질, 지방 등 핵심 정보를 쉽게 봅니다.", "여러 아이의 한 입 도전, 알레르기 주의, 공유 사진을 확인합니다."],
    ["안 먹는 반찬 클릭", "알레르기 안전"],
    ["먹기 어려운 반찬을 누르면 놓칠 수 있는 영양소를 알려줍니다.", "선택한 알레르기와 관련된 메뉴는 도전보다 안전 확인을 먼저 안내합니다."],
    ["한 입 도전과 레벨업", "사진 기록"],
    ["작은 도전을 기록하고 경험치와 뱃지로 성장을 확인합니다.", "급식판 사진은 기본적으로 기기에 저장하고 선택한 사진만 부모에게 공유합니다."],
    ["보호자 주간 요약", "초등/중등/고등 모드"],
    ["편식 경향과 도전 기록을 보호자가 이해하기 쉽게 정리합니다.", "초등은 귀엽게, 중등은 게임형으로, 고등은 차분한 자기관리형으로 제공합니다."],
    ["식품영양성분DB정보", "영양소 추정 보조 자료"],
    ["음식명 기반 영양소 추정 고도화 참고 데이터", "1.0 이후 고도화 참고 자료이며 데이터 집계 기능은 포함하지 않습니다."]
  ]);

  function replaceText(root = document.body) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);

    for (const node of nodes) {
      let value = node.nodeValue;
      for (const [from, to] of replacements) {
        if (value.includes(from)) value = value.replaceAll(from, to);
      }
      node.nodeValue = value;
    }
  }

  function updateLinks() {
    for (const link of document.querySelectorAll("a")) {
      const text = link.textContent.trim();
      if (text === "개인정보처리방침 보기") link.setAttribute("href", "/privacy.html");
      if (text === "문의하기") link.setAttribute("href", "/support.html");
    }
  }

  const observer = new MutationObserver(() => replaceText());
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("load", () => {
    replaceText();
    updateLinks();
  });
  setTimeout(() => {
    replaceText();
    updateLinks();
  }, 100);
  setTimeout(() => {
    replaceText();
    updateLinks();
  }, 500);
})();
