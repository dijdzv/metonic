import { runApplication } from './application.mjs';

runApplication({
  title: 'Async pair', artifact: './async-pair', eventName: 'metonic-async-pair',
  canvasId: 'canvas', statusId: 'status', stopId: 'stop',
});
