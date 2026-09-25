/* A small adapter for Inferno Core 1.4.3's test detail hooks. Keep the
 * session footer link as the fallback if Core changes this markup. */
(function () {
  'use strict';

  const detailSuffix = '-detail';
  const detailSelector = '[data-testid$="-detail"]';
  const sessionPath = /^\/suites\/[^/]+\/([A-Za-z0-9_-]+)\/?$/;
  let scanPending = false;

  function addAction(detail, sessionId) {
    if (detail.querySelector('.au-result-feedback-action')) return;
    const testId = detail.getAttribute('data-testid')?.slice(0, -detailSuffix.length);
    if (!testId || !/^[A-Za-z0-9_-]{1,160}$/.test(testId)) return;
    const summary = document.querySelector('[data-testid="' + testId + '-summary"]');
    const resultTag = summary?.querySelector('[data-testid$="-pass"], [data-testid$="-fail"], [data-testid$="-error"], [data-testid$="-skip"], [data-testid$="-omit"], [data-testid$="-cancel"], [data-testid$="-wait"]');
    const resultId = resultTag?.getAttribute('data-testid')?.replace(/-(pass|fail|error|skip|omit|cancel|wait)$/, '');
    if (!resultId || !/^[A-Za-z0-9_-]{1,160}$/.test(resultId)) return;

    const container = document.createElement('div');
    container.className = 'au-result-feedback-action';
    const link = document.createElement('a');
    link.textContent = 'Give feedback on this result';
    link.href = '/feedback/?session=' + encodeURIComponent(sessionId) +
      '&test=' + encodeURIComponent(testId) + '&result=' + encodeURIComponent(resultId);
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.addEventListener('click', (event) => event.stopPropagation());
    container.append(link);
    detail.prepend(container);
  }

  function scan() {
    scanPending = false;
    const match = location.pathname.match(sessionPath);
    if (!match) return;
    document.querySelectorAll(detailSelector).forEach((detail) => addAction(detail, match[1]));
  }

  function scheduleScan() {
    if (scanPending) return;
    scanPending = true;
    requestAnimationFrame(scan);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleScan, { once: true });
  } else {
    scheduleScan();
  }
  new MutationObserver(scheduleScan).observe(document.body, { childList: true, subtree: true });
})();
