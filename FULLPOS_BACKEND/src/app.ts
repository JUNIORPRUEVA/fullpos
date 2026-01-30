import express from 'express';
import path from 'path';
import helmet from 'helmet';
import morgan from 'morgan';
import cors from 'cors';
import routes from './routes';
import { errorHandler, notFound } from './middlewares/errorHandler';
import env, { corsOrigins } from './config/env';

const app = express();

app.set('trust proxy', true);

app.use(express.json());
app.use(helmet());
app.use(
  cors({
    origin: corsOrigins.includes('*') ? true : corsOrigins,
    credentials: true,
  }),
);
app.use(morgan(env.NODE_ENV === 'production' ? 'combined' : 'dev'));

app.use('/api', routes);

const uploadsDir = env.UPLOADS_DIR?.trim() || path.join(process.cwd(), 'uploads');
app.use('/uploads', express.static(uploadsDir));

app.use(notFound);
app.use(errorHandler);

export default app;
