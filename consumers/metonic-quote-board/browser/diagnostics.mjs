import { runApplication } from './application.mjs';

runApplication({
  title: 'Item and quote board diagnostics', artifact: './app',
  eventName: 'quote-board-refresh', canvasId: 'canvas',
  statusId: 'status', stopId: 'stop',
  onLoaded: exports => {
    window.metonicQuoteDiagnostics = () => JSON.parse(exports.diagnostics_json());
  },
});
