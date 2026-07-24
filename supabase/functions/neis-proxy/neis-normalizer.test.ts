import { assertEquals } from 'jsr:@std/assert@1';
import { normalizeMealRows, normalizeSchoolRows } from './neis-normalizer.ts';

Deno.test('keeps only middle and high schools', () => {
  const rows = [
    {
      SCHUL_NM: '가람중학교',
      ATPT_OFCDC_SC_CODE: 'B10',
      SD_SCHUL_CODE: '7011234',
      LCTN_SC_NM: '서울특별시',
      ORG_RDNMA: '서울 중구 1',
      SCHUL_KND_SC_NM: '중학교',
    },
    {
      SCHUL_NM: '가람초등학교',
      ATPT_OFCDC_SC_CODE: 'B10',
      SD_SCHUL_CODE: '7015678',
      LCTN_SC_NM: '서울특별시',
      ORG_RDNMA: '서울 중구 2',
      SCHUL_KND_SC_NM: '초등학교',
    },
  ];

  assertEquals(
    normalizeSchoolRows(rows).map((school) => school.name),
    ['가람중학교'],
  );
});

Deno.test('parses allergens and nutrition hints without leaking raw markup', () => {
  const [meal] = normalizeMealRows([{
    MLSV_YMD: '20260724',
    DDISH_NM: '현미밥<br/>닭갈비(5.6.15.)<br/>배추김치(9.)',
    CAL_INFO: '812.3 Kcal',
    NTR_INFO: '탄수화물(g) : 112.0<br/>단백질(g) : 32.0',
  }], '20260724');

  assertEquals(meal.menuItems[1].name, '닭갈비');
  assertEquals(meal.menuItems[1].allergyCodes, [5, 6, 15]);
  assertEquals(meal.menuItems[1].nutrients.includes('단백질'), true);
  assertEquals(meal.isSample, false);
});
