import 'dotenv/config';
import { defineConfig } from '@apps-in-toss/web-framework/config';
import { requireEnv } from './src/config/env';

export default defineConfig({
  appName: requireEnv('AIT_APP_NAME'),
  brand: {
    displayName: '급식레벨업',
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
