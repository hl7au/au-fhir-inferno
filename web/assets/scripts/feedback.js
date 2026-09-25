/* Public issue handoff. Only the explicitly listed fields enter the issue draft. */
(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const form = $('feedback-form');
  const review = $('feedback-review');
  const session = $('feedback-session');
  const suite = $('feedback-suite');
  const resultSelect = $('feedback-result');
  const resultSearch = $('feedback-result-search');
  const test = $('feedback-test');
  const outcome = $('feedback-outcome');
  const kind = $('feedback-kind');
  let results = [];
  let suiteVersion = '';
  let loadedSuiteId = '';
  let loadSequence = 0;
  let intakeEnabled = false;
  let activeDraft = null;
  const query = new URLSearchParams(location.search);
  let pendingTestId = safeReference(query.get('test'));
  let pendingResultId = safeReference(query.get('result'));

  function selectedResult() {
    return results.find((result) => result.id === resultSelect.value);
  }

  function setKind() {
    $('feedback-result-fields').hidden = kind.value !== 'result';
  }

  function setIdentity() {
    const named = document.querySelector('input[name="feedback-identity"]:checked')?.value === 'named';
    $('feedback-contact').hidden = !named;
    ['feedback-name', 'feedback-email', 'feedback-contact-public'].forEach((id) => {
      $(id).disabled = !named;
    });
    $('feedback-contact-public').required = named;
    $('feedback-contact-status').textContent = '';
  }

  function resetResults() {
    results = [];
    resultSearch.value = '';
    resultSearch.disabled = true;
    resultSelect.replaceChildren(new Option('Choose a result, or enter its test ID below', ''));
    resultSelect.value = '';
    $('feedback-result-count').textContent = '';
    test.readOnly = false;
    outcome.disabled = false;
    test.value = '';
    outcome.value = '';
  }

  function selectResult() {
    const result = selectedResult();
    test.readOnly = !!result;
    outcome.disabled = !!result;
    if (result) {
      test.value = result.test_id;
      outcome.value = ['pass', 'fail', 'error', 'skip', 'omit', 'cancel', 'wait'].includes(result.result)
        ? result.result : 'other';
    } else {
      test.value = '';
      outcome.value = '';
    }
  }

  function validReference(value) {
    return /^[A-Za-z0-9_-]{1,160}$/.test(value);
  }

  function safeReference(value) {
    return typeof value === 'string' && validReference(value) ? value : '';
  }

  function safeTime(value) {
    return typeof value === 'string' && /^\d{4}-\d\d-\d\dT[\d:.+-]+Z?$/.test(value)
      ? value : '';
  }

  function testIndex(testSuite) {
    const index = new Map();
    const groups = [...(Array.isArray(testSuite?.test_groups) ? testSuite.test_groups : [])];
    while (groups.length) {
      const group = groups.pop();
      if (!group || typeof group !== 'object') continue;
      (Array.isArray(group.tests) ? group.tests : []).forEach((entry) => {
        if (!safeReference(entry?.id)) return;
        const number = typeof entry.short_id === 'string' && /^[A-Za-z0-9. -]{1,30}$/.test(entry.short_id)
          ? entry.short_id.trim() : '';
        const title = typeof entry.title === 'string'
          ? entry.title.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 120) : '';
        index.set(entry.id, { number, title });
      });
      groups.push(...(Array.isArray(group.test_groups) ? group.test_groups : []));
    }
    return index;
  }

  function resultLabel(item) {
    const name = [item.number, item.title].filter(Boolean).join(' — ') || item.test_id;
    const outcome = { pass: 'Passed', fail: 'Failed', error: 'Error', skip: 'Skipped', omit: 'Omitted',
      cancel: 'Cancelled', wait: 'Waiting' }[item.result]
      || 'Other outcome';
    return `${name} · ${outcome}`;
  }

  function showResults() {
    const query = resultSearch.value.trim().toLocaleLowerCase();
    const selectedId = resultSelect.value;
    resultSelect.replaceChildren(new Option('Choose a result, or enter its test ID below', ''));
    const matching = results.filter((item) => !query ||
      `${item.number} ${item.title} ${item.test_id} ${item.result}`.toLocaleLowerCase().includes(query));
    const attention = matching.filter((item) => ['fail', 'error'].includes(item.result));
    const other = matching.filter((item) => !['fail', 'error'].includes(item.result));
    [['Failed or errored', attention], ['Other results', other]].forEach(([heading, items]) => {
      if (!items.length) return;
      const group = document.createElement('optgroup');
      group.label = heading;
      items.forEach((item) => group.append(new Option(resultLabel(item), item.id)));
      resultSelect.add(group);
    });
    resultSelect.value = matching.some((item) => item.id === selectedId) ? selectedId : '';
    selectResult();
    $('feedback-result-count').textContent = results.length
      ? `${matching.length} of ${results.length} results shown. Search by test number or title.`
      : '';
  }

  async function feedbackRef(sessionId) {
    if (!sessionId || !window.crypto?.subtle) return '';
    const bytes = new TextEncoder().encode('au-inferno-feedback:v1:' + sessionId);
    const digest = await window.crypto.subtle.digest('SHA-256', bytes);
    return 'fb-' + Array.from(new Uint8Array(digest)).slice(0, 12)
      .map((byte) => byte.toString(16).padStart(2, '0')).join('');
  }

  async function loadSession() {
    const sequence = ++loadSequence;
    const id = session.value.trim();
    const status = $('feedback-load-status');
    resetResults();
    suiteVersion = '';
    loadedSuiteId = '';
    suite.value = '';
    if (!id) {
      status.textContent = 'Enter a session reference, or continue without one.';
      return;
    }
    if (id.length > 100 || !validReference(id)) {
      status.textContent = 'A session reference can contain only letters, numbers, hyphens and underscores.';
      return;
    }
    status.textContent = 'Loading session context…';
    try {
      const base = '/suites/api/test_sessions/' + encodeURIComponent(id);
      const sessionResponse = await fetch(base, { credentials: 'same-origin' });
      if (sequence !== loadSequence) return;
      if (!sessionResponse.ok) throw new Error('Session unavailable');
      const sessionData = await sessionResponse.json();
      if (sequence !== loadSequence) return;
      const suiteId = sessionData.test_suite_id;
      if (typeof suiteId === 'string' && validReference(suiteId)) {
        let option = Array.from(suite.options).find((item) => item.value === suiteId);
        if (!option) {
          option = new Option(suiteId, suiteId);
          suite.add(option);
        }
        suite.value = suiteId;
        loadedSuiteId = suiteId;
      }
      suiteVersion = typeof sessionData.test_suite?.version === 'string'
        ? sessionData.test_suite.version.slice(0, 80) : '';
      const tests = testIndex(sessionData.test_suite);

      // Inferno's result serializer also contains inputs, outputs, messages and
      // request summaries. Never render or include any of those in feedback.
      const resultsResponse = await fetch(base + '/results', { credentials: 'same-origin' });
      if (sequence !== loadSequence) return;
      if (resultsResponse.ok) {
        const data = await resultsResponse.json();
        if (sequence !== loadSequence) return;
        if (Array.isArray(data)) {
          results = data.filter((item) => item && safeReference(item.id) &&
            safeReference(item.test_id)).map((item) => ({
              id: item.id,
              test_id: item.test_id,
              result: safeReference(item.result),
              created_at: safeTime(item.created_at),
              ...tests.get(item.test_id)
            }));
          resultSearch.disabled = !results.length;
          showResults();
        }
      }
      status.textContent = results.length
        ? `Loaded ${results.length} test results. Choose one to include its test ID, outcome and time.`
        : 'Session found, but no current test results are available. Enter a test ID and outcome if known.';
      if (pendingTestId) {
        const linkedResult = results.find((item) => item.id === pendingResultId && item.test_id === pendingTestId) ||
          results.filter((item) => item.test_id === pendingTestId)
          .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))[0];
        if (linkedResult) {
          resultSelect.value = linkedResult.id;
          selectResult();
          status.textContent = 'Selected the result you opened in Inferno. Check its details before reporting.';
        } else {
          test.value = pendingTestId;
          status.textContent = 'This test has no available result. Add the outcome you saw, if known.';
        }
        pendingTestId = '';
        pendingResultId = '';
      }
    } catch (_error) {
      if (sequence !== loadSequence) return;
      status.textContent = 'Session context is unavailable. It may have been purged. You can still report feedback with the reference and details you know.';
      if (pendingTestId) {
        test.value = pendingTestId;
        pendingTestId = '';
        pendingResultId = '';
      }
    }
  }

  async function report() {
    const isResult = kind.value === 'result';
    const chosen = selectedResult();
    const reference = session.value.trim();
    const testId = test.value.trim();
    const suiteOption = suite.selectedOptions[0];
    const suiteId = suite.value;
    const testName = chosen ? [chosen.number, chosen.title].filter(Boolean).join(' — ') : '';
    if (reference && (reference.length > 100 || !validReference(reference))) {
      session.setCustomValidity('Use only letters, numbers, hyphens and underscores.');
      session.reportValidity();
      return null;
    }
    session.setCustomValidity('');
    if (isResult && (!suiteId || !testId || !validReference(testId) || !outcome.value)) {
      $('feedback-load-status').textContent = 'For a result report, choose a suite, test ID and outcome.';
      return null;
    }
    const identity = document.querySelector('input[name="feedback-identity"]:checked')?.value || 'anonymous';
    const name = identity === 'named' ? $('feedback-name').value.trim() : '';
    const email = identity === 'named' ? $('feedback-email').value.trim() : '';
    if (identity === 'named' && !name && !email) {
      $('feedback-contact-status').textContent = 'Enter a name or contact email to use this option.';
      $('feedback-name').focus();
      return null;
    }

    const subject = isResult
      ? `AU Inferno result feedback: ${(testName || testId).slice(0, 120)}`
      : 'AU Inferno general feedback';
    const resultTime = isResult ? safeTime(chosen?.created_at) : '';
    const feedbackTime = new Date().toISOString();
    const feedbackReference = await feedbackRef(reference);
    const reporter = identity === 'named'
      ? [name, email && `Contact email (public): ${email}`].filter(Boolean).join('\n')
      : 'Anonymous community member';
    const context = [
      `Test kit: ${suiteOption?.dataset.kit || 'Not specified'}`,
      `Test kit version: ${suiteOption?.dataset.kitVersion || 'Not available'}`,
      `Suite ID: ${suiteId || 'Not specified'}`,
      `Suite version: ${suiteVersion || 'Not available'}`,
      `Test: ${isResult ? (testName || 'Not available') : 'Not applicable'}`,
      `Test ID: ${isResult ? testId : 'Not applicable'}`,
      `Outcome: ${isResult ? (safeReference(chosen?.result) || outcome.value) : 'Not applicable'}`,
      `Result time (UTC): ${isResult ? (resultTime || 'Not available') : 'Not applicable'}`,
      `Feedback time (UTC): ${feedbackTime}`,
      `Feedback reference: ${feedbackReference || 'Not available'}`
    ];
    return {
      subject,
      type: isResult ? 'Problem with a test result' : 'General feedback',
      context: context.join('\n'),
      expected: $('feedback-expected').value.trim(),
      actual: $('feedback-actual').value.trim(),
      reporter,
      payload: {
        type: kind.value,
        website: $('feedback-website').value,
        sessionId: reference,
        suiteId,
        suiteVersion,
        kitVersion: suiteOption?.dataset.kitVersion || '',
        testId: isResult ? testId : '',
        testName: isResult ? testName : '',
        outcome: isResult ? (safeReference(chosen?.result) || outcome.value) : '',
        resultTime,
        feedbackTime,
        expected: $('feedback-expected').value.trim(),
        actual: $('feedback-actual').value.trim(),
        identity,
        name,
        email,
        publishContact: identity === 'named' && $('feedback-contact-public').checked
      }
    };
  }

  kind.addEventListener('change', setKind);
  document.querySelectorAll('input[name="feedback-identity"]').forEach((radio) =>
    radio.addEventListener('change', setIdentity));
  resultSearch.addEventListener('input', showResults);
  resultSelect.addEventListener('change', selectResult);
  session.addEventListener('input', () => {
    loadSequence++;
    session.setCustomValidity('');
    resetResults();
    loadedSuiteId = '';
    suiteVersion = '';
    suite.value = '';
    $('feedback-load-status').textContent = 'Load this session to choose one of its results.';
  });
  suite.addEventListener('change', () => {
    if (suite.value !== loadedSuiteId) {
      resetResults();
      suiteVersion = '';
    }
  });
  $('feedback-load').addEventListener('click', loadSession);
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const draft = await report();
    if (!draft) return;
    $('feedback-form-status').textContent = '';
    try {
      const response = await fetch('/feedback/api/preview', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(draft.payload)
      });
      const preview = await response.json();
      if (!response.ok) {
        $('feedback-form-status').textContent = preview.error || 'Review the report details and try again.';
        return;
      }
      draft.subject = preview.title;
      draft.context = preview.context;
      draft.expected = preview.expected;
      draft.actual = preview.actual;
      draft.reporter = preview.reporter;
    } catch (_error) {
      intakeEnabled = false;
      $('feedback-form-status').textContent = 'The preview service is unavailable. Review the draft carefully before using GitHub.';
    }
    activeDraft = draft;
    $('feedback-subject').value = draft.subject;
    $('feedback-context').value = draft.context;
    $('feedback-review-expected').value = draft.expected;
    $('feedback-review-actual').value = draft.actual;
    $('feedback-review-identity').value = draft.reporter;
    const issueUrl = new URL('https://github.com/hl7au/au-fhir-inferno/issues/new');
    issueUrl.searchParams.set('template', 'inferno-feedback.yml');
    issueUrl.searchParams.set('title', draft.subject);
    issueUrl.searchParams.set('feedback_type', draft.type);
    issueUrl.searchParams.set('context', draft.context + '\nReporter: ' + draft.reporter);
    issueUrl.searchParams.set('expected', draft.expected);
    issueUrl.searchParams.set('actual', draft.actual);
    $('feedback-issue').href = issueUrl.toString();
    $('feedback-submit').hidden = !intakeEnabled;
    $('feedback-submit-status').textContent = intakeEnabled ? '' :
      'Account-free submission is not configured in this environment yet. You can still use the GitHub option.';
    $('feedback-copy-status').textContent = '';
    form.hidden = true;
    review.hidden = false;
    review.scrollIntoView({ block: 'start' });
  });
  $('feedback-edit').addEventListener('click', () => {
    activeDraft = null;
    review.hidden = true;
    form.hidden = false;
    form.scrollIntoView({ block: 'start' });
  });
  $('feedback-submit').addEventListener('click', async () => {
    if (!activeDraft || !intakeEnabled) return;
    const button = $('feedback-submit');
    button.disabled = true;
    $('feedback-submit-status').textContent = 'Posting feedback…';
    try {
      const response = await fetch('/feedback/api/reports', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(activeDraft.payload)
      });
      const answer = await response.json();
      if (!response.ok) throw new Error(answer.error || 'The report could not be posted.');
      if (!/^https:\/\/github\.com\/hl7au\/au-fhir-inferno\/issues\/\d+$/.test(answer.url)) {
        throw new Error('The report was posted, but its issue link could not be verified.');
      }
      $('feedback-done-link').href = answer.url;
      review.hidden = true;
      $('feedback-done').hidden = false;
      $('feedback-done').scrollIntoView({ block: 'start' });
    } catch (error) {
      $('feedback-submit-status').textContent = error.message || 'The report could not be posted. Please try again.';
    } finally {
      button.disabled = false;
    }
  });
  $('feedback-copy').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText([
        $('feedback-subject').value,
        $('feedback-context').value,
        'Reporter:\n' + $('feedback-review-identity').value,
        'What I expected:\n' + $('feedback-review-expected').value,
        'What happened:\n' + $('feedback-review-actual').value
      ].join('\n\n'));
      $('feedback-copy-status').textContent = 'Report copied. Paste it into the public GitHub issue form.';
    } catch (_error) {
      $('feedback-copy-status').textContent = 'Copy failed. Select and copy the message above.';
    }
  });

  setKind();
  setIdentity();
  fetch('/feedback/api/config', { credentials: 'same-origin' })
    .then((response) => response.json())
    .then((config) => { intakeEnabled = config.enabled === true; })
    .catch(() => { intakeEnabled = false; });
  const initialSession = query.get('session');
  if (initialSession && initialSession.length <= 100 && validReference(initialSession)) {
    session.value = initialSession;
    loadSession();
  } else if (pendingTestId) {
    test.value = pendingTestId;
    pendingTestId = '';
  }
})();
