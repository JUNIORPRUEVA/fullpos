import { prisma } from '../../config/prisma';
import env from '../../config/env';

export async function getOwnerAppConfig(companyId?: number) {
  const company = companyId
    ? await prisma.company.findUnique({
        where: { id: companyId },
      })
    : null;

  return {
    androidUrl: company?.ownerAppAndroidUrl ?? env.OWNER_APP_ANDROID_URL ?? null,
    iosUrl: company?.ownerAppIosUrl ?? env.OWNER_APP_IOS_URL ?? null,
    version: company?.ownerAppVersion ?? env.OWNER_APP_VERSION ?? '1.0.0',
    companyId: company?.id ?? companyId ?? null,
  };
}
