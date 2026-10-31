import { app } from './app.js';
import { env } from './config/env.js';
import { logger } from './lib/logger.js';
import { prisma } from './lib/prisma.js';

try {
  await prisma.$connect();
} catch (error) {
  logger.fatal({ err: error }, 'database connection failed');
  process.exit(1);
}

const server = app.listen(env.PORT, () => {
  logger.info({ port: env.PORT, environment: env.NODE_ENV }, 'FoodConnect API started');
});

const shutdown = (signal: string) => {
  logger.info({ signal }, 'shutting down');
  server.close((error) => {
    if (error) {
      logger.error({ err: error }, 'shutdown failed');
      void prisma.$disconnect()
        .catch((disconnectError: unknown) => {
          logger.error({ err: disconnectError }, 'database disconnect failed');
        })
        .finally(() => process.exit(1));
      return;
    }
    void prisma.$disconnect()
      .then(() => process.exit(0))
      .catch((disconnectError: unknown) => {
        logger.error({ err: disconnectError }, 'database disconnect failed');
        process.exit(1);
      });
  });
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
