import { describe, expect, it } from 'vitest';
import { ALLERGIES, allergyRisk } from './allergy';

describe('allergy safety', () => {
  it('blocks one-bite when a selected allergen is present', () => {
    expect(allergyRisk({ allergyCodes: [5, 6, 15] }, [6, 9])).toEqual([6]);
  });

  it('keeps the menu allergen order when more than one allergen is selected', () => {
    expect(allergyRisk({ allergyCodes: [15, 5, 6] }, [6, 15])).toEqual([15, 6]);
  });

  it('defines all nineteen approved Korean allergy labels', () => {
    expect(Object.keys(ALLERGIES)).toHaveLength(19);
    expect(ALLERGIES[1]).toBe('난류');
    expect(ALLERGIES[19]).toBe('잣');
  });
});
