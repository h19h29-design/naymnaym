import { defineConfig } from '@apps-in-toss/web-framework/config';

export default defineConfig({
  appName: 'nyam-levelup',
  brand: { primaryColor: '#FF8A3D' },
  webView: {
    bounces: false,
    allowsBackForwardNavigationGestures: true,
  },
  webBundleDir: 'dist',
  permissions: [],
});
