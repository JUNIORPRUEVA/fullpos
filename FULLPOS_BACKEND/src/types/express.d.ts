import type { JwtUser } from '../modules/auth/auth.types';

declare global {
  namespace Express {
    // eslint-disable-next-line @typescript-eslint/naming-convention
    interface Request {
      user?: JwtUser;
    }
  }
}
