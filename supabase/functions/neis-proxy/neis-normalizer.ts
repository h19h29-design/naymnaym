import type {
  MealDay,
  MealItem,
  School,
} from "../_shared/neis-contract/index.ts";

const ALLERGY_ANNOTATION_PATTERN = /\(([\d.,\s]+)\)/g;

const HTML_ENTITIES: Record<string, string> = {
  amp: "&",
  apos: "'",
  gt: ">",
  lt: "<",
  nbsp: " ",
  quot: '"',
};

const NUTRIENT_RULES: Array<[string[], string[]]> = [
  [["나물", "시금치", "콩나물", "채소", "샐러드", "오이", "상추", "깻잎", "브로콜리", "숙주", "미나리", "부추", "양상추", "양배추", "콜리플라워", "당근", "우엉", "연근", "도라지", "고사리", "취나물", "곤드레", "애호박", "가지", "마늘쫑", "피망", "파프리카", "아스파라거스", "케일", "시래기", "우거지", "열무", "치커리", "적채", "무말랭이", "무생채", "비름", "아욱", "근대", "냉이", "봄동", "쑥갓", "청경채", "알배기", "버섯", "표고", "느타리", "팽이", "양송이", "새송이", "만가닥", "양파", "마늘", "무"], ["식이섬유", "비타민"]],
  [["닭", "돼지", "소고기", "고기", "생선", "계란", "달걀", "두부", "고등어", "멸치", "불고기", "제육", "삼겹", "갈비", "치킨", "오리", "소시지", "햄", "베이컨", "미트볼", "함박", "탕수육", "깐풍", "라조기", "장조림", "육전", "동그랑땡", "떡갈비", "차돌", "우삼겹", "너비아니", "석쇠", "수육", "보쌈", "족발", "곱창", "순대", "육류", "안심", "등심", "목살", "주물럭", "스테이크", "꼬치", "핫바", "구이", "조림", "찜", "오징어", "새우", "낙지", "주꾸미", "쭈꾸미", "해물", "어묵", "크래미", "맛살", "아귀", "장어", "연어", "참치", "굴비", "문어", "한치", "바지락", "홍합", "미더덕", "꽃게", "갈치", "삼치", "조기", "동태", "명태", "코다리", "임연수", "꽁치", "가자미", "전어", "전복", "게맛살", "게장", "메추리", "스크램블", "에그", "소떡소떡"], [
    "단백질",
    "철분",
  ]],
  [["우유", "멸치", "치즈", "요구르트", "요거트", "요플레", "밀크", "연유", "버터", "미역", "다시마", "파래", "톳", "매생이", "청각", "꼬시래기", "해초", "곰피", "김자반", "돌김", "조미김", "김구이", "김부각", "잔멸치", "아몬드"], ["칼슘"]],
  [["밥", "면", "빵", "떡", "잡채", "국수", "짜장", "짬뽕", "우동", "스파게티", "파스타", "수제비", "카레", "오므라이스", "라이스", "죽", "누룽지", "샌드위치", "햄버거", "핫도그", "피자", "토스트", "머핀", "와플", "팬케이크", "또띠아", "부리토", "모닝빵", "식빵", "베이글", "크로와상", "감자", "고구마", "옥수수", "단호박", "시리얼", "츄러스", "떡볶이", "떡꼬치", "떡국", "라볶이", "만두", "교자", "딤섬", "케이크", "도넛", "붕어빵", "호떡", "카스테라", "푸딩", "젤리", "아이스크림", "샤베트", "핫케이크"], ["탄수화물"]],
  [["김치", "과일", "토마토", "귤", "사과", "배추", "깍두기", "총각", "동치미", "오이소박이", "젓갈", "장아찌", "피클", "할라피뇨", "배", "오렌지", "바나나", "딸기", "포도", "수박", "참외", "멜론", "파인애플", "키위", "망고", "방울토마토", "자두", "복숭아", "체리", "블루베리", "석류", "곶감", "푸룬", "건포도", "후르츠"], ["비타민"]],
  [["국", "탕", "찌개", "전골", "국밥", "수프", "스프", "미소", "사골", "육개장", "부대", "황태", "북어", "재첩", "도가니", "올갱이", "다슬기", "유부"], ["식이섬유", "비타민", "단백질"]],
  [["튀김", "까스", "카츠", "커틀릿", "강정", "프라이", "후라이", "가라아게", "텐푸라", "김말이", "전", "부침", "고로케", "크로켓", "꿔바로우"], ["단백질", "탄수화물"]],
  [["두부", "순두부", "연두부", "콩자반", "콩조림", "청국장", "비지", "완두", "강낭콩", "콩비지", "콩국", "콩잎", "렌틸", "병아리콩", "콩"], ["단백질", "칼슘"]],
];

export interface RawSchoolRow {
  SCHUL_NM: string;
  ATPT_OFCDC_SC_CODE: string;
  SD_SCHUL_CODE: string;
  LCTN_SC_NM: string;
  ORG_RDNMA: string;
  SCHUL_KND_SC_NM: string;
}

export interface RawMealRow {
  MLSV_YMD: string;
  DDISH_NM: string;
  CAL_INFO?: string;
  NTR_INFO?: string;
}

function estimateNutrients(name: string): string[] {
  return [
    ...new Set(
      NUTRIENT_RULES.flatMap(([keywords, nutrients]) =>
        keywords.some((keyword) => name.includes(keyword)) ? nutrients : []
      ),
    ),
  ];
}

function plainText(value: string): string {
  return value
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(
      /&#(\d+);|&#x([\da-f]+);|&([a-z][\da-z]+);/gi,
      (entity, decimal, hexadecimal, named) => {
        if (named) {
          return HTML_ENTITIES[named.toLowerCase()] ?? "";
        }

        const codePoint = Number.parseInt(
          decimal ?? hexadecimal,
          decimal ? 10 : 16,
        );
        return Number.isInteger(codePoint) && codePoint >= 0 &&
            codePoint <= 0x10ffff &&
            !(codePoint >= 0xd800 && codePoint <= 0xdfff)
          ? String.fromCodePoint(codePoint)
          : entity;
      },
    )
    .replace(/<[^>]*>/g, "")
    .replaceAll("\u00a0", " ")
    .trim();
}

interface ParsedMealItem extends Omit<MealItem, "id"> {
  contentKey: string;
}

function parseMealItemContent(raw: string): ParsedMealItem {
  const displayText = plainText(raw);
  const allergyCodes = [...displayText.matchAll(ALLERGY_ANNOTATION_PATTERN)]
    .flatMap((annotation) => annotation[1].match(/\d+/g) ?? [])
    .map(Number)
    .filter((value) => value >= 1 && value <= 19)
    .filter((value, position, values) => values.indexOf(value) === position)
    .sort((a, b) => a - b);
  const name = displayText
    .replace(/\((?:\s*\d{1,2}[.,)]?\s*)+\)/g, "")
    .replace(/^\d+\.\s*/, "")
    .replaceAll("*", "")
    .trim();

  return {
    contentKey: JSON.stringify([name, allergyCodes]),
    name,
    allergyCodes,
    nutrients: estimateNutrients(name),
    tags: [],
    sourceRawText: raw,
  };
}

function itemId(date: string, contentKey: string, occurrence: number): string {
  return `${date}:${encodeURIComponent(contentKey)}:${occurrence}`;
}

export function parseMealItem(
  raw: string,
  date: string,
  occurrence = 1,
): MealItem {
  const { contentKey, ...item } = parseMealItemContent(raw);
  return {
    id: itemId(date, contentKey, occurrence),
    ...item,
  };
}

function normalizeMenuItems(rawDishName: string, date: string): MealItem[] {
  const occurrences = new Map<string, number>();

  return rawDishName
    .split(/<br\s*\/?>/gi)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((raw) => {
      const parsed = parseMealItemContent(raw);
      const occurrence = (occurrences.get(parsed.contentKey) ?? 0) + 1;
      occurrences.set(parsed.contentKey, occurrence);
      const { contentKey, ...item } = parsed;
      return {
        id: itemId(date, contentKey, occurrence),
        ...item,
      };
    });
}

export function normalizeSchoolRows(rows: RawSchoolRow[]): School[] {
  return rows.flatMap((row) => {
    const schoolType = row.SCHUL_KND_SC_NM === "초등학교"
      ? "elementary"
      : row.SCHUL_KND_SC_NM === "중학교"
      ? "middle"
      : row.SCHUL_KND_SC_NM === "고등학교"
      ? "high"
      : null;
    return schoolType === null ? [] : [{
      name: row.SCHUL_NM.trim(),
      officeCode: row.ATPT_OFCDC_SC_CODE,
      schoolCode: row.SD_SCHUL_CODE,
      region: row.LCTN_SC_NM.trim(),
      address: row.ORG_RDNMA.trim(),
      schoolType,
    }];
  });
}

export function normalizeMealRows(rows: RawMealRow[]): MealDay[] {
  return rows.map((row) => ({
    date: row.MLSV_YMD,
    menuItems: normalizeMenuItems(row.DDISH_NM, row.MLSV_YMD),
    calorie: row.CAL_INFO?.trim() || null,
    nutrition: row.NTR_INFO ? plainText(row.NTR_INFO) : null,
    isSample: false,
    notice: null,
  }));
}
