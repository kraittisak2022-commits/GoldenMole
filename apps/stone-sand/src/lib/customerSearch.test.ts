import { matchedAlias, matchesCustomer, parseAliases } from './customerSearch';

const shop = { name: 'ร้านสินทวีวังเหนือ', aliases: ['เสี่ยบาส', 'บาส'], phone: '0931234567' };

describe('parseAliases', () => {
  it('splits on commas and new lines, trims and drops blanks and repeats', () => {
    expect(parseAliases(' เสี่ยบาส , บาส\nเฮียบาส,, บาส ')).toEqual(['เสี่ยบาส', 'บาส', 'เฮียบาส']);
    expect(parseAliases('')).toEqual([]);
  });
});

describe('matchesCustomer', () => {
  it('finds a shop by any of its other names', () => {
    expect(matchesCustomer(shop, 'เสี่ยบาส')).toBe(true);
    expect(matchesCustomer(shop, 'สินทวี')).toBe(true);
    expect(matchesCustomer(shop, '123')).toBe(true);
    expect(matchesCustomer(shop, 'สมชาย')).toBe(false);
  });
});

describe('matchedAlias', () => {
  it('names the alias only when the main name did not match', () => {
    expect(matchedAlias(shop, 'เสี่ย')).toBe('เสี่ยบาส');
    expect(matchedAlias(shop, 'สินทวี')).toBeNull();
  });
});
