import { runApplication } from './application.mjs';

runApplication({
  title: 'Item and quote board', artifact: './app', eventName: 'quote-board-refresh',
  canvasId: 'canvas', statusId: 'status', stopId: 'stop',
});
