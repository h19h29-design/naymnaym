import type { PropsWithChildren } from 'react';
import { TDSMobileAITProvider } from '@toss/tds-mobile-ait';

export function AppProviders({ children }: PropsWithChildren) {
  return <TDSMobileAITProvider>{children}</TDSMobileAITProvider>;
}
