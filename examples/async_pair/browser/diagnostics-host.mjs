import { runApplication } from './application.mjs';

runApplication({
  title: 'Async diagnostics', artifact: './async-pair-dev',
  eventName: 'metonic-async-pair', canvasId: 'canvas',
  statusId: 'status', stopId: 'stop',
  onLoaded: exports => {
    window.metonicAsyncDiagnostics = () => JSON.parse(exports.diagnostics_json());
  },
});
