import { TDSMobileAITProvider } from '@toss/tds-mobile-ait';
import type { PropsWithChildren } from 'react';

export function AppProviders({ children }: PropsWithChildren) {
  return <TDSMobileAITProvider brandPrimaryColor="#FF8A3D">{children}</TDSMobileAITProvider>;
}
