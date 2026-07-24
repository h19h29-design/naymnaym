# Apps-in-Toss Zero-Cost MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved 냠냠레벨업 core experience as a review-ready Apps-in-Toss WebView mini-app while keeping hosting, user-data storage, and initial operation at zero cash cost.

**Architecture:** Add a standalone React/TypeScript WebView client under `apps-in-toss/`, persist all user state through Toss `Storage`, and call one narrowly scoped Supabase Edge Function that protects and normalizes the NEIS API. Keep live data, cached live data, no-meal states, errors, and an explicitly entered in-memory demo session separate.

**Tech Stack:** Apps-in-Toss Web Framework 2.x, React 18, TypeScript 5, Vite 7, Toss Design System Mobile, Vitest, Testing Library, Supabase Edge Functions, Deno 2, NEIS Open API.

## Global Constraints

- Preserve the existing iOS and Android apps; all new client work belongs under `apps-in-toss/`.
- Use the Apps-in-Toss WebView runtime, client-side routing, light mode, TDS components, and no duplicate custom navigation bar.
- Support only middle- and high-school students who can use Toss; do not add elementary-school or parent flows.
- Keep profile, school, allergies, records, XP, level, and cached meals on the device only.
- Do not use Supabase Database, Auth users, Storage, Realtime, paid functions, Toss login, payment, ads, promotion, smart messages, or push.
- Use one Supabase Edge Function only to protect the NEIS key, validate requests, normalize responses, and apply exact-origin CORS.
- Keep Supabase on the free plan with no automatic paid upgrade. If a free quota is exhausted, return a service-limited state and incur no charge.
- Never put `NEIS_API_KEY`, Supabase service-role keys, or user records into the client bundle, source control, response bodies, or logs.
- Never silently replace a failed live request with sample data. Demo mode starts only from an explicitly labeled user action and writes nothing to persistent progress.
- Keep the uncompressed `.ait` bundle below 100 MB and copy only the seven required growth images.
- Register one direct app feature route for `오늘 급식 기록` / `Meal record` at `/today`.
- Require sandbox and QR tests on both iOS and Android before review submission.
- Preserve unrelated worktree changes and stage only files named by the active task.

---

## File Structure

```text
.gitignore
apps-in-toss/
├── .env.example
├── README.md
├── granite.config.ts
├── index.html
├── package.json
├── package-lock.json
├── tsconfig.json
├── tsconfig.node.json
├── vite.config.ts
├── vitest.setup.ts
├── public/
│   └── growth/level-1.png ... level-7.png
├── scripts/
│   └── verify-release.mjs
└── src/
    ├── app/
    │   ├── App.tsx
    │   ├── App.test.tsx
    │   ├── AppProviders.tsx
    │   └── routes.tsx
    ├── components/
    │   ├── AppErrorState.tsx
    │   ├── GrowthHeader.tsx
    │   ├── MealCard.tsx
    │   └── MealFeedbackModal.tsx
    ├── config/
    │   ├── clientEnv.ts
    │   ├── env.ts
    │   └── env.test.ts
    ├── domain/
    │   ├── allergy.ts
    │   ├── allergy.test.ts
    │   ├── progress.ts
    │   ├── progress.test.ts
    │   ├── records.ts
    │   ├── records.test.ts
    │   └── types.ts
    ├── features/
    │   ├── onboarding/
    │   │   ├── OnboardingPage.tsx
    │   │   └── OnboardingPage.test.tsx
    │   ├── settings/
    │   │   ├── SettingsPage.tsx
    │   │   └── SettingsPage.test.tsx
    │   └── today/
    │       ├── demoMeal.ts
    │       ├── TodayPage.tsx
    │       ├── TodayPage.test.tsx
    │       └── useTodayMeal.ts
    ├── services/
    │   ├── neisClient.ts
    │   ├── neisClient.test.ts
    │   ├── repository.ts
    │   ├── repository.test.ts
    │   ├── storage.ts
    │   └── storage.test.ts
    ├── state/
    │   ├── AppStateProvider.tsx
    │   └── reducer.ts
    ├── styles/
    │   └── global.css
    ├── test/
    │   └── fixtures.ts
    └── main.tsx
supabase/functions/
├── _shared/neis-contract/
│   ├── index.ts
│   └── package.json
└── neis-proxy/
    ├── handler.test.ts
    ├── handler.ts
    ├── index.ts
    ├── neis-normalizer.test.ts
    └── neis-normalizer.ts
marketing-site/dist/
├── privacy.html
└── support.html
docs/
├── apps-in-toss-release-runbook.md
└── superpowers/plans/2026-07-24-apps-in-toss-zero-cost-mvp-implementation.md
```

The shared contract lives inside `supabase/functions/_shared/` so the Edge Function can deploy it, while `apps-in-toss/package.json` consumes the same source through a local `file:` dependency. This prevents client/server DTO drift without adding a package registry or hosted service.

---

### Task 1: Bootstrap the WebView Client and TDS Shell

**Files:**
- Modify: `.gitignore`
- Create: `apps-in-toss/.env.example`
- Create: `apps-in-toss/package.json`
- Create: `apps-in-toss/package-lock.json`
- Create: `apps-in-toss/tsconfig.json`
- Create: `apps-in-toss/tsconfig.node.json`
- Create: `apps-in-toss/vite.config.ts`
- Create: `apps-in-toss/vitest.setup.ts`
- Create: `apps-in-toss/index.html`
- Create: `apps-in-toss/granite.config.ts`
- Create: `apps-in-toss/src/config/env.ts`
- Create: `apps-in-toss/src/config/env.test.ts`
- Create: `apps-in-toss/src/app/AppProviders.tsx`
- Create: `apps-in-toss/src/app/App.tsx`
- Create: `apps-in-toss/src/main.tsx`
- Create: `apps-in-toss/src/styles/global.css`

**Interfaces:**
- Produces: a React 18 client wrapped in `TDSMobileAITProvider`.
- Produces: `requireEnv(name, env) -> string` for build-time configuration.
- Produces: Apps-in-Toss config with no permissions and partner WebView settings.
- Consumes later: `AppRoutes` from Task 6.

- [ ] **Step 1: Write the failing environment-contract test**

```ts
// apps-in-toss/src/config/env.test.ts
import { describe, expect, it } from 'vitest';
import { requireEnv } from './env';

describe('requireEnv', () => {
  it('returns a non-empty configured value', () => {
    expect(requireEnv('AIT_APP_NAME', { AIT_APP_NAME: 'nyam' })).toBe('nyam');
  });

  it('fails before a bundle can be built with missing console values', () => {
    expect(() => requireEnv('AIT_APP_NAME', { AIT_APP_NAME: '  ' }))
      .toThrow('Missing required environment variable: AIT_APP_NAME');
  });
});
```

- [ ] **Step 2: Create the package manifest and install the pinned toolchain**

```json
{
  "name": "nyam-apps-in-toss",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit",
    "build:web": "vite build",
    "build:ait": "ait build",
    "verify:release": "node scripts/verify-release.mjs"
  },
  "dependencies": {
    "@apps-in-toss/web-framework": "2.10.7",
    "@emotion/react": "11.14.0",
    "@toss/tds-mobile": "2.5.0",
    "@toss/tds-mobile-ait": "2.5.0",
    "react": "18.3.1",
    "react-dom": "18.3.1",
    "react-router-dom": "7.18.1"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "7.0.0",
    "@testing-library/react": "16.3.2",
    "@testing-library/user-event": "14.6.1",
    "@types/node": "22.20.1",
    "@types/react": "18.3.31",
    "@types/react-dom": "18.3.7",
    "@vitejs/plugin-react": "5.2.0",
    "dotenv": "17.4.2",
    "jsdom": "29.1.1",
    "typescript": "5.9.3",
    "vite": "7.3.6",
    "vitest": "4.1.10"
  }
}
```

Use the following compiler and test configuration:

```json
// apps-in-toss/tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowJs": false,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src", "vite.config.ts", "vitest.setup.ts"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

```json
// apps-in-toss/tsconfig.node.json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts", "granite.config.ts"]
}
```

```ts
// apps-in-toss/vite.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: './vitest.setup.ts',
    clearMocks: true,
  },
});
```

```ts
// apps-in-toss/vitest.setup.ts
import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

vi.stubEnv('VITE_NEIS_PROXY_URL', 'https://edge.test/neis-proxy');
vi.stubEnv('VITE_SUPABASE_ANON_KEY', 'public-test-anon-key');
```

Run:

```bash
cd apps-in-toss && npm install
```

Expected: `package-lock.json` is created and no paid service is provisioned.

- [ ] **Step 3: Run the focused test and verify RED**

```bash
cd apps-in-toss && npm test -- src/config/env.test.ts
```

Expected: the test fails because `src/config/env.ts` does not exist.

- [ ] **Step 4: Implement the environment guard and safe configuration files**

```ts
// apps-in-toss/src/config/env.ts
export function requireEnv(
  name: string,
  env: Record<string, string | undefined> = process.env,
): string {
  const value = env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}
```

```ts
// apps-in-toss/granite.config.ts
import 'dotenv/config';
import { defineConfig } from '@apps-in-toss/web-framework/config';
import { requireEnv } from './src/config/env';

export default defineConfig({
  appName: requireEnv('AIT_APP_NAME'),
  brand: {
    displayName: '냠냠레벨업',
    primaryColor: '#FF9F43',
    icon: requireEnv('AIT_ICON_URL'),
  },
  permissions: [],
  web: {
    host: 'localhost',
    port: 5173,
    commands: { dev: 'npm run dev', build: 'npm run build:web' },
  },
  outdir: 'dist',
  webViewProps: {
    type: 'partner',
    bounces: true,
    pullToRefreshEnabled: false,
    allowsBackForwardNavigationGestures: true,
  },
});
```

Commit `.env.example` with blank `AIT_APP_NAME`, `AIT_ICON_URL`, `VITE_NEIS_PROXY_URL`, and `VITE_SUPABASE_ANON_KEY` entries. Add `apps-in-toss/.env`, `apps-in-toss/dist/`, and `apps-in-toss/*.ait` to `.gitignore`; never commit actual configuration values or build artifacts.

- [ ] **Step 5: Add the TDS provider, viewport, and light-mode baseline**

```tsx
// apps-in-toss/src/app/AppProviders.tsx
import type { PropsWithChildren } from 'react';
import { TDSMobileAITProvider } from '@toss/tds-mobile-ait';

export function AppProviders({ children }: PropsWithChildren) {
  return <TDSMobileAITProvider>{children}</TDSMobileAITProvider>;
}
```

`index.html` must contain:

```html
<!doctype html>
<html lang="ko">
<head>
<meta charset="UTF-8" />
<meta
  name="viewport"
  content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
/>
<meta name="color-scheme" content="light" />
<title>냠냠레벨업</title>
</head>
<body>
<div id="root"></div>
<script type="module" src="/src/main.tsx"></script>
</body>
</html>
```

Use `Button` from `@toss/tds-mobile` in the initial `App` smoke screen so missing TDS wiring fails immediately.

```tsx
// apps-in-toss/src/app/App.tsx
import { Button } from '@toss/tds-mobile';

export function App() {
  return (
    <main className="app-shell">
      <h1>냠냠레벨업</h1>
      <p>오늘 급식을 한입씩 기록해요.</p>
      <Button onClick={() => undefined}>준비됐어요</Button>
    </main>
  );
}
```

```tsx
// apps-in-toss/src/main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './app/App';
import { AppProviders } from './app/AppProviders';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AppProviders>
      <App />
    </AppProviders>
  </StrictMode>,
);
```

```css
/* apps-in-toss/src/styles/global.css */
:root {
  color-scheme: light;
  font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo",
    "Noto Sans KR", sans-serif;
  background: #ffffff;
  color: #191f28;
}

* { box-sizing: border-box; }
body { margin: 0; background: #ffffff; }
button, input { font: inherit; }
.app-shell { min-height: 100dvh; padding: 24px 20px 40px; }
```

- [ ] **Step 6: Verify GREEN, typecheck, and commit**

```bash
cd apps-in-toss
npm test -- src/config/env.test.ts
npm run typecheck
npm run build:web
cd ..
git add .gitignore apps-in-toss
git commit -m "chore: bootstrap apps-in-toss client"
```

Expected: the focused test, typecheck, and web build pass without needing a hosted server.

---

### Task 2: Define the Shared NEIS Contract and Normalizer

**Files:**
- Create: `supabase/functions/_shared/neis-contract/package.json`
- Create: `supabase/functions/_shared/neis-contract/index.ts`
- Modify: `apps-in-toss/package.json`
- Modify: `apps-in-toss/package-lock.json`
- Create: `supabase/functions/neis-proxy/neis-normalizer.ts`
- Create: `supabase/functions/neis-proxy/neis-normalizer.test.ts`

**Interfaces:**
- Produces: `ProxyRequest`, `ApiResult<T>`, `School`, `MealDay`, `MealItem`, and `ProxyErrorCode`.
- Produces: `normalizeSchoolRows(rows)` and `normalizeMealRows(rows, date)`.
- Consumes: NEIS raw school and meal rows only inside the Edge Function.

- [ ] **Step 1: Define the single client/server DTO source**

```ts
// supabase/functions/_shared/neis-contract/index.ts
export type SchoolType = 'middle' | 'high';

export interface School {
  name: string;
  officeCode: string;
  schoolCode: string;
  region: string;
  address: string;
  schoolType: SchoolType;
}

export interface MealItem {
  id: string;
  name: string;
  allergyCodes: number[];
  nutrients: string[];
  tags: string[];
  sourceRawText: string;
}

export interface MealDay {
  date: string;
  menuItems: MealItem[];
  calorie: string | null;
  nutrition: string | null;
  isSample: boolean;
  notice: string | null;
}

export type ProxyRequest =
  | { action: 'searchSchools'; payload: { keyword: string } }
  | {
      action: 'fetchMeals';
      payload: { officeCode: string; schoolCode: string; date: string };
    };

export type ProxyErrorCode =
  | 'BAD_REQUEST'
  | 'FORBIDDEN_ORIGIN'
  | 'NO_DATA'
  | 'NOT_CONFIGURED'
  | 'RATE_LIMITED'
  | 'UPSTREAM_ERROR';

export type ApiResult<T> =
  | { ok: true; data: T }
  | { ok: false; code: ProxyErrorCode; message: string };
```

The package manifest must set `"name": "@nyam/neis-contract"`, `"type": "module"`, and `"exports": "./index.ts"`.

Add the shared source to the client dependencies only after this package exists:

```json
"@nyam/neis-contract": "file:../supabase/functions/_shared/neis-contract"
```

Then refresh the lockfile:

```bash
cd apps-in-toss && npm install
```

- [ ] **Step 2: Write failing Deno normalization tests**

```ts
// supabase/functions/neis-proxy/neis-normalizer.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { normalizeMealRows, normalizeSchoolRows } from './neis-normalizer.ts';

Deno.test('keeps only middle and high schools', () => {
  const rows = [
    { SCHUL_NM: '가람중학교', ATPT_OFCDC_SC_CODE: 'B10', SD_SCHUL_CODE: '7011234',
      LCTN_SC_NM: '서울특별시', ORG_RDNMA: '서울 중구 1', SCHUL_KND_SC_NM: '중학교' },
    { SCHUL_NM: '가람초등학교', ATPT_OFCDC_SC_CODE: 'B10', SD_SCHUL_CODE: '7015678',
      LCTN_SC_NM: '서울특별시', ORG_RDNMA: '서울 중구 2', SCHUL_KND_SC_NM: '초등학교' },
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
```

- [ ] **Step 3: Run the tests and verify RED**

```bash
npx --yes deno@2.9.4 test supabase/functions/neis-proxy/neis-normalizer.test.ts
```

Expected: import failure because `neis-normalizer.ts` does not exist.

- [ ] **Step 4: Implement parsing and keyword-based nutrition hints**

```ts
const ALLERGY_PATTERN = /(?<!\d)([1-9]|1[0-9])(?=\.|\)|,|\s|$)/g;

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
```

Complete the normalizer with these mappings and exported functions:

```ts
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
    keywords.some((keyword) => name.includes(keyword)) ? nutrients : []))];
}

function plainText(value: string): string {
  return value
    .replace(/<br\s*\/?>/gi, '\n')
    .replaceAll('&amp;', '&')
    .trim();
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
```

Export both raw interfaces only from this server normalizer; do not re-export them from the shared client contract.

- [ ] **Step 5: Verify GREEN and commit**

```bash
npx --yes deno@2.9.4 test supabase/functions/neis-proxy/neis-normalizer.test.ts
git add supabase/functions/_shared/neis-contract \
        supabase/functions/neis-proxy/neis-normalizer.ts \
        supabase/functions/neis-proxy/neis-normalizer.test.ts \
        apps-in-toss/package.json apps-in-toss/package-lock.json
git commit -m "feat: add shared NEIS response contract"
```

---

### Task 3: Build the Key-Protecting NEIS Edge Function

**Files:**
- Create: `supabase/functions/neis-proxy/handler.ts`
- Create: `supabase/functions/neis-proxy/handler.test.ts`
- Create: `supabase/functions/neis-proxy/index.ts`

**Interfaces:**
- Produces: `createHandler(deps) -> (request: Request) => Promise<Response>`.
- Accepts: only `POST` and allowed-origin `OPTIONS`, with a body no larger than 4096 bytes.
- Calls: only NEIS `schoolInfo` and `mealServiceDietInfo`.
- Returns: only the shared normalized `ApiResult<T>` contract.

- [ ] **Step 1: Write failing validation, CORS, and key-safety tests**

```ts
// supabase/functions/neis-proxy/handler.test.ts
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { createHandler } from './handler.ts';

const deps = {
  allowedOrigins: new Set(['https://sandbox.example']),
  neisApiKey: 'server-secret',
  fetch: async () => new Response(JSON.stringify({ schoolInfo: [{ head: [] }, { row: [] }] })),
};

Deno.test('rejects an unlisted browser origin', async () => {
  const response = await createHandler(deps)(new Request('https://edge.test', {
    method: 'POST',
    headers: { origin: 'https://evil.example' },
    body: JSON.stringify({ action: 'searchSchools', payload: { keyword: '가람' } }),
  }));
  assertEquals(response.status, 403);
});

Deno.test('rejects malformed meal identifiers before upstream fetch', async () => {
  let called = false;
  const response = await createHandler({ ...deps, fetch: async () => {
    called = true;
    return new Response();
  }})(new Request('https://edge.test', {
    method: 'POST',
    headers: { origin: 'https://sandbox.example' },
    body: JSON.stringify({
      action: 'fetchMeals',
      payload: { officeCode: 'bad', schoolCode: '1', date: '20261390' },
    }),
  }));
  assertEquals(response.status, 400);
  assertEquals(called, false);
});

Deno.test('never includes the NEIS key in an upstream failure', async () => {
  const response = await createHandler({ ...deps, fetch: async () => {
    throw new Error('upstream failed');
  }})(new Request('https://edge.test', {
    method: 'POST',
    headers: { origin: 'https://sandbox.example' },
    body: JSON.stringify({ action: 'searchSchools', payload: { keyword: '가람' } }),
  }));
  const text = await response.text();
  assertEquals(response.status, 502);
  assertEquals(text.includes('server-secret'), false);
  assertStringIncludes(text, 'UPSTREAM_ERROR');
});
```

- [ ] **Step 2: Run the focused Edge tests and verify RED**

```bash
npx --yes deno@2.9.4 test supabase/functions/neis-proxy/handler.test.ts
```

Expected: import failure because `handler.ts` does not exist.

- [ ] **Step 3: Implement exact request validation**

```ts
const OFFICE_CODE = /^[A-Z][0-9]{2}$/;
const SCHOOL_CODE = /^[0-9]{7}$/;
const DATE = /^[0-9]{8}$/;
const SCHOOL_KEYWORD = /^[가-힣A-Za-z0-9\s().-]{2,40}$/;

function isRealDate(value: string): boolean {
  if (!DATE.test(value)) return false;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(4, 6));
  const day = Number(value.slice(6, 8));
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  return actual.length === keys.length &&
    actual.every((key, index) => key === [...keys].sort()[index]);
}

function validateRequest(value: unknown): ProxyRequest | null {
  if (!isObject(value) || !hasOnlyKeys(value, ['action', 'payload']) ||
      !isObject(value.payload)) return null;
  if (value.action === 'searchSchools') {
    if (!hasOnlyKeys(value.payload, ['keyword'])) return null;
    const keyword = typeof value.payload.keyword === 'string'
      ? value.payload.keyword.trim()
      : '';
    return SCHOOL_KEYWORD.test(keyword)
      ? { action: 'searchSchools', payload: { keyword } }
      : null;
  }
  if (value.action === 'fetchMeals') {
    if (!hasOnlyKeys(value.payload, ['officeCode', 'schoolCode', 'date'])) return null;
    const { officeCode, schoolCode, date } = value.payload;
    return typeof officeCode === 'string' && OFFICE_CODE.test(officeCode) &&
        typeof schoolCode === 'string' && SCHOOL_CODE.test(schoolCode) &&
        typeof date === 'string' && isRealDate(date)
      ? { action: 'fetchMeals', payload: { officeCode, schoolCode, date } }
      : null;
  }
  return null;
}
```

This rejects unknown actions and fields, whitespace-only search, malformed IDs, impossible dates, and invalid JSON values without echoing input. The school normalizer from Task 2 removes elementary schools.

- [ ] **Step 4: Implement the two allowlisted upstream calls and safe responses**

```ts
interface HandlerDeps {
  allowedOrigins: Set<string>;
  neisApiKey: string;
  fetch: typeof fetch;
}

function json(origin: string, status: number, body: unknown): Response {
  const headers = new Headers({
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  if (origin) {
    headers.set('access-control-allow-origin', origin);
    headers.set('vary', 'Origin');
  }
  return new Response(JSON.stringify(body), {
    status,
    headers,
  });
}

function error(origin: string, status: number, code: ProxyErrorCode, message: string) {
  return json(origin, status, { ok: false, code, message });
}

function corsHeaders(origin: string): HeadersInit {
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'authorization, apikey, content-type',
    'access-control-max-age': '600',
    'vary': 'Origin',
  };
}

function neisUrl(request: ProxyRequest, apiKey: string): URL {
  const resource = request.action === 'searchSchools'
    ? 'schoolInfo'
    : 'mealServiceDietInfo';
  const url = new URL(`https://open.neis.go.kr/hub/${resource}`);
  url.searchParams.set('KEY', apiKey);
  url.searchParams.set('Type', 'json');
  url.searchParams.set('pIndex', '1');
  url.searchParams.set('pSize', request.action === 'searchSchools' ? '20' : '10');
  if (request.action === 'searchSchools') {
    url.searchParams.set('SCHUL_NM', request.payload.keyword);
  } else {
    url.searchParams.set('ATPT_OFCDC_SC_CODE', request.payload.officeCode);
    url.searchParams.set('SD_SCHUL_CODE', request.payload.schoolCode);
    url.searchParams.set('MLSV_YMD', request.payload.date);
  }
  return url;
}

function resultCode(value: unknown): string | null {
  if (!isObject(value) || !isObject(value.RESULT)) return null;
  return typeof value.RESULT.CODE === 'string' ? value.RESULT.CODE : null;
}

function rows(value: unknown, resource: string): unknown[] {
  if (!isObject(value)) return [];
  const group = value[resource];
  if (!Array.isArray(group) || !isObject(group[1]) || !Array.isArray(group[1].row)) {
    return [];
  }
  return group[1].row;
}

export function createHandler(deps: HandlerDeps) {
  return async (request: Request): Promise<Response> => {
    const started = performance.now();
    const requestId = crypto.randomUUID();
    const origin = request.headers.get('origin') ?? '';
    let action = 'unparsed';
    let status = 500;
    try {
      if (!deps.neisApiKey || deps.allowedOrigins.size === 0) {
        status = 503;
        return error('', status, 'NOT_CONFIGURED', '급식 조회가 준비되지 않았어요.');
      }
      if (!deps.allowedOrigins.has(origin)) {
        status = 403;
        return error('', status, 'FORBIDDEN_ORIGIN', '허용되지 않은 요청이에요.');
      }
      if (request.method === 'OPTIONS') {
        status = 204;
        return new Response(null, { status, headers: corsHeaders(origin) });
      }
      if (request.method !== 'POST') {
        status = 405;
        return error(origin, status, 'BAD_REQUEST', 'POST 요청만 사용할 수 있어요.');
      }
      const advertised = Number(request.headers.get('content-length') ?? '0');
      if (Number.isFinite(advertised) && advertised > 4096) {
        status = 413;
        return error(origin, status, 'BAD_REQUEST', '요청 크기가 너무 커요.');
      }
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > 4096) {
        status = 413;
        return error(origin, status, 'BAD_REQUEST', '요청 크기가 너무 커요.');
      }
      let decoded: unknown;
      try {
        decoded = JSON.parse(raw);
      } catch {
        status = 400;
        return error(origin, status, 'BAD_REQUEST', '요청 형식이 올바르지 않아요.');
      }
      const parsed = validateRequest(decoded);
      if (parsed === null) {
        status = 400;
        return error(origin, status, 'BAD_REQUEST', '요청 값이 올바르지 않아요.');
      }
      action = parsed.action;
      const upstream = await deps.fetch(neisUrl(parsed, deps.neisApiKey), {
        headers: { accept: 'application/json' },
      });
      if (upstream.status === 429) {
        status = 429;
        return error(origin, status, 'RATE_LIMITED', '요청이 많아요. 잠시 후 다시 시도해 주세요.');
      }
      if (!upstream.ok) {
        status = 502;
        return error(origin, status, 'UPSTREAM_ERROR', '급식 정보를 불러오지 못했어요.');
      }
      const upstreamJson: unknown = await upstream.json();
      const resource = parsed.action === 'searchSchools'
        ? 'schoolInfo'
        : 'mealServiceDietInfo';
      const upstreamRows = rows(upstreamJson, resource);
      const code = resultCode(upstreamJson);
      if (code === 'INFO-200' || upstreamRows.length === 0) {
        if (parsed.action === 'searchSchools') {
          status = 200;
          return json(origin, status, { ok: true, data: [] });
        }
        status = 404;
        return error(origin, status, 'NO_DATA', '오늘은 등록된 급식이 없어요.');
      }
      if (code !== null && code !== 'INFO-000') {
        status = 502;
        return error(origin, status, 'UPSTREAM_ERROR', '급식 정보를 불러오지 못했어요.');
      }
      const data = parsed.action === 'searchSchools'
        ? normalizeSchoolRows(upstreamRows as RawSchoolRow[])
        : normalizeMealRows(upstreamRows as RawMealRow[], parsed.payload.date)[0];
      status = 200;
      return json(origin, status, { ok: true, data });
    } catch {
      status = 502;
      return error(origin, status, 'UPSTREAM_ERROR', '급식 정보를 불러오지 못했어요.');
    } finally {
      console.info(JSON.stringify({
        requestId,
        action,
        status,
        durationMs: Math.round(performance.now() - started),
      }));
    }
  };
}
```

Import the shared request/error types plus `normalizeSchoolRows`, `normalizeMealRows`, `RawSchoolRow`, and `RawMealRow`. The handler logs only request ID, action, status, and duration—never payloads, query-string URLs, keys, upstream bodies, or authorization headers.

- [ ] **Step 5: Wire runtime secrets without service-role access**

```ts
// supabase/functions/neis-proxy/index.ts
import { createHandler } from './handler.ts';

const allowedOrigins = new Set(
  (Deno.env.get('NEIS_ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
);
const neisApiKey = Deno.env.get('NEIS_API_KEY') ?? '';

Deno.serve(createHandler({
  allowedOrigins,
  neisApiKey,
  fetch,
}));
```

When either secret is empty, return `NOT_CONFIGURED` with status 503. Keep Supabase JWT verification enabled at deployment; the public anon key may invoke the function, but no Auth user or session is created.

- [ ] **Step 6: Verify GREEN and commit**

```bash
npx --yes deno@2.9.4 fmt --check supabase/functions/neis-proxy supabase/functions/_shared/neis-contract
npx --yes deno@2.9.4 test supabase/functions/neis-proxy
git add supabase/functions/neis-proxy
git commit -m "feat: proxy NEIS through a guarded edge function"
```

---

### Task 4: Port Allergy Safety, Meal Records, and XP Rules

**Files:**
- Create: `apps-in-toss/src/domain/types.ts`
- Create: `apps-in-toss/src/domain/allergy.ts`
- Create: `apps-in-toss/src/domain/allergy.test.ts`
- Create: `apps-in-toss/src/domain/progress.ts`
- Create: `apps-in-toss/src/domain/progress.test.ts`
- Create: `apps-in-toss/src/domain/records.ts`
- Create: `apps-in-toss/src/domain/records.test.ts`
- Create: `apps-in-toss/src/test/fixtures.ts`

**Interfaces:**
- Produces: `EatingStatus`, `DifficultyReason`, `MealRecord`, `Profile`, and `Progress`.
- Produces: `allergyRisk(item: Pick<MealItem, 'allergyCodes'>, selectedCodes: number[]) -> number[]`.
- Produces: `calculateXp(input: XpInput) -> { base: number; challenge: number; total: number }`.
- Produces: `levelFor(totalXp: number) -> { number: number; threshold: number; title: string }`.
- Produces: idempotent `upsertMealRecord(records, nextRecord)`.

- [ ] **Step 1: Write failing allergy and XP tests**

```ts
import { makeRecord } from '../test/fixtures';

it('blocks one-bite when a selected allergen is present', () => {
  expect(allergyRisk({ allergyCodes: [5, 6, 15] }, [6, 9])).toEqual([6]);
});

it('applies retry XP and the base cap', () => {
  expect(calculateXp({
    status: 'oneBite',
    previousStatus: 'difficultToday',
    baseEarnedToday: 40,
    challengeEarnedToday: 0,
    variedFoodGroup: false,
    streakRecord: false,
    allergySafetyCheck: false,
  })).toEqual({ base: 10, challenge: 25, total: 35 });
});

it('applies challenge and combined daily caps after base XP', () => {
  expect(calculateXp({
    status: 'oneBite',
    previousStatus: null,
    baseEarnedToday: 40,
    challengeEarnedToday: 50,
    variedFoodGroup: true,
    streakRecord: true,
    allergySafetyCheck: true,
  })).toEqual({ base: 10, challenge: 0, total: 10 });
});

it('maps thresholds to the seven approved levels', () => {
  expect(levelFor(0).title).toBe('냠냠 새싹');
  expect(levelFor(180).title).toBe('냠냠 용사');
  expect(levelFor(1000).title).toBe('레전드 냠냠러');
});

it('recognizes only the immediately previous date as a streak', () => {
  expect(hasPreviousDayRecord([makeRecord({ date: '20260723' })], '20260724'))
    .toBe(true);
  expect(hasPreviousDayRecord([makeRecord({ date: '20260722' })], '20260724'))
    .toBe(false);
});
```

- [ ] **Step 2: Write the failing duplicate-record test**

```ts
it('updates the status but never awards duplicate XP for the same menu and date', () => {
  const first = makeRecord({ status: 'oneBite', awardedXp: 18 });
  const updated = upsertMealRecord([first], {
    ...first,
    status: 'finished',
    awardedXp: 10,
  });
  expect(updated.records).toHaveLength(1);
  expect(updated.records[0].status).toBe('finished');
  expect(updated.newXp).toBe(0);
});
```

- [ ] **Step 3: Run the domain tests and verify RED**

```bash
cd apps-in-toss
npm test -- src/domain
```

Expected: imports fail because the domain modules do not exist.

- [ ] **Step 4: Implement the approved rules as pure functions**

```ts
// apps-in-toss/src/domain/types.ts
import type { School } from '@nyam/neis-contract';

export type EatingStatus =
  | 'finished'
  | 'half'
  | 'oneBite'
  | 'smelledOnly'
  | 'difficultToday'
  | 'allergyAvoided';

export type DifficultyReason =
  | 'texture'
  | 'smell'
  | 'spicy'
  | 'color'
  | 'newFood'
  | 'allergy'
  | 'other';

export interface Profile {
  nickname: string;
  schoolType: 'middle' | 'high';
  school: School;
  allergyCodes: number[];
  createdAt: string;
}

export interface MealRecord {
  date: string;
  mealItemId: string;
  mealName: string;
  status: EatingStatus;
  difficultyReason: DifficultyReason | null;
  awardedXp: number;
  recordedAt: string;
}

export interface Progress {
  totalXp: number;
  baseEarnedByDate: Record<string, number>;
  challengeEarnedByDate: Record<string, number>;
}

export interface ChallengeRecord {
  date: string;
  mealItemId: string;
  kinds: Array<
    'variedFoodGroup' | 'streakRecord' | 'allergySafetyCheck' | 'retry'
  >;
  awardedXp: number;
}

export interface XpInput {
  status: EatingStatus;
  previousStatus: EatingStatus | null;
  baseEarnedToday: number;
  challengeEarnedToday: number;
  variedFoodGroup: boolean;
  streakRecord: boolean;
  allergySafetyCheck: boolean;
}

export interface XpAward {
  base: number;
  challenge: number;
  total: number;
}
```

Create shared test data with no personal information:

```ts
// apps-in-toss/src/test/fixtures.ts
import type { MealDay, School } from '@nyam/neis-contract';
import type { MealRecord, Profile } from '../domain/types';

export const school: School = {
  name: '가람중학교',
  officeCode: 'B10',
  schoolCode: '7011234',
  region: '서울특별시',
  address: '서울특별시 중구 테스트로 1',
  schoolType: 'middle',
};

export const meal: MealDay = {
  date: '20260724',
  menuItems: [{
    id: 'meal-1',
    name: '현미밥',
    allergyCodes: [],
    nutrients: ['탄수화물'],
    tags: [],
    sourceRawText: '현미밥',
  }],
  calorie: '812.3 Kcal',
  nutrition: '탄수화물(g) : 112.0',
  isSample: false,
  notice: null,
};

export function mealWithAllergen(code: number): MealDay {
  return {
    ...meal,
    menuItems: [{
      ...meal.menuItems[0],
      id: `allergen-${code}`,
      name: '알레르기 확인 메뉴',
      allergyCodes: [code],
    }],
  };
}

export function makeProfile(overrides: Partial<Profile> = {}): Profile {
  return {
    nickname: '냠냠이',
    schoolType: 'middle',
    school,
    allergyCodes: [],
    createdAt: '2026-07-24T00:00:00.000Z',
    ...overrides,
  };
}

export function makeRecord(overrides: Partial<MealRecord> = {}): MealRecord {
  return {
    date: '20260724',
    mealItemId: 'meal-1',
    mealName: '현미밥',
    status: 'oneBite',
    difficultyReason: null,
    awardedXp: 18,
    recordedAt: '2026-07-24T03:00:00.000Z',
    ...overrides,
  };
}
```

```ts
// apps-in-toss/src/domain/progress.ts
import type {
  EatingStatus,
  MealRecord,
  XpAward,
  XpInput,
} from './types';

const BASE_XP: Record<EatingStatus, number> = {
  finished: 10,
  half: 12,
  oneBite: 18,
  smelledOnly: 10,
  difficultToday: 3,
  allergyAvoided: 8,
};

const RETRY_XP: Record<EatingStatus, number> = {
  difficultToday: 5,
  smelledOnly: 10,
  oneBite: 25,
  half: 35,
  finished: 35,
  allergyAvoided: 0,
};

const LEVELS = [
  [0, '냠냠 새싹'],
  [80, '한 입 탐험가'],
  [180, '냠냠 용사'],
  [320, '편식 몬스터 사냥꾼'],
  [500, '급식 히어로'],
  [720, '영양 마스터'],
  [1000, '레전드 냠냠러'],
] as const;
```

Cap daily base XP at 50, challenge bonus at 70, and combined XP at 100. Award the capped base first, then use the remaining combined allowance for challenge XP:

```ts
export function calculateXp(input: XpInput): XpAward {
  const combinedBefore = input.baseEarnedToday + input.challengeEarnedToday;
  const combinedRoom = Math.max(0, 100 - combinedBefore);
  const base = Math.min(
    BASE_XP[input.status],
    Math.max(0, 50 - input.baseEarnedToday),
    combinedRoom,
  );
  const challengePotential =
    (input.previousStatus === 'difficultToday' ? RETRY_XP[input.status] : 0) +
    (input.variedFoodGroup ? 5 : 0) +
    (input.streakRecord ? 5 : 0) +
    (input.allergySafetyCheck ? 10 : 0);
  const challenge = Math.min(
    challengePotential,
    Math.max(0, 70 - input.challengeEarnedToday),
    Math.max(0, combinedRoom - base),
  );
  return { base, challenge, total: base + challenge };
}

export function levelFor(totalXp: number) {
  let index = 0;
  LEVELS.forEach(([threshold], candidate) => {
    if (totalXp >= threshold) index = candidate;
  });
  const [threshold, title] = LEVELS[index];
  return { number: index + 1, threshold, title };
}

export function hasPreviousDayRecord(records: MealRecord[], date: string): boolean {
  const current = new Date(Date.UTC(
    Number(date.slice(0, 4)),
    Number(date.slice(4, 6)) - 1,
    Number(date.slice(6, 8)),
  ));
  current.setUTCDate(current.getUTCDate() - 1);
  const previousDate = [
    current.getUTCFullYear(),
    String(current.getUTCMonth() + 1).padStart(2, '0'),
    String(current.getUTCDate()).padStart(2, '0'),
  ].join('');
  return records.some((record) => record.date === previousDate);
}
```

Apply retry XP only when the previous record was `difficultToday`.

Define all 19 allergy codes and Korean labels in one immutable map:

```ts
export const ALLERGIES = {
  1: '난류', 2: '우유', 3: '메밀', 4: '땅콩', 5: '대두',
  6: '밀', 7: '고등어', 8: '게', 9: '새우', 10: '돼지고기',
  11: '복숭아', 12: '토마토', 13: '아황산류', 14: '호두',
  15: '닭고기', 16: '쇠고기', 17: '오징어', 18: '조개류', 19: '잣',
} as const;
```

```ts
// apps-in-toss/src/domain/allergy.ts
import type { MealItem } from '@nyam/neis-contract';

export function allergyRisk(
  item: Pick<MealItem, 'allergyCodes'>,
  selectedCodes: number[],
): number[] {
  const selected = new Set(selectedCodes);
  return item.allergyCodes.filter((code) => selected.has(code));
}
```

```ts
// apps-in-toss/src/domain/records.ts
import type { MealRecord } from './types';

export function upsertMealRecord(
  records: MealRecord[],
  nextRecord: MealRecord,
): { records: MealRecord[]; newXp: number } {
  const index = records.findIndex((record) =>
    record.date === nextRecord.date &&
    record.mealItemId === nextRecord.mealItemId);
  if (index < 0) {
    return { records: [...records, nextRecord], newXp: nextRecord.awardedXp };
  }
  const updated = [...records];
  updated[index] = {
    ...nextRecord,
    awardedXp: records[index].awardedXp,
  };
  return { records: updated, newXp: 0 };
}
```

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd apps-in-toss
npm test -- src/domain
npm run typecheck
cd ..
git add apps-in-toss/src/domain apps-in-toss/src/test/fixtures.ts
git commit -m "feat: port meal safety and growth rules"
```

---

### Task 5: Add Versioned Toss Storage and Live-Meal Cache

**Files:**
- Create: `apps-in-toss/src/services/storage.ts`
- Create: `apps-in-toss/src/services/storage.test.ts`
- Create: `apps-in-toss/src/services/repository.ts`
- Create: `apps-in-toss/src/services/repository.test.ts`

**Interfaces:**
- Produces: `KeyValueStorage` adapter and `tossStorage`.
- Produces: `AppRepository.load()`, `saveProfile`, `saveProgress`, `saveRecords`, `cacheMeal`, and `deleteAll`.
- Produces: corrupt-data recovery and versioned keys.
- Consumes: `Storage` from `@apps-in-toss/web-framework`.

- [ ] **Step 1: Write failing persistence and corruption tests**

```ts
import type { KeyValueStorage } from './storage';
import { makeProfile } from '../test/fixtures';
import { AppRepository } from './repository';

class MemoryStorage implements KeyValueStorage {
  constructor(private values = new Map<string, string>()) {}
  async getItem(key: string) { return this.values.get(key) ?? null; }
  async setItem(key: string, value: string) { this.values.set(key, value); }
  async removeItem(key: string) { this.values.delete(key); }
  keys() { return [...this.values.keys()]; }
}

function seedAllKeys() {
  return new Map([
    ['nyam-toss:profile:v1', '{}'],
    ['nyam-toss:progress:v1', '{}'],
    ['nyam-toss:meal-records:v1', '[]'],
    ['nyam-toss:challenge-records:v1', '[]'],
    ['nyam-toss:meal-cache:v1', '[]'],
  ]);
}

it('round-trips a profile through the storage adapter', async () => {
  const storage = new MemoryStorage();
  const repository = new AppRepository(storage);
  await repository.saveProfile(makeProfile());
  expect((await repository.load()).profile?.nickname).toBe('냠냠이');
});

it('drops only a corrupt value and preserves other keys', async () => {
  const storage = new MemoryStorage(new Map([
    ['nyam-toss:profile:v1', '{broken'],
    ['nyam-toss:progress:v1', JSON.stringify({ totalXp: 80 })],
  ]));
  const state = await new AppRepository(storage).load();
  expect(state.profile).toBeNull();
  expect(state.progress.totalXp).toBe(80);
});

it('clears every nyam key when the user deletes local data', async () => {
  const storage = new MemoryStorage(seedAllKeys());
  await new AppRepository(storage).deleteAll();
  expect(storage.keys()).toEqual([]);
});
```

- [ ] **Step 2: Write failing cache-behavior tests**

```ts
import { beforeEach } from 'vitest';
import { meal, school } from '../test/fixtures';

let repository: AppRepository;
beforeEach(() => {
  repository = new AppRepository(new MemoryStorage());
});

it('returns a same-school same-date cached meal as cache data', async () => {
  await repository.cacheMeal(school, meal);
  expect(await repository.getCachedMeal(school, meal.date))
    .toEqual({ meal, source: 'cache' });
});

it('returns no cache entry for a school and date that never succeeded', async () => {
  expect(await repository.getCachedMeal(school, '20260724')).toBeNull();
});
```

- [ ] **Step 3: Run the storage tests and verify RED**

```bash
cd apps-in-toss
npm test -- src/services/storage.test.ts src/services/repository.test.ts
```

- [ ] **Step 4: Implement the adapter and versioned repository**

```ts
import { Storage } from '@apps-in-toss/web-framework';

export interface KeyValueStorage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

export const tossStorage: KeyValueStorage = {
  getItem: (key) => Storage.getItem(key),
  setItem: (key, value) => Storage.setItem(key, value),
  removeItem: (key) => Storage.removeItem(key),
};
```

Use exactly these keys:

```ts
const KEYS = {
  profile: 'nyam-toss:profile:v1',
  progress: 'nyam-toss:progress:v1',
  mealRecords: 'nyam-toss:meal-records:v1',
  challengeRecords: 'nyam-toss:challenge-records:v1',
  mealCache: 'nyam-toss:meal-cache:v1',
} as const;
```

Implement the repository with exact-school/date cache keys and recovery isolated per stored value:

```ts
// apps-in-toss/src/services/repository.ts
import type { MealDay, School } from '@nyam/neis-contract';
import type {
  ChallengeRecord,
  MealRecord,
  Profile,
  Progress,
} from '../domain/types';
import type { KeyValueStorage } from './storage';

const DEFAULT_PROGRESS: Progress = {
  totalXp: 0,
  baseEarnedByDate: {},
  challengeEarnedByDate: {},
};

interface MealCacheEntry {
  key: string;
  meal: MealDay;
  savedAt: string;
}

export interface RepositoryState {
  profile: Profile | null;
  progress: Progress;
  mealRecords: MealRecord[];
  challengeRecords: ChallengeRecord[];
}

export class AppRepository {
  constructor(private readonly storage: KeyValueStorage) {}

  private async read<T>(key: string, fallback: T): Promise<T> {
    const raw = await this.storage.getItem(key);
    if (raw === null) return fallback;
    try {
      return JSON.parse(raw) as T;
    } catch {
      await this.storage.removeItem(key);
      return fallback;
    }
  }

  private write(key: string, value: unknown): Promise<void> {
    return this.storage.setItem(key, JSON.stringify(value));
  }

  async load(): Promise<RepositoryState> {
    const storedProgress = await this.read<Partial<Progress>>(KEYS.progress, {});
    return {
      profile: await this.read<Profile | null>(KEYS.profile, null),
      progress: { ...DEFAULT_PROGRESS, ...storedProgress },
      mealRecords: await this.read<MealRecord[]>(KEYS.mealRecords, []),
      challengeRecords: await this.read<ChallengeRecord[]>(
        KEYS.challengeRecords,
        [],
      ),
    };
  }

  saveProfile(profile: Profile) { return this.write(KEYS.profile, profile); }
  saveProgress(progress: Progress) { return this.write(KEYS.progress, progress); }
  saveRecords(records: MealRecord[]) { return this.write(KEYS.mealRecords, records); }
  saveChallengeRecords(records: ChallengeRecord[]) {
    return this.write(KEYS.challengeRecords, records);
  }

  private cacheKey(school: School, date: string) {
    return `${school.officeCode}:${school.schoolCode}:${date}`;
  }

  async cacheMeal(school: School, meal: MealDay): Promise<void> {
    if (meal.isSample) return;
    const entries = await this.read<MealCacheEntry[]>(KEYS.mealCache, []);
    const key = this.cacheKey(school, meal.date);
    const next = [
      { key, meal, savedAt: new Date().toISOString() },
      ...entries.filter((entry) => entry.key !== key),
    ].slice(0, 14);
    await this.write(KEYS.mealCache, next);
  }

  async getCachedMeal(school: School, date: string) {
    const entries = await this.read<MealCacheEntry[]>(KEYS.mealCache, []);
    const entry = entries.find((candidate) =>
      candidate.key === this.cacheKey(school, date));
    return entry ? { meal: entry.meal, source: 'cache' as const } : null;
  }

  async deleteAll(): Promise<void> {
    await Promise.all(Object.values(KEYS).map((key) => this.storage.removeItem(key)));
  }
}
```

Do not expose a repository method that accepts or stores failed API results.

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd apps-in-toss
npm test -- src/services/storage.test.ts src/services/repository.test.ts
npm run typecheck
cd ..
git add apps-in-toss/src/services
git commit -m "feat: persist mini-app data in Toss storage"
```

---

### Task 6: Add the NEIS Client, App State, and Direct Routes

**Files:**
- Create: `apps-in-toss/src/services/neisClient.ts`
- Create: `apps-in-toss/src/services/neisClient.test.ts`
- Create: `apps-in-toss/src/config/clientEnv.ts`
- Modify: `apps-in-toss/src/domain/types.ts`
- Create: `apps-in-toss/src/state/reducer.ts`
- Create: `apps-in-toss/src/state/AppStateProvider.tsx`
- Create: `apps-in-toss/src/app/routes.tsx`
- Modify: `apps-in-toss/src/app/App.tsx`
- Create: `apps-in-toss/src/app/App.test.tsx`

**Interfaces:**
- Produces: `NeisClient.searchSchools(keyword: string, signal?: AbortSignal) -> Promise<School[]>`.
- Produces: `NeisClient.fetchMeal(school: School, date: string) -> Promise<MealDay>`.
- Produces: app bootstrap states `loading | ready | recoverableError`.
- Produces: routes `/`, `/onboarding`, `/today`, and `/settings`.
- Consumes: the shared `ApiResult<T>` contract and `AppRepository`.

- [ ] **Step 1: Write failing API boundary tests**

```ts
import type { ApiResult } from '@nyam/neis-contract';
import { school } from '../test/fixtures';

function makeClientReturning<T>(result: ApiResult<T>) {
  return new NeisClient({
    endpoint: 'https://edge.example/neis-proxy',
    anonKey: 'public-anon-key',
    fetch: async () => new Response(JSON.stringify(result), { status: result.ok ? 200 : 429 }),
  });
}

it('sends only the allowed action and anon authorization headers', async () => {
  const fetchSpy = vi.fn(async () =>
    new Response(JSON.stringify({ ok: true, data: [] }), { status: 200 }));
  const client = new NeisClient({
    endpoint: 'https://edge.example/neis-proxy',
    anonKey: 'public-anon-key',
    fetch: fetchSpy,
  });
  await client.searchSchools('가람');
  const [, init] = fetchSpy.mock.calls[0];
  expect(init?.headers).toMatchObject({
    apikey: 'public-anon-key',
    authorization: 'Bearer public-anon-key',
  });
  expect(JSON.parse(String(init?.body))).toEqual({
    action: 'searchSchools',
    payload: { keyword: '가람' },
  });
});

it('maps a stable edge error without entering demo mode', async () => {
  const client = makeClientReturning({
    ok: false, code: 'RATE_LIMITED', message: '잠시 후 다시 시도해 주세요.',
  });
  await expect(client.fetchMeal(school, '20260724'))
    .rejects.toMatchObject({ code: 'RATE_LIMITED' });
});
```

- [ ] **Step 2: Write failing route/bootstrap tests**

```tsx
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { makeProfile } from '../test/fixtures';
import { routeObjects } from './routes';

function renderTestApp({
  initialEntry,
  profile,
}: {
  initialEntry: string;
  profile: Profile | null;
}) {
  const router = createMemoryRouter(routeObjects(profile), {
    initialEntries: [initialEntry],
  });
  return render(<RouterProvider router={router} />);
}

it('redirects a first-time /today deep link to onboarding', async () => {
  renderTestApp({ initialEntry: '/today', profile: null });
  expect(await screen.findByRole('heading', { name: '냠냠레벨업 시작하기' }))
    .toBeInTheDocument();
});

it('opens /today directly for a configured user', async () => {
  renderTestApp({ initialEntry: '/today', profile: makeProfile() });
  expect(await screen.findByRole('heading', { name: '오늘 급식' }))
    .toBeInTheDocument();
});

it('allows the explicitly requested demo route without a profile', async () => {
  renderTestApp({ initialEntry: '/today?demo=1', profile: null });
  expect(await screen.findByRole('heading', { name: '오늘 급식' }))
    .toBeInTheDocument();
});
```

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
cd apps-in-toss
npm test -- src/services/neisClient.test.ts src/app/App.test.tsx
```

- [ ] **Step 4: Implement the typed client and explicit error class**

```ts
// apps-in-toss/src/services/neisClient.ts
import type {
  ApiResult,
  MealDay,
  ProxyErrorCode,
  ProxyRequest,
  School,
} from '@nyam/neis-contract';
import { clientEnv } from '../config/clientEnv';

interface NeisClientOptions {
  endpoint: string;
  anonKey: string;
  fetch?: typeof fetch;
}

export class NeisClientError extends Error {
  constructor(
    public readonly code: ProxyErrorCode,
    message: string,
    public readonly status: number,
  ) {
    super(message);
  }
}

export class NeisClient {
  private readonly fetchImpl: typeof fetch;

  constructor(private readonly options: NeisClientOptions) {
    this.fetchImpl = options.fetch ?? fetch;
  }

  searchSchools(keyword: string, signal?: AbortSignal): Promise<School[]> {
    return this.post({ action: 'searchSchools', payload: { keyword } }, signal);
  }

  fetchMeal(school: School, date: string): Promise<MealDay> {
    return this.post({
      action: 'fetchMeals',
      payload: {
        officeCode: school.officeCode,
        schoolCode: school.schoolCode,
        date,
      },
    });
  }

  private async post<T>(request: ProxyRequest, signal?: AbortSignal): Promise<T> {
    let response: Response;
    try {
      response = await this.fetchImpl(this.options.endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          apikey: this.options.anonKey,
          authorization: `Bearer ${this.options.anonKey}`,
        },
        body: JSON.stringify(request),
        signal,
      });
    } catch (caught) {
      if (caught instanceof DOMException && caught.name === 'AbortError') throw caught;
      throw new NeisClientError(
        'UPSTREAM_ERROR',
        '급식 정보를 불러오지 못했어요.',
        0,
      );
    }
    let result: ApiResult<T>;
    try {
      result = await response.json() as ApiResult<T>;
    } catch {
      throw this.unreadableResponse(response.status);
    }
    if (typeof result !== 'object' || result === null ||
        typeof result.ok !== 'boolean') {
      throw this.unreadableResponse(response.status);
    }
    if (!result.ok) {
      throw new NeisClientError(result.code, result.message, response.status);
    }
    if (!response.ok) {
      throw this.unreadableResponse(response.status);
    }
    return result.data;
  }

  private unreadableResponse(status: number) {
    const rateLimited = status === 429;
    return new NeisClientError(
      rateLimited ? 'RATE_LIMITED' : 'UPSTREAM_ERROR',
      rateLimited
        ? '요청이 많아요. 잠시 후 다시 시도해 주세요.'
        : '급식 정보를 불러오지 못했어요.',
      status,
    );
  }
}

export const neisClient = new NeisClient({
  endpoint: clientEnv.neisProxyUrl,
  anonKey: clientEnv.supabaseAnonKey,
});
```

Read `VITE_NEIS_PROXY_URL` and `VITE_SUPABASE_ANON_KEY` through this browser-only module. Never accept or reference a service-role key:

```ts
// apps-in-toss/src/config/clientEnv.ts
function required(name: string, value: string | undefined): string {
  const normalized = value?.trim();
  if (!normalized) throw new Error(`Missing required environment variable: ${name}`);
  return normalized;
}

export const clientEnv = {
  neisProxyUrl: required('VITE_NEIS_PROXY_URL', import.meta.env.VITE_NEIS_PROXY_URL),
  supabaseAnonKey: required(
    'VITE_SUPABASE_ANON_KEY',
    import.meta.env.VITE_SUPABASE_ANON_KEY,
  ),
} as const;
```

- [ ] **Step 5: Implement bootstrap and route behavior**

Implement repository bootstrap with an explicit reducer:

```ts
// apps-in-toss/src/state/reducer.ts
import type { RepositoryState } from '../services/repository';

export type AppState =
  | { status: 'loading' }
  | ({ status: 'ready' } & RepositoryState)
  | { status: 'recoverableError'; message: string };

export type AppAction =
  | { type: 'loaded'; value: RepositoryState }
  | { type: 'failed'; message: string }
  | { type: 'reset' };

export function reducer(_state: AppState, action: AppAction): AppState {
  if (action.type === 'loaded') return { status: 'ready', ...action.value };
  if (action.type === 'failed') {
    return { status: 'recoverableError', message: action.message };
  }
  return { status: 'loading' };
}
```

```tsx
// apps-in-toss/src/state/AppStateProvider.tsx
import {
  createContext,
  type Dispatch,
  type PropsWithChildren,
  useContext,
  useEffect,
  useReducer,
} from 'react';
import type { AppRepository } from '../services/repository';
import { reducer, type AppAction, type AppState } from './reducer';

interface AppStateValue {
  state: AppState;
  dispatch: Dispatch<AppAction>;
  repository: AppRepository;
  reload(): Promise<void>;
}

const Context = createContext<AppStateValue | null>(null);

export function AppStateProvider({
  repository,
  children,
}: PropsWithChildren<{ repository: AppRepository }>) {
  const [state, dispatch] = useReducer(reducer, { status: 'loading' });
  const reload = async () => {
    dispatch({ type: 'reset' });
    try {
      dispatch({ type: 'loaded', value: await repository.load() });
    } catch {
      dispatch({ type: 'failed', message: '저장된 정보를 불러오지 못했어요.' });
    }
  };
  useEffect(() => { void reload(); }, [repository]);
  return (
    <Context.Provider value={{ state, dispatch, repository, reload }}>
      {children}
    </Context.Provider>
  );
}

export function useAppState() {
  const value = useContext(Context);
  if (value === null) throw new Error('AppStateProvider is required');
  return value;
}
```

Use route objects so production can call `createBrowserRouter` and tests can call `createMemoryRouter`:

```tsx
// apps-in-toss/src/app/routes.tsx
import { Navigate, type RouteObject, useSearchParams } from 'react-router-dom';
import type { Profile } from '../domain/types';

const OnboardingPlaceholder = () => <h1>냠냠레벨업 시작하기</h1>;
const TodayPlaceholder = () => <h1>오늘 급식</h1>;
const SettingsPlaceholder = () => <h1>설정</h1>;

function TodayGate({ profile }: { profile: Profile | null }) {
  const [searchParams] = useSearchParams();
  const demo = searchParams.get('demo') === '1';
  return profile || demo
    ? <TodayPlaceholder />
    : <Navigate to="/onboarding?next=%2Ftoday" replace />;
}

export function routeObjects(profile: Profile | null): RouteObject[] {
  const onboarding = <OnboardingPlaceholder />;
  return [
    {
      path: '/',
      element: <Navigate to={profile ? '/today' : '/onboarding'} replace />,
    },
    { path: '/onboarding', element: onboarding },
    { path: '/today', element: <TodayGate profile={profile} /> },
    {
      path: '/settings',
      element: profile ? <SettingsPlaceholder /> : onboarding,
    },
    {
      path: '*',
      element: <Navigate to={profile ? '/today' : '/onboarding'} replace />,
    },
  ];
}
```

```tsx
// apps-in-toss/src/app/App.tsx
import { useMemo } from 'react';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { AppRepository } from '../services/repository';
import { tossStorage } from '../services/storage';
import { AppStateProvider, useAppState } from '../state/AppStateProvider';
import { routeObjects } from './routes';

const repository = new AppRepository(tossStorage);

function RoutedApp() {
  const { state } = useAppState();
  const profile = state.status === 'ready' ? state.profile : null;
  const router = useMemo(() => createBrowserRouter(routeObjects(profile)), [profile]);
  if (state.status === 'loading') return <p>불러오는 중...</p>;
  if (state.status === 'recoverableError') return <p>{state.message}</p>;
  return <RouterProvider router={router} />;
}

export function App() {
  return (
    <AppStateProvider repository={repository}>
      <RoutedApp />
    </AppStateProvider>
  );
}
```

A direct `/today` request without a profile redirects to `/onboarding?next=%2Ftoday`; Task 7 validates and consumes only internal `next` paths.

Keep demo state outside the persistent reducer by adding this type to `apps-in-toss/src/domain/types.ts`:

```ts
export type SessionMode = { kind: 'live' } | { kind: 'demo' };
```

Only `/today?demo=1` creates `{ kind: 'demo' }`; no network failure changes that value.

- [ ] **Step 6: Verify GREEN and commit**

```bash
cd apps-in-toss
npm test -- src/services/neisClient.test.ts src/app/App.test.tsx
npm run typecheck
cd ..
git add apps-in-toss/src/app apps-in-toss/src/services/neisClient* \
        apps-in-toss/src/state apps-in-toss/src/config/clientEnv.ts \
        apps-in-toss/src/domain/types.ts
git commit -m "feat: connect routes and NEIS client state"
```

---

### Task 7: Build Review-Safe Onboarding and School Search

**Files:**
- Create: `apps-in-toss/src/features/onboarding/OnboardingPage.tsx`
- Create: `apps-in-toss/src/features/onboarding/OnboardingPage.test.tsx`
- Modify: `apps-in-toss/src/app/routes.tsx`

**Interfaces:**
- Produces: nickname, `middle | high`, school, and allergy selection flow.
- Consumes: `NeisClient.searchSchools`, `ALLERGIES`, and `AppRepository.saveProfile`.
- Navigates: to the validated internal destination after save.

- [ ] **Step 1: Write failing first-run and validation tests**

```tsx
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { AppStateProvider } from '../../state/AppStateProvider';
import { neisClient } from '../../services/neisClient';
import type { AppRepository } from '../../services/repository';
import { school } from '../../test/fixtures';

const saveProfile = vi.fn(async () => undefined);
let user: ReturnType<typeof userEvent.setup>;

function renderOnboarding({
  searchSchools = vi.fn(async () => []),
}: {
  searchSchools?: typeof neisClient.searchSchools;
} = {}) {
  user = userEvent.setup();
  vi.spyOn(neisClient, 'searchSchools').mockImplementation(searchSchools);
  const repository = {
    load: async () => ({
      profile: null,
      progress: {
        totalXp: 0,
        baseEarnedByDate: {},
        challengeEarnedByDate: {},
      },
      mealRecords: [],
      challengeRecords: [],
    }),
    saveProfile,
  } as unknown as AppRepository;
  return render(
    <MemoryRouter>
      <AppStateProvider repository={repository}>
        <OnboardingPage />
      </AppStateProvider>
    </MemoryRouter>,
  );
}

it('requires a nickname, school, and supported school type', async () => {
  renderOnboarding();
  await user.click(screen.getByRole('button', { name: '시작하기' }));
  expect(screen.getByText('별명을 입력해 주세요.')).toBeInTheDocument();
  expect(screen.getByText('중학교 또는 고등학교를 선택해 주세요.')).toBeInTheDocument();
  expect(screen.getByText('학교를 선택해 주세요.')).toBeInTheDocument();
});

it('searches after two characters and saves the selected result', async () => {
  const searchSchools = vi.fn().mockResolvedValue([school]);
  renderOnboarding({ searchSchools });
  await user.type(screen.getByLabelText('별명'), '냠냠이');
  await user.click(screen.getByRole('radio', { name: '중학교' }));
  await user.type(screen.getByLabelText('학교 검색'), '가람');
  await user.click(await screen.findByRole('button', { name: /가람중학교/ }));
  await user.click(screen.getByRole('button', { name: '시작하기' }));
  expect(saveProfile).toHaveBeenCalledWith(expect.objectContaining({
    school,
    schoolType: 'middle',
  }));
});
```

- [ ] **Step 2: Run the page test and verify RED**

```bash
cd apps-in-toss
npm test -- src/features/onboarding/OnboardingPage.test.tsx
```

- [ ] **Step 3: Implement the TDS-first onboarding flow**

Use TDS `TextField`, `Button`, `Checkbox`, and typography, plus a semantic result list. Keep the first screen useful without an automatically opened bottom sheet. Debounce school search by 300 ms, require 2–40 valid characters, cancel stale searches with `AbortController`, and cap displayed results at 20.

Use this state and request effect in `OnboardingPage`:

```tsx
const [nickname, setNickname] = useState('');
const [schoolType, setSchoolType] = useState<'middle' | 'high' | null>(null);
const [keyword, setKeyword] = useState('');
const [schools, setSchools] = useState<School[]>([]);
const [selectedSchool, setSelectedSchool] = useState<School | null>(null);
const [allergyCodes, setAllergyCodes] = useState<number[]>([]);
const [errors, setErrors] = useState<string[]>([]);
const [demoConfirmOpen, setDemoConfirmOpen] = useState(false);
const { repository, reload } = useAppState();
const navigate = useNavigate();
const [searchParams] = useSearchParams();

useEffect(() => {
  const normalized = keyword.trim();
  if (normalized.length < 2) {
    setSchools([]);
    return;
  }
  const controller = new AbortController();
  const timer = window.setTimeout(() => {
    void neisClient.searchSchools(normalized, controller.signal)
      .then((results) => setSchools(
        results.filter((item) => schoolType === null || item.schoolType === schoolType)
          .slice(0, 20),
      ))
      .catch((caught: unknown) => {
        if (!(caught instanceof DOMException && caught.name === 'AbortError')) {
          setErrors(['학교를 검색하지 못했어요. 다시 시도해 주세요.']);
        }
      });
  }, 300);
  return () => {
    window.clearTimeout(timer);
    controller.abort();
  };
}, [keyword, schoolType]);

useEffect(() => {
  if (selectedSchool !== null && selectedSchool.schoolType !== schoolType) {
    setSelectedSchool(null);
  }
}, [schoolType, selectedSchool]);

async function submit() {
  const nextErrors = [
    ...(nickname.trim() ? [] : ['별명을 입력해 주세요.']),
    ...(schoolType ? [] : ['중학교 또는 고등학교를 선택해 주세요.']),
    ...(selectedSchool ? [] : ['학교를 선택해 주세요.']),
  ];
  setErrors(nextErrors);
  if (nextErrors.length > 0 || schoolType === null || selectedSchool === null) return;
  await repository.saveProfile({
    nickname: nickname.trim().slice(0, 12),
    schoolType,
    school: selectedSchool,
    allergyCodes,
    createdAt: new Date().toISOString(),
  });
  await reload();
  const requested = searchParams.get('next');
  const next = requested?.startsWith('/') && !requested.startsWith('//')
    ? requested
    : '/today';
  navigate(next, { replace: true });
}
```

Render the form with this component shape:

```tsx
return (
  <main className="app-shell">
    <h1>냠냠레벨업 시작하기</h1>
    <p>{copy.privacy}</p>
    <TextField
      variant="box"
      label="별명"
      labelOption="sustain"
      value={nickname}
      maxLength={12}
      onChange={(event) => setNickname(event.currentTarget.value)}
    />
    <fieldset>
      <legend>학교급</legend>
      {(['middle', 'high'] as const).map((value) => (
        <label key={value}>
          <Checkbox.Circle
            inputType="radio"
            name="schoolType"
            checked={schoolType === value}
            onCheckedChange={() => setSchoolType(value)}
          />
          {value === 'middle' ? '중학교' : '고등학교'}
        </label>
      ))}
    </fieldset>
    <TextField
      variant="box"
      label="학교 검색"
      labelOption="sustain"
      value={keyword}
      onChange={(event) => setKeyword(event.currentTarget.value)}
    />
    <ul aria-label="학교 검색 결과">
      {schools.map((item) => (
        <li key={`${item.officeCode}:${item.schoolCode}`}>
          <Button color="light" onClick={() => setSelectedSchool(item)}>
            {item.name} · {item.region}
          </Button>
        </li>
      ))}
    </ul>
    <fieldset>
      <legend>알레르기</legend>
      {Object.entries(ALLERGIES).map(([code, label]) => (
        <label key={code}>
          <Checkbox.Line
            checked={allergyCodes.includes(Number(code))}
            onCheckedChange={(checked) => setAllergyCodes((current) =>
              checked
                ? [...current, Number(code)]
                : current.filter((item) => item !== Number(code)))}
          />
          {label}
        </label>
      ))}
      <label>
        <Checkbox.Line
          checked={allergyCodes.length === 0}
          onCheckedChange={(checked) => {
            if (checked) setAllergyCodes([]);
          }}
        />
        해당 없음
      </label>
    </fieldset>
    {errors.map((message) => <p role="alert" key={message}>{message}</p>)}
    <Button onClick={() => void submit()}>시작하기</Button>
    <Button color="light" onClick={() => setDemoConfirmOpen(true)}>
      {copy.demo}
    </Button>
    <Modal open={demoConfirmOpen} onOpenChange={setDemoConfirmOpen}>
      <Modal.Overlay onClick={() => setDemoConfirmOpen(false)} />
      <Modal.Content aria-label="체험 모드 안내">
        <h2>체험해 볼까요?</h2>
        <p>체험 기록은 저장되지 않고 실제 성장에 반영되지 않아요.</p>
        <Button onClick={() => navigate('/today?demo=1')}>체험 시작</Button>
      </Modal.Content>
    </Modal>
  </main>
);
```

Use the following visible copy:

```ts
const copy = {
  title: '냠냠레벨업 시작하기',
  privacy: '별명, 학교, 알레르기와 기록은 이 기기에만 저장돼요.',
  demo: '학교 없이 체험해 보기',
  noResults: '검색 결과가 없어요. 학교 이름을 다시 확인해 주세요.',
};
```

Show all 19 allergy choices with “해당 없음”. Selecting “해당 없음” clears codes; selecting a code clears “해당 없음”. Do not collect birth date, phone number, gender, real name, parent information, or Toss account data.

- [ ] **Step 4: Add the explicit demo entry**

The `학교 없이 체험해 보기` button navigates to `/today?demo=1` without saving a profile. Its confirmation copy must state: `체험 기록은 저장되지 않고 실제 성장에 반영되지 않아요.`

Replace `OnboardingPlaceholder` in `apps-in-toss/src/app/routes.tsx` with:

```tsx
import { OnboardingPage } from '../features/onboarding/OnboardingPage';

const onboarding = <OnboardingPage />;
```

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd apps-in-toss
npm test -- src/features/onboarding/OnboardingPage.test.tsx
npm run typecheck
cd ..
git add apps-in-toss/src/features/onboarding apps-in-toss/src/app/routes.tsx
git commit -m "feat: add local-only Toss onboarding"
```

---

### Task 8: Build Today’s Meal, Safety Feedback, Demo, and Growth UI

**Files:**
- Create: `apps-in-toss/src/features/today/demoMeal.ts`
- Copy: `NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_1.imageset/Squirrel_Growth_Level_1.png` to `apps-in-toss/public/growth/level-1.png`
- Copy: corresponding non-empty level 2–7 PNGs to `apps-in-toss/public/growth/level-2.png` through `level-7.png`
- Create: `apps-in-toss/src/components/GrowthHeader.tsx`
- Create: `apps-in-toss/src/components/MealCard.tsx`
- Create: `apps-in-toss/src/components/MealFeedbackModal.tsx`
- Create: `apps-in-toss/src/components/AppErrorState.tsx`
- Create: `apps-in-toss/src/features/today/useTodayMeal.ts`
- Create: `apps-in-toss/src/features/today/TodayPage.tsx`
- Create: `apps-in-toss/src/features/today/TodayPage.test.tsx`
- Modify: `apps-in-toss/src/app/routes.tsx`

**Interfaces:**
- Produces: five distinct states: `live`, `cache`, `noMeal`, `error`, and `demo`.
- Produces: three primary actions: `한입도전`, `잘먹어요`, and `못먹겠어요`.
- Produces: user-triggered difficulty modal and allergy-safe alternative.
- Consumes: `calculateXp`, `upsertMealRecord`, `AppRepository`, and seven growth images.

- [ ] **Step 1: Write failing data-source and demo isolation tests**

```tsx
it('labels cached live data and does not call it sample data', async () => {
  renderToday({ mealResult: { kind: 'cache', meal } });
  expect(await screen.findByText('저장된 급식 정보예요')).toBeInTheDocument();
  expect(screen.queryByText(/체험/)).not.toBeInTheDocument();
});

it('shows an error instead of silently replacing live data with demo data', async () => {
  renderToday({ mealResult: { kind: 'error', code: 'UPSTREAM_ERROR' } });
  expect(await screen.findByText('급식 정보를 불러오지 못했어요')).toBeInTheDocument();
  expect(screen.queryByText('체험 급식')).not.toBeInTheDocument();
});

it('never persists a demo meal record or XP', async () => {
  renderToday({ route: '/today?demo=1' });
  await user.click(await screen.findByRole('button', { name: '한입도전' }));
  expect(saveRecords).not.toHaveBeenCalled();
  expect(saveProgress).not.toHaveBeenCalled();
  expect(screen.getByText('체험 기록은 저장되지 않아요')).toBeInTheDocument();
});
```

- [ ] **Step 2: Write failing allergy and detailed-feedback tests**

```tsx
it('replaces one-bite with allergy avoidance for a risky item', async () => {
  renderToday({ allergies: [6], meal: mealWithAllergen(6) });
  expect(await screen.findByRole('button', { name: '알레르기 때문에 피했어요' }))
    .toBeInTheDocument();
  expect(screen.queryByRole('button', { name: '한입도전' }))
    .not.toBeInTheDocument();
});

it('opens difficulty reasons only after the user asks', async () => {
  renderToday({ meal });
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  await user.click(await screen.findByRole('button', { name: '못먹겠어요' }));
  expect(screen.getByRole('dialog', { name: '어떤 점이 어려웠나요?' }))
    .toBeInTheDocument();
});
```

- [ ] **Step 3: Run the page test and verify RED**

```bash
cd apps-in-toss
npm test -- src/features/today/TodayPage.test.tsx
```

- [ ] **Step 4: Implement live/cache/no-meal/error loading**

Use this bundled demo fixture so its source and label are unambiguous:

```ts
// apps-in-toss/src/features/today/demoMeal.ts
import type { MealDay } from '@nyam/neis-contract';
import { useEffect, useState } from 'react';

export const demoMeal = {
  "date": "20260724",
  "menuItems": [
    {
      "id": "demo-1",
      "name": "현미밥",
      "allergyCodes": [],
      "nutrients": ["탄수화물"],
      "tags": ["체험"],
      "sourceRawText": "현미밥"
    },
    {
      "id": "demo-2",
      "name": "닭갈비",
      "allergyCodes": [5, 6, 15],
      "nutrients": ["단백질", "철분"],
      "tags": ["체험"],
      "sourceRawText": "닭갈비(5.6.15.)"
    }
  ],
  "calorie": "체험 데이터",
  "nutrition": null,
  "isSample": true,
  "notice": "체험 급식은 실제 학교 급식이 아니며 기록과 XP가 저장되지 않아요."
} satisfies MealDay;
```

`useTodayMeal` must:

1. Use bundled demo JSON only when `sessionMode.kind === 'demo'`.
2. Request today in Seoul as `YYYYMMDD` for a configured live profile.
3. Save successful live results to cache and return `{ kind: 'live', meal }`.
4. On `NO_DATA`, return `{ kind: 'noMeal' }`.
5. On network, quota, configuration, or upstream errors, try only the exact school/date cache and return `{ kind: 'cache', meal }` if present.
6. Otherwise return `{ kind: 'error', code }`.

Use visible, non-interchangeable labels: `오늘 급식`, `저장된 급식 정보예요`, `오늘은 등록된 급식이 없어요`, `급식 정보를 불러오지 못했어요`, and `체험 급식`.

Map recoverable errors without exposing infrastructure details:

```tsx
// apps-in-toss/src/components/AppErrorState.tsx
import { Button } from '@toss/tds-mobile';

const ERROR_COPY: Record<string, string> = {
  RATE_LIMITED: '요청이 많아 잠시 이용하기 어려워요. 조금 뒤 다시 시도해 주세요.',
  NOT_CONFIGURED: '급식 조회 준비 중이에요. 문의 및 지원에서 알려 주세요.',
  UPSTREAM_ERROR: '급식 정보를 불러오지 못했어요. 네트워크를 확인해 주세요.',
  PROFILE_REQUIRED: '먼저 학교를 설정해 주세요.',
};

export function AppErrorState({
  code,
  retry,
}: {
  code: string;
  retry(): void;
}) {
  return (
    <section role="alert">
      <h2>급식 정보를 불러오지 못했어요</h2>
      <p>{ERROR_COPY[code] ?? ERROR_COPY.UPSTREAM_ERROR}</p>
      <Button onClick={retry}>다시 시도</Button>
    </section>
  );
}
```

Implement the transition as a pure async function used by the hook:

```ts
// apps-in-toss/src/features/today/useTodayMeal.ts
import type { MealDay } from '@nyam/neis-contract';
import type { Profile, SessionMode } from '../../domain/types';
import { NeisClientError, type NeisClient } from '../../services/neisClient';
import type { AppRepository } from '../../services/repository';
import { demoMeal } from './demoMeal';

export type TodayMealResult =
  | { kind: 'live'; meal: MealDay }
  | { kind: 'cache'; meal: MealDay }
  | { kind: 'demo'; meal: MealDay }
  | { kind: 'noMeal' }
  | { kind: 'error'; code: string };

export function seoulDate(now = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
  return parts.replaceAll('-', '');
}

export async function loadTodayMeal(input: {
  mode: SessionMode;
  profile: Profile | null;
  client: NeisClient;
  repository: AppRepository;
  now?: Date;
}): Promise<TodayMealResult> {
  if (input.mode.kind === 'demo') return { kind: 'demo', meal: demoMeal };
  if (input.profile === null) return { kind: 'error', code: 'PROFILE_REQUIRED' };
  const date = seoulDate(input.now);
  try {
    const meal = await input.client.fetchMeal(input.profile.school, date);
    await input.repository.cacheMeal(input.profile.school, meal);
    return { kind: 'live', meal };
  } catch (caught) {
    if (caught instanceof NeisClientError && caught.code === 'NO_DATA') {
      return { kind: 'noMeal' };
    }
    const cached = await input.repository.getCachedMeal(input.profile.school, date);
    if (cached !== null) return { kind: 'cache', meal: cached.meal };
    return {
      kind: 'error',
      code: caught instanceof NeisClientError ? caught.code : 'UPSTREAM_ERROR',
    };
  }
}

export function useTodayMeal(input: Omit<Parameters<typeof loadTodayMeal>[0], 'now'>) {
  const [result, setResult] = useState<'loading' | TodayMealResult>('loading');
  const [attempt, setAttempt] = useState(0);
  const date = seoulDate();
  useEffect(() => {
    let active = true;
    setResult('loading');
    void loadTodayMeal(input).then((next) => {
      if (active) setResult(next);
    });
    return () => { active = false; };
  }, [
    input.mode.kind,
    input.profile?.school.officeCode,
    input.profile?.school.schoolCode,
    input.client,
    input.repository,
    date,
    attempt,
  ]);
  return { result, retry: () => setAttempt((value) => value + 1) };
}
```

This exposes `{ result: 'loading' | TodayMealResult, retry() }` and reruns only when school, Seoul date, client/repository instance, session mode, or a user retry changes.

- [ ] **Step 5: Implement meal feedback and allergy safety**

For a safe menu item, show TDS buttons for `한입도전`, `잘먹어요`, and `못먹겠어요`. Map them to `oneBite`, `finished`, and a user-triggered TDS modal. The modal offers `식감`, `냄새`, `매움`, `색`, `새로운 음식`, `알레르기`, and `기타`, then lets the user record `냄새만 맡았어요`, `절반 먹었어요`, or `오늘은 어려웠어요`.

Build `TodayPage` around the discriminated result so each source has one visible branch:

```tsx
export function TodayPage() {
  const [searchParams] = useSearchParams();
  const sessionMode: SessionMode = searchParams.get('demo') === '1'
    ? { kind: 'demo' }
    : { kind: 'live' };
  const { state, repository, reload } = useAppState();
  const profile = state.status === 'ready' ? state.profile : null;
  const persistentProgress =
    state.status === 'ready' ? state.progress : DEFAULT_PROGRESS;
  const persistentRecords = state.status === 'ready' ? state.mealRecords : [];
  const challengeRecords = state.status === 'ready' ? state.challengeRecords : [];
  const [demoRecords, setDemoRecords] = useState<MealRecord[]>([]);
  const [demoProgress, setDemoProgress] = useState<Progress>(DEFAULT_PROGRESS);
  const [demoNotice, setDemoNotice] = useState<string | null>(null);
  const records = sessionMode.kind === 'demo' ? demoRecords : persistentRecords;
  const progress = sessionMode.kind === 'demo' ? demoProgress : persistentProgress;
  const { result, retry } = useTodayMeal({
    mode: sessionMode,
    profile,
    client: neisClient,
    repository,
  });

  if (result === 'loading') return <main className="app-shell">불러오는 중...</main>;
  if (result.kind === 'noMeal') {
    return <main className="app-shell"><h1>오늘 급식</h1><p>오늘은 등록된 급식이 없어요</p></main>;
  }
  if (result.kind === 'error') {
    return <main className="app-shell"><AppErrorState code={result.code} retry={retry} /></main>;
  }

  const sourceLabel = {
    live: '오늘 급식',
    cache: '저장된 급식 정보예요',
    demo: '체험 급식',
  }[result.kind];
  const meal = result.meal;
  return (
    <main className="app-shell">
      <GrowthHeader totalXp={progress.totalXp} />
      <h1>{sourceLabel}</h1>
      {result.kind === 'demo' && <p>체험 기록은 저장되지 않아요</p>}
      {demoNotice && <p role="status">{demoNotice}</p>}
      {meal.menuItems.map((item) => (
        <MealCard
          key={item.id}
          item={item}
          allergyCodes={profile?.allergyCodes ?? []}
          onRecord={(status, reason) => void record(item, status, reason)}
        />
      ))}
    </main>
  );
}
```

Define the local fallback and demo-only state as:

```tsx
const DEFAULT_PROGRESS: Progress = {
  totalXp: 0,
  baseEarnedByDate: {},
  challengeEarnedByDate: {},
};

```

`MealCard` shows menu name, nutrition hints, allergen names, and the three actions; it swaps `한입도전` for the safety action whenever `allergyRisk` returns a non-empty array.

Use one guarded record function for buttons and modal choices:

```ts
async function record(
  item: MealItem,
  status: EatingStatus,
  difficultyReason: DifficultyReason | null = null,
) {
  if (status === 'oneBite' && allergyRisk(item, profile?.allergyCodes ?? []).length > 0) {
    throw new Error('Allergy-risk items cannot be recorded as oneBite');
  }
  const previous = records
    .filter((candidate) =>
      candidate.mealName === item.name && candidate.date < meal.date)
    .sort((left, right) => left.date.localeCompare(right.date))
    .at(-1);
  const variedFoodGroup = item.nutrients.length >= 2;
  const streakRecord = hasPreviousDayRecord(records, meal.date);
  const allergySafetyCheck = status === 'allergyAvoided';
  const retry = previous?.status === 'difficultToday';
  const award = calculateXp({
    status,
    previousStatus: previous?.status ?? null,
    baseEarnedToday: progress.baseEarnedByDate[meal.date] ?? 0,
    challengeEarnedToday: progress.challengeEarnedByDate[meal.date] ?? 0,
    variedFoodGroup,
    streakRecord,
    allergySafetyCheck,
  });
  const next: MealRecord = {
    date: meal.date,
    mealItemId: item.id,
    mealName: item.name,
    status,
    difficultyReason,
    awardedXp: award.total,
    recordedAt: new Date().toISOString(),
  };
  const updated = upsertMealRecord(records, next);
  if (sessionMode.kind === 'demo') {
    setDemoRecords(updated.records);
    if (updated.newXp > 0) {
      setDemoProgress({
        totalXp: progress.totalXp + updated.newXp,
        baseEarnedByDate: {
          ...progress.baseEarnedByDate,
          [meal.date]: (progress.baseEarnedByDate[meal.date] ?? 0) + award.base,
        },
        challengeEarnedByDate: {
          ...progress.challengeEarnedByDate,
          [meal.date]:
            (progress.challengeEarnedByDate[meal.date] ?? 0) + award.challenge,
        },
      });
    }
    setDemoNotice('체험 기록은 저장되지 않아요');
    return;
  }
  await repository.saveRecords(updated.records);
  if (updated.newXp > 0) {
    await repository.saveProgress({
      totalXp: progress.totalXp + updated.newXp,
      baseEarnedByDate: {
        ...progress.baseEarnedByDate,
        [meal.date]: (progress.baseEarnedByDate[meal.date] ?? 0) + award.base,
      },
      challengeEarnedByDate: {
        ...progress.challengeEarnedByDate,
        [meal.date]:
          (progress.challengeEarnedByDate[meal.date] ?? 0) + award.challenge,
      },
    });
    if (award.challenge > 0) {
      await repository.saveChallengeRecords([
        ...challengeRecords,
        {
          date: meal.date,
          mealItemId: item.id,
          kinds: [
            ...(variedFoodGroup ? ['variedFoodGroup' as const] : []),
            ...(streakRecord ? ['streakRecord' as const] : []),
            ...(allergySafetyCheck ? ['allergySafetyCheck' as const] : []),
            ...(retry ? ['retry' as const] : []),
          ],
          awardedXp: award.challenge,
        },
      ]);
    }
  }
  await reload();
}
```

Render the detailed choice only inside a user-opened TDS modal:

```tsx
<Modal open={difficultyOpen} onOpenChange={setDifficultyOpen}>
  <Modal.Overlay onClick={() => setDifficultyOpen(false)} />
  <Modal.Content role="dialog" aria-label="어떤 점이 어려웠나요?">
    <h2>어떤 점이 어려웠나요?</h2>
    {([
      ['texture', '식감'],
      ['smell', '냄새'],
      ['spicy', '매움'],
      ['color', '색'],
      ['newFood', '새로운 음식'],
      ['allergy', '알레르기'],
      ['other', '기타'],
    ] as const).map(([value, label]) => (
      <Button key={value} color="light" onClick={() => setReason(value)}>
        {label}
      </Button>
    ))}
    <Button onClick={() => void record(item, 'smelledOnly', reason)}>
      냄새만 맡았어요
    </Button>
    <Button onClick={() => void record(item, 'half', reason)}>
      절반 먹었어요
    </Button>
    <Button color="light" onClick={() => void record(item, 'difficultToday', reason)}>
      오늘은 어려웠어요
    </Button>
  </Modal.Content>
</Modal>
```

For an allergy-risk item:

```tsx
<Button
  color="danger"
  onClick={() => record('allergyAvoided')}
>
  알레르기 때문에 피했어요
</Button>
```

Show the matching allergen names before the button. Never offer `oneBite` for that item.

- [ ] **Step 6: Implement growth feedback using only existing PNG assets**

```tsx
export function GrowthHeader({ totalXp }: { totalXp: number }) {
  const level = levelFor(totalXp);
  return (
    <section aria-label="성장 현황">
      <img src={`/growth/level-${level.number}.png`} alt={`${level.title} 캐릭터`} />
      <strong>Lv.{level.number} {level.title}</strong>
      <span>{totalXp} XP</span>
    </section>
  );
}
```

Use a short CSS opacity/scale transition after XP changes and respect `prefers-reduced-motion`. Do not add Lottie or another runtime dependency for the MVP.

Replace `TodayPlaceholder` in `apps-in-toss/src/app/routes.tsx` with the actual page:

```tsx
import { TodayPage } from '../features/today/TodayPage';

function TodayGate({ profile }: { profile: Profile | null }) {
  const [searchParams] = useSearchParams();
  return profile || searchParams.get('demo') === '1'
    ? <TodayPage />
    : <Navigate to="/onboarding?next=%2Ftoday" replace />;
}
```

- [ ] **Step 7: Verify GREEN and commit**

```bash
cd apps-in-toss
npm test -- src/features/today/TodayPage.test.tsx
npm run typecheck
cd ..
git add apps-in-toss/public apps-in-toss/src/components \
        apps-in-toss/src/features/today apps-in-toss/src/app/routes.tsx
git commit -m "feat: add meal feedback and growth experience"
```

---

### Task 9: Add Settings, Data Deletion, External Policies, and Route Recovery

**Files:**
- Create: `apps-in-toss/src/features/settings/SettingsPage.tsx`
- Create: `apps-in-toss/src/features/settings/SettingsPage.test.tsx`
- Modify: `apps-in-toss/src/features/onboarding/OnboardingPage.tsx`
- Modify: `apps-in-toss/src/app/routes.tsx`
- Modify: `apps-in-toss/src/state/AppStateProvider.tsx`

**Interfaces:**
- Produces: profile/allergy editing, local-data deletion, privacy, and support actions.
- Consumes: `openURL` from `@apps-in-toss/web-framework`.
- Uses: existing GitHub Pages privacy and support URLs.

- [ ] **Step 1: Write failing deletion and external-link tests**

```tsx
it('requires confirmation and returns to onboarding after local deletion', async () => {
  renderSettings();
  await user.click(screen.getByRole('button', { name: '내 데이터 삭제' }));
  expect(screen.getByText('이 기기의 프로필, 기록, XP가 모두 삭제돼요.'))
    .toBeInTheDocument();
  await user.click(screen.getByRole('button', { name: '모두 삭제' }));
  expect(deleteAll).toHaveBeenCalledTimes(1);
  expect(await screen.findByRole('heading', { name: '냠냠레벨업 시작하기' }))
    .toBeInTheDocument();
});

it('opens only approved HTTPS policy destinations', async () => {
  renderSettings();
  await user.click(screen.getByRole('button', { name: '개인정보 처리방침' }));
  expect(openURL).toHaveBeenCalledWith(
    'https://h19h29-design.github.io/naymnaym/privacy.html',
  );
});
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
cd apps-in-toss
npm test -- src/features/settings/SettingsPage.test.tsx
```

- [ ] **Step 3: Implement settings and coordinated local deletion**

Use TDS list rows and a user-triggered confirmation dialog. After `deleteAll` succeeds, reset in-memory state before navigating to `/onboarding`. If deletion fails, retain the current state and show `데이터를 삭제하지 못했어요. 다시 시도해 주세요.`

```tsx
// apps-in-toss/src/features/settings/SettingsPage.tsx
import { openURL } from '@apps-in-toss/web-framework';
import { Button, Modal } from '@toss/tds-mobile';

export function SettingsPage() {
  const { repository, reload } = useAppState();
  const navigate = useNavigate();
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const deleteData = async () => {
    try {
      await repository.deleteAll();
      await reload();
      navigate('/onboarding', { replace: true });
    } catch {
      setError('데이터를 삭제하지 못했어요. 다시 시도해 주세요.');
    }
  };

  return (
    <main className="app-shell">
      <h1>설정</h1>
      <Button
        color="light"
        onClick={() => navigate('/onboarding?mode=edit&next=%2Fsettings')}
      >
        프로필과 알레르기 수정
      </Button>
      <Button color="light" onClick={() => void openURL(POLICY_URLS.privacy)}>
        개인정보 처리방침
      </Button>
      <Button color="light" onClick={() => void openURL(POLICY_URLS.support)}>
        문의 및 지원
      </Button>
      <Button color="danger" onClick={() => setDeleteOpen(true)}>
        내 데이터 삭제
      </Button>
      {error && <p role="alert">{error}</p>}
      <Modal open={deleteOpen} onOpenChange={setDeleteOpen}>
        <Modal.Overlay onClick={() => setDeleteOpen(false)} />
        <Modal.Content aria-label="내 데이터 삭제 확인">
          <h2>내 데이터 삭제</h2>
          <p>이 기기의 프로필, 기록, XP가 모두 삭제돼요.</p>
          <Button color="danger" onClick={() => void deleteData()}>모두 삭제</Button>
        </Modal.Content>
      </Modal>
    </main>
  );
}
```

Use `openURL` only for:

```ts
export const POLICY_URLS = {
  privacy: 'https://h19h29-design.github.io/naymnaym/privacy.html',
  support: 'https://h19h29-design.github.io/naymnaym/support.html',
} as const;
```

Do not link to app stores, advertisements, downloads, payment pages, or nonessential sites.

When `mode=edit`, replace the earlier context destructuring, initialize `OnboardingPage` from the ready profile, and preserve its original `createdAt`:

```tsx
const { state: appState, repository, reload } = useAppState();
const editing = searchParams.get('mode') === 'edit';
const existingProfile = appState.status === 'ready' ? appState.profile : null;

useEffect(() => {
  if (!editing || existingProfile === null) return;
  setNickname(existingProfile.nickname);
  setSchoolType(existingProfile.schoolType);
  setSelectedSchool(existingProfile.school);
  setKeyword(existingProfile.school.name);
  setAllergyCodes(existingProfile.allergyCodes);
}, [editing, existingProfile]);

// Inside submit():
createdAt: editing && existingProfile
  ? existingProfile.createdAt
  : new Date().toISOString(),
```

- [ ] **Step 4: Add invalid-route recovery**

Unknown paths redirect to `/today` for configured users or `/onboarding` for new users. Browser back navigation must use the Toss-provided navigation behavior; do not render a second top app bar or custom back button.

Replace `SettingsPlaceholder` in `apps-in-toss/src/app/routes.tsx` with:

```tsx
import { SettingsPage } from '../features/settings/SettingsPage';

{
  path: '/settings',
  element: profile ? <SettingsPage /> : onboarding,
}
```

- [ ] **Step 5: Verify GREEN and commit**

```bash
cd apps-in-toss
npm test -- src/features/settings/SettingsPage.test.tsx src/app/App.test.tsx
npm run typecheck
cd ..
git add apps-in-toss/src/features/settings apps-in-toss/src/app/routes.tsx \
        apps-in-toss/src/state/AppStateProvider.tsx \
        apps-in-toss/src/features/onboarding/OnboardingPage.tsx
git commit -m "feat: add mini-app privacy controls"
```

---

### Task 10: Update Policy Pages and Add Automated Free/Review Checks

**Files:**
- Modify: `marketing-site/dist/privacy.html`
- Modify: `marketing-site/dist/support.html`
- Create: `apps-in-toss/scripts/verify-release.mjs`
- Create: `apps-in-toss/README.md`
- Create: `docs/apps-in-toss-release-runbook.md`

**Interfaces:**
- Produces: accurate user-facing disclosure for the Toss local-only MVP.
- Produces: `npm run verify:release` to block oversized or unsafe bundles.
- Produces: a reproducible zero-cost operations and review runbook.

- [ ] **Step 1: Write the release verifier before building the final bundle**

```js
// apps-in-toss/scripts/verify-release.mjs
import { readdir, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const LIMIT = 100 * 1024 * 1024;
const ROOT = fileURLToPath(new URL('../dist/', import.meta.url));
const forbidden = [
  /NEIS_API_KEY/,
  /service_role/,
  /SUPABASE_SERVICE_ROLE_KEY/,
  /sk_live_/,
  /\beval\s*\(/,
];

async function walk(path) {
  const entries = await readdir(path, { withFileTypes: true });
  return (await Promise.all(entries.map(async (entry) => {
    const child = join(path, entry.name);
    return entry.isDirectory() ? walk(child) : [child];
  }))).flat();
}

const files = await walk(ROOT);
let total = 0;
for (const file of files) {
  const info = await stat(file);
  total += info.size;
  if (/\.(?:js|css|html|json|map)$/.test(file)) {
    const text = await readFile(file, 'utf8');
    for (const pattern of forbidden) {
      if (pattern.test(text)) throw new Error(`Forbidden secret marker in ${file}`);
    }
  }
}
if (total >= LIMIT) throw new Error(`Uncompressed bundle is ${total} bytes`);
console.log(`Release checks passed: ${total} bytes`);
```

- [ ] **Step 2: Update privacy and support content without erasing native-app disclosures**

Add a clearly labeled `토스 미니앱` section that states:

- nickname, school, allergies, meal records, XP, and level remain in Toss device storage;
- app deletion, Toss storage clearing, or device change can remove that data;
- `neis-proxy` receives only school search text or school codes/date and does not store user records;
- Supabase is used only for the serverless NEIS relay;
- the mini-app has an in-app local-data deletion action;
- privacy and support contacts remain those already published on the pages.

Keep the existing iOS/Android parent-sync description as a separate native-app section so the policy does not incorrectly claim it disappeared.

- [ ] **Step 3: Document configuration and zero-cost guardrails**

`apps-in-toss/README.md` must list:

```text
Client .env: AIT_APP_NAME, AIT_ICON_URL, VITE_NEIS_PROXY_URL, VITE_SUPABASE_ANON_KEY
Edge secrets: NEIS_API_KEY, NEIS_ALLOWED_ORIGINS
Forbidden services: Supabase DB/Auth users/Storage/Realtime, paid Toss features
Quota behavior: show RATE_LIMITED/service-limited UI; never upgrade automatically
```

The release runbook must explain where to copy console-issued values, how to rotate the NEIS key, how to add sandbox and production origins exactly, how to check Supabase usage, and how to stop the function if free limits are approached.

- [ ] **Step 4: Run policy and bundle checks**

```bash
rg -n "토스 미니앱|기기에만 저장|내 데이터 삭제|NEIS" \
  marketing-site/dist/privacy.html marketing-site/dist/support.html
cd apps-in-toss
npm run build:web
npm run verify:release
cd ..
git diff --check
```

Expected: both policy pages contain the mini-app disclosure, the built client contains no forbidden secret marker, and the uncompressed bundle is under 100 MB.

- [ ] **Step 5: Commit**

```bash
git add marketing-site/dist/privacy.html marketing-site/dist/support.html \
        apps-in-toss/scripts/verify-release.mjs apps-in-toss/README.md \
        docs/apps-in-toss-release-runbook.md
git commit -m "docs: add Toss privacy and release guardrails"
```

---

### Task 11: Complete Integration, Build the `.ait`, and Run Review Gates

**Files:**
- Modify only if verification finds defects: files created in Tasks 1–10.
- Verify: `apps-in-toss/dist/`
- Verify: generated `.ait` artifact.
- Verify: `docs/apps-in-toss-release-runbook.md`

**Interfaces:**
- Produces: a review candidate, not an automatic public launch.
- Registers: `오늘 급식 기록` / `Meal record` -> `intoss://{AIT_APP_NAME}/today`.
- Deploys: only `neis-proxy`, with JWT verification enabled.

- [ ] **Step 1: Run every automated test and static check**

```bash
cd apps-in-toss
npm test
npm run typecheck
npm run build:web
npm run verify:release
cd ..
npx --yes deno@2.9.4 fmt --check supabase/functions/neis-proxy \
  supabase/functions/_shared/neis-contract
npx --yes deno@2.9.4 test supabase/functions/neis-proxy
git diff --check
```

Expected: all client and Edge tests pass, typecheck is clean, the web bundle passes secret/size checks, and formatting is clean.

- [ ] **Step 2: Configure actual console-issued values in ignored local environments**

Obtain the app name and icon URL from the Apps-in-Toss console and the project URL and public anon key from the Supabase project settings. Put them in `apps-in-toss/.env`; verify with:

```bash
cd apps-in-toss
set -a
source .env
set +a
test -n "$AIT_APP_NAME"
test -n "$AIT_ICON_URL"
test -n "$VITE_NEIS_PROXY_URL"
test -n "$VITE_SUPABASE_ANON_KEY"
cd ..
```

Keep the actual values out of commits and terminal transcripts. The public anon key is allowed in the WebView client; service-role and NEIS keys are not.

- [ ] **Step 3: Publish the updated policy pages on the existing free GitHub Pages site**

Use an isolated temporary worktree for the existing `gh-pages` branch:

```bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
git worktree prune
site_worktree=$(mktemp -d)
git worktree add "$site_worktree" gh-pages
git -C "$site_worktree" rm -r --ignore-unmatch .
cp -R "$repo_root/marketing-site/dist/." "$site_worktree/"
git -C "$site_worktree" add -A
git -C "$site_worktree" diff --cached --check
if ! git -C "$site_worktree" diff --cached --quiet; then
  git -C "$site_worktree" commit -m "docs: publish Toss mini-app policies"
  git -C "$site_worktree" push origin gh-pages
fi
git worktree remove "$site_worktree"
curl -fsS -o /dev/null https://h19h29-design.github.io/naymnaym/privacy.html
curl -fsS -o /dev/null https://h19h29-design.github.io/naymnaym/support.html
```

Expected: both HTTPS checks return success and no new hosting product is created. If the temporary worktree command fails, leave the directory intact for inspection instead of deleting it manually.

- [ ] **Step 4: Deploy only the free Edge Function**

Set `SUPABASE_PROJECT_REF`, `NEIS_API_KEY`, and the exact comma-separated sandbox/production origins in the local shell, then run:

```bash
test -n "$SUPABASE_PROJECT_REF"
test -n "$NEIS_API_KEY"
test -n "$NEIS_ALLOWED_ORIGINS"
npx supabase secrets set \
  --project-ref "$SUPABASE_PROJECT_REF" \
  NEIS_API_KEY="$NEIS_API_KEY" \
  NEIS_ALLOWED_ORIGINS="$NEIS_ALLOWED_ORIGINS"
npx supabase functions deploy neis-proxy \
  --project-ref "$SUPABASE_PROJECT_REF"
```

Do not pass `--no-verify-jwt`. In the Supabase dashboard, confirm the project remains on the free plan and that no database, Auth user, Storage bucket, Realtime channel, or paid add-on was created.

- [ ] **Step 5: Build the Apps-in-Toss review artifact**

```bash
cd apps-in-toss
npm run build:ait
npm run verify:release
find dist -maxdepth 3 -type f -print
du -sh dist
```

Expected: `.ait` creation succeeds, the unpacked output stays below 100 MB, and the bundle contains only the intended seven growth PNGs and demo JSON.

- [ ] **Step 6: Register the direct feature route**

In the Apps-in-Toss console, register:

```text
Korean feature name: 오늘 급식 기록
English feature name: Meal record
Scheme: intoss://{the exact console-issued app name}/today
```

Open the registered feature from the console preview. Verify that a configured user lands on today’s meal, while a first-time user reaches onboarding and returns to `/today` after completion.

- [ ] **Step 7: Complete sandbox and real-device review matrix**

Run each row on both iOS and Android through the Apps-in-Toss sandbox/QR flow:

| Scenario | Required result |
|---|---|
| First launch | onboarding appears; no bottom sheet auto-opens |
| School search | middle/high results only; elementary results absent |
| Live meal | NEIS result is labeled as today’s live meal |
| No meal | no-meal message appears; demo data does not appear |
| Offline with exact cache | cached-data label appears |
| Offline without cache | retryable error appears; demo data does not appear |
| Allergy risk | allergen is named; one-bite is unavailable |
| Meal record | XP changes once; duplicate status update adds 0 XP |
| Relaunch | profile, records, and XP remain on the same device |
| Demo | demo is clearly labeled and persists no record or XP |
| Delete data | confirmation clears local data and returns to onboarding |
| Back gesture | Toss navigation works without a duplicate back button |
| Policy/support | approved HTTPS pages open |
| Interaction | every tap responds within two seconds |

Capture screenshots for onboarding, live meal, allergy prevention, growth, settings deletion, privacy, and both device platforms.

- [ ] **Step 8: Perform the final cost and review audit**

Confirm all of the following in the runbook:

```text
[ ] Supabase plan is Free and spend cap/paid upgrade is not enabled
[ ] Only neis-proxy is deployed
[ ] Database/Auth users/Storage/Realtime usage is zero
[ ] No paid Toss API or product is configured
[ ] No API key appears in the bundle, repository, logs, or responses
[ ] Privacy and support URLs are public
[ ] .ait unpacked size is below 100 MB
[ ] Today route is registered as an app feature
[ ] iOS and Android QR checks passed
[ ] Live failure never enters demo mode
```

Approval is still controlled by Toss, so do not claim guaranteed acceptance. Submit only after every objective gate above passes; if Toss reports a review defect, reproduce it in sandbox, add a failing regression test, fix it, and rerun this task.

- [ ] **Step 9: Commit only verification-driven corrections**

```bash
git status --short
git add apps-in-toss supabase/functions/neis-proxy \
        supabase/functions/_shared/neis-contract \
        marketing-site/dist/privacy.html marketing-site/dist/support.html \
        docs/apps-in-toss-release-runbook.md
git commit -m "test: verify apps-in-toss review candidate"
```

Skip this commit when verification required no source or documentation changes. Never commit `apps-in-toss/.env`, Edge secrets, generated `.ait` artifacts, screenshots containing personal data, or unrelated worktree files.
