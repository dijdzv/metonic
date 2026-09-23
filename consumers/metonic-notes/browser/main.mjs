import { runApplication } from './application.mjs';

runApplication({
  title: 'Memo', artifact: './app', eventName: 'notes-refresh',
  canvasId: 'canvas', statusId: 'status', stopId: 'stop',
});
