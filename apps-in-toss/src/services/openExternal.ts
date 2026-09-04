import { Device } from '@apps-in-toss/web-framework';

export const EXTERNAL_URLS = {
  privacy: 'https://nyam.h19h19.com/privacy.html',
  support: 'https://nyam.h19h19.com/support.html',
} as const;

export async function openExternal(url: string) {
  await Device.openURL(url);
}
