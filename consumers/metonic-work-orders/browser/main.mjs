import { runApplication } from './application.mjs';

runApplication({
  title: 'Work orders',
  artifact: './app',
  eventName: 'work-orders-refresh',
  canvasId: 'canvas',
  statusId: 'status',
  stopId: 'stop',
});
