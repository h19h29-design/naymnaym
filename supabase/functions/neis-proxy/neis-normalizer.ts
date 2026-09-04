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
  [["나물", "채소", "시금치", "브로콜리", "샐러드"], ["식이섬유", "비타민"]],
  [["고기", "닭", "소고기", "돼지", "생선", "달걀", "두부", "콩"], [
    "단백질",
    "철분",
  ]],
  [["우유", "치즈", "요거트", "요구르트"], ["칼슘"]],
  [["밥", "면", "빵", "감자", "고구마"], ["탄수화물"]],
  [["김치", "과일", "사과", "배", "귤", "딸기", "포도"], ["비타민"]],
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
