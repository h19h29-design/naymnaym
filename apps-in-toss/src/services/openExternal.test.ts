import { beforeEach, describe, expect, it, vi } from 'vitest';

const openURL = vi.fn();
vi.mock('@apps-in-toss/web-framework', () => ({ Device: { openURL } }));

describe('external URLs', () => {
  beforeEach(() => openURL.mockReset());
  it('uses the current SDK Device API', async () => {
    const { EXTERNAL_URLS, openExternal } = await import('./openExternal');
    await openExternal(EXTERNAL_URLS.privacy);
    expect(openURL).toHaveBeenCalledWith('https://nyam.h19h19.com/privacy.html');
  });
});
