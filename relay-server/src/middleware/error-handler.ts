import { FastifyError, FastifyReply, FastifyRequest } from 'fastify';

export function errorHandler(error: FastifyError, request: FastifyRequest, reply: FastifyReply) {
  // Log the error stack trace
  request.log.error({ err: error }, `[ErrorHandler] Request failed: ${request.method} ${request.url}`);

  // Determine standard status code
  const statusCode = error.statusCode || 500;

  // Send a normalized JSON response
  reply.status(statusCode).send({
    success: false,
    error: {
      message: error.message || 'Internal Server Error',
      code: error.code || 'UNKNOWN_ERROR',
    }
  });
}
