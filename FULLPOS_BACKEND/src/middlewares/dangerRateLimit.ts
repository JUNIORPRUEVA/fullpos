import { Request, Response, NextFunction } from 'express';

const windowMs = 60_000;
const maxHits = 3;
const hits = new Map<string, number[]>();

export function dangerRateLimit(req: Request, res: Response, next: NextFunction) {
  const key = (req.headers['x-cloud-key'] as string | undefined) ?? req.ip;
  const now = Date.now();
  const list = hits.get(key) ?? [];
  const filtered = list.filter((t) => now - t < windowMs);
  filtered.push(now);
  hits.set(key, filtered);
  if (filtered.length > maxHits) {
    return res.status(429).json({ message: 'Demasiadas solicitudes' });
  }
  return next();
}
