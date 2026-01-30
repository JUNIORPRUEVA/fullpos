import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import env from '../config/env';
import { JwtUser } from '../modules/auth/auth.types';

export function authGuard(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Token requerido' });
  }

  const token = authHeader.substring(7);
  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET) as JwtUser & { exp: number };
    req.user = {
      id: payload.id,
      companyId: payload.companyId,
      username: payload.username,
      role: payload.role,
      email: payload.email,
    };
    return next();
  } catch (err) {
    return res.status(401).json({ message: 'Token inv\u00e1lido o expirado' });
  }
}
