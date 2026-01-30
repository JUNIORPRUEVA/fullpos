import { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: any, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof ZodError) {
    return res.status(400).json({
      message: 'Validation error',
      issues: err.issues.map((issue) => ({ path: issue.path, message: issue.message })),
    });
  }

  // Common upload validation errors
  if (err?.message === 'Solo imágenes') {
    return res.status(400).json({ message: 'Solo imágenes' });
  }
  if (err?.name === 'MulterError') {
    return res.status(400).json({ message: err.message ?? 'Upload error' });
  }

  if (err?.status) {
    return res.status(err.status).json({ message: err.message ?? 'Request error' });
  }

  console.error(err);
  return res.status(500).json({ message: 'Unexpected error' });
}

export function notFound(_req: Request, res: Response) {
  res.status(404).json({ message: 'Not found' });
}
