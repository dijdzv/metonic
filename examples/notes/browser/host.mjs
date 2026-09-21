import { runApplication } from './application.mjs';

runApplication({
  title: 'Notes', artifact: './notes', eventName: 'metonic-notes',
  canvasId: 'canvas', statusId: 'status', stopId: 'stop',
  controls: [{ id: 'note' }, { id: 'clear', action: 1 }],
});
