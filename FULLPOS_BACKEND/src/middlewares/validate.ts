import { NextFunction, Request, Response } from 'express';
import { ZodSchema } from 'zod';

type RequestPart = 'body' | 'query' | 'params';

export function validate(schema: ZodSchema, part: RequestPart = 'body') {
  return (req: Request, _res: Response, next: NextFunction) => {
    const parsed = schema.safeParse(req[part]);
    if (!parsed.success) {
      const err = parsed.error;
      return next(err);
    }

    // Replace the parsed payload to ensure types downstream
    (req as any)[part] = parsed.data;
    next();
  };
}
