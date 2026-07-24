import type { MealDay, MealItem, School } from '../_shared/neis-contract/index.ts';

const ALLERGY_PATTERN = /(?<!\d)([1-9]|1[0-9])(?=\.|\)|,|\s|$)/g;

const NUTRIENT_RULES: Array<[string[], string[]]> = [
  [['나물', '채소', '시금치', '브로콜리', '샐러드'], ['식이섬유', '비타민']],
  [['고기', '닭', '소고기', '돼지', '생선', '달걀', '두부', '콩'], ['단백질', '철분']],
  [['우유', '치즈', '요거트', '요구르트'], ['칼슘']],
  [['밥', '면', '빵', '감자', '고구마'], ['탄수화물']],
  [['김치', '과일', '사과', '배', '귤', '딸기', '포도'], ['비타민']],
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
  return [...new Set(NUTRIENT_RULES.flatMap(([keywords, nutrients]) =>
    keywords.some((keyword) => name.includes(keyword)) ? nutrients : []
  ))];
}

function plainText(value: string): string {
  return value
    .replace(/<br\s*\/?>/gi, '\n')
    .replaceAll('&amp;', '&')
    .trim();
}

export function parseMealItem(raw: string, index: number): MealItem {
  const allergyCodes = [...raw.matchAll(ALLERGY_PATTERN)]
    .map((match) => Number(match[1]))
    .filter((value, position, values) => values.indexOf(value) === position)
    .sort((a, b) => a - b);
  const name = raw
    .replace(/\((?:\s*\d{1,2}[.,)]?\s*)+\)/g, '')
    .replace(/^\d+\.\s*/, '')
    .replaceAll('*', '')
    .trim();

  return {
    id: `${index}-${name}`,
    name,
    allergyCodes,
    nutrients: estimateNutrients(name),
    tags: [],
    sourceRawText: raw,
  };
}

export function normalizeSchoolRows(rows: RawSchoolRow[]): School[] {
  return rows.flatMap((row) => {
    const schoolType = row.SCHUL_KND_SC_NM === '중학교'
      ? 'middle'
      : row.SCHUL_KND_SC_NM === '고등학교'
        ? 'high'
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

export function normalizeMealRows(rows: RawMealRow[], date: string): MealDay[] {
  return rows.map((row) => ({
    date,
    menuItems: plainText(row.DDISH_NM)
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean)
      .map(parseMealItem),
    calorie: row.CAL_INFO?.trim() || null,
    nutrition: row.NTR_INFO ? plainText(row.NTR_INFO) : null,
    isSample: false,
    notice: null,
  }));
}
