export const openApiDocument = {
  openapi: '3.0.3',
  info: {
    title: 'FoodConnect API',
    version: '1.0.0',
    description: 'Versioned REST API for coordinating surplus food donations.',
  },
  servers: [{ url: '/api/v1' }],
  paths: {
    '/health': {
      get: {
        summary: 'Check API process health',
        responses: { '200': { description: 'API is running' } },
      },
    },
  },
};
