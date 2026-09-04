import { describe, expect, it } from 'vitest';
import { hasAllergyRisk } from './allergy';

describe('allergy matching', () => {
  it('matches numeric allergy codes without partial-string errors', () => {
    expect(hasAllergyRisk([1, 12], [12])).toBe(true);
    expect(hasAllergyRisk([1], [12])).toBe(false);
  });
});
