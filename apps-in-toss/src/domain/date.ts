const SEOUL = 'Asia/Seoul';

export function getSeoulDateKey(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: SEOUL, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}${value.month}${value.day}`;
}

function dateFromKey(key: string) {
  return new Date(Date.UTC(Number(key.slice(0, 4)), Number(key.slice(4, 6)) - 1, Number(key.slice(6, 8)), 12));
}

export function addDays(key: string, count: number) {
  const date = dateFromKey(key);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10).replaceAll('-', '');
}

export function weekKeys(start: string) {
  const weekday = dateFromKey(start).getUTCDay();
  const monday = addDays(start, -((weekday + 6) % 7));
  return Array.from({ length: 7 }, (_, index) => addDays(monday, index));
}

export function formatKoreanDate(key: string, includeWeekday = true) {
  return new Intl.DateTimeFormat('ko-KR', { month: 'long', day: 'numeric', ...(includeWeekday ? { weekday: 'short' as const } : {}) }).format(dateFromKey(key));
}
