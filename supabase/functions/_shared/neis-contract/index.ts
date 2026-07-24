export type SchoolType = "middle" | "high";

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
  | { action: "searchSchools"; payload: { keyword: string } }
  | {
    action: "fetchMeals";
    payload: { officeCode: string; schoolCode: string; date: string };
  };

export type ProxyErrorCode =
  | "BAD_REQUEST"
  | "FORBIDDEN_ORIGIN"
  | "NO_DATA"
  | "NOT_CONFIGURED"
  | "RATE_LIMITED"
  | "UPSTREAM_ERROR";

export type ApiResult<T> =
  | { ok: true; data: T }
  | { ok: false; code: ProxyErrorCode; message: string };
