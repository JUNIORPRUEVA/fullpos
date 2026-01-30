import app from './app';
import env from './config/env';
import { prisma } from './config/prisma';

const port = env.PORT;

async function bootstrap() {
  await prisma.$connect();
  app.listen(port, () => {
    console.log(`FULLPOS backend running on port ${port}`);
  });
}

bootstrap().catch((err) => {
  console.error('Failed to start server', err);
  process.exit(1);
});
