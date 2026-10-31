import { app } from './app.js';
import { env } from './config/env.js';
import { logger } from './lib/logger.js';

const server = app.listen(env.PORT, () => {
  logger.info({ port: env.PORT, environment: env.NODE_ENV }, 'FoodConnect API started');
});

const shutdown = (signal: string) => {
  logger.info({ signal }, 'shutting down');
  server.close((error) => {
    if (error) {
      logger.error({ err: error }, 'shutdown failed');
      process.exit(1);
    }
    process.exit(0);
  });
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
