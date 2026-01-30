import { Request, Response, NextFunction } from 'express';
import env from '../config/env';

export function overrideKeyGuard(req: Request, res: Response, next: NextFunction) {
  if (env.ALLOW_PUBLIC_CLOUD === true) {
    return next();
  }

  const apiKey = env.OVERRIDE_API_KEY?.trim();
  if (!apiKey) {
    return next();
  }

  const provided =
    (req.headers['x-override-key'] as string | undefined) ??
    (req.headers['x-cloud-key'] as string | undefined);

  if (!provided || provided.trim() != apiKey) {
    return res.status(401).json({ message: 'API key requerida' });
  }

  return next();
}
