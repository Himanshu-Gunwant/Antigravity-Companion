import { FastifyInstance } from 'fastify';
import { NotificationService } from '../services/notification';

export async function notificationRoutes(
  fastify: FastifyInstance,
  options: { notificationService: NotificationService }
) {
  const { notificationService } = options;

  fastify.post('/register-device', async (request, reply) => {
    const { deviceId, fcmToken, platform } = request.body as {
      deviceId?: string;
      fcmToken?: string;
      platform?: 'android' | 'ios';
    };

    if (!deviceId || !fcmToken || !platform) {
      return reply.status(400).send({ error: 'Missing deviceId, fcmToken, or platform' });
    }

    if (platform !== 'android' && platform !== 'ios') {
      return reply.status(400).send({ error: 'Invalid platform. Must be "android" or "ios"' });
    }

    try {
      notificationService.registerDevice(deviceId, fcmToken, platform);
      return reply.send({ success: true, message: 'Device token registered successfully' });
    } catch (err: any) {
      return reply.status(500).send({ error: 'Failed to register device token', details: err.message });
    }
  });
}
