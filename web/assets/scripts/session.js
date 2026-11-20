const basePath = '/suites';

/* 
* Get local storage sessions 
* Format of local storage is:
* sessions: {
*  recent_sessions: [
*    {
*      id: string,
*      url: string,
*      title: string,
*      date: string,
*    },
*  ]
* }
*/
const getSessions = () => {
  const sessionsString = localStorage.getItem('sessions');
  try {
    const sessions = JSON.parse(sessionsString);
    const sessionsList = sessions && sessions.recent_sessions
      ? sessions.recent_sessions
      : [];
    return sessionsList
      .sort((a, b) => a.date.localeCompare(b.date))
      .reverse();
  } catch {
    return [];
  }
};

const populateSessions = (sessions, containerId) => {
  sessions.forEach((session) => {
    const element = $($.parseHTML(`
      <li class="list-group-item">
        <a href="${session.url}" class="text-decoration-none">
            <div>
                <h6 class="mb-1">${session.title}</h6>
                <small class="text-muted">${new Date(session.date).toLocaleString()}</small><br>
            </div>
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">
                <path d="M9.00002 15.8746L12.88 11.9946L9.00002 8.11461C8.61002 7.72461 8.61002 7.09461 9.00002 6.70461C9.39002 6.31461 10.02 6.31461 10.41 6.70461L15 11.2946C15.39 11.6846 15.39 12.3146 15 12.7046L10.41 17.2946C10.02 17.6846 9.39002 17.6846 9.00002 17.2946C8.62002 16.9046 8.61002 16.2646 9.00002 15.8746Z" fill="#6C757D"/>
            </svg>
        </a>
      </li>
    `));
    $(`#${containerId}`).append(element);
  });
};

const clearSessions = () => {
  localStorage.removeItem('sessions');
  location.reload();
};

// POST /suites/<suite id> is inferno_core's session form route
// (TestSessionFormPostController): it creates the session, applies any suite options
// sent as form fields, and redirects to the session page on the host it was posted to.
const launchOnHost = (host, suiteId, options) => {
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = `${host}${basePath}/${encodeURIComponent(suiteId)}`;
  options.forEach((option) => {
    const field = document.createElement('input');
    field.type = 'hidden';
    field.name = option.id;
    field.value = option.value;
    form.appendChild(field);
  });
  document.body.appendChild(form);
  form.submit();
};

const createSession = (target) => {

  showSpinner(target);

  // Get Suite ID
  const suiteInput = Array.from(document.getElementsByTagName('input'))
    .filter((elem) => elem.checked && elem.name === 'suite')[0]; // should only have one selected option
  const suiteId = suiteInput && suiteInput.value;

  // Get checked options and map to id and value
  const checkedOptions = Array.from(document.getElementsByTagName('input'))
    .filter((elem) => elem.checked && elem.name !== 'suite' && $(elem).is(':visible'))
    .map((elem) => ({
      id: elem.name,
      value: elem.value
    }));

  // A CI-build suite offered from another environment (see the test-kit layout) launches
  // there. The page cannot POST the JSON API cross-origin, so it submits Inferno's own
  // session form route instead: a top-level navigation, which needs no CORS, and which
  // ends on the new session's page on that host.
  const launchHost = suiteInput && suiteInput.dataset.launchHost;
  if (launchHost) {
    launchOnHost(launchHost, suiteId, checkedOptions);
    return;
  }

  const hostAndBasePath = `${siteConfig.infernoHost}${basePath}`
  const postUrl = `${hostAndBasePath}/api/test_sessions?test_suite_id=${suiteId}`;
  const postBody = {
    preset_id: null,
    suite_options: checkedOptions,
  };
  fetch(postUrl, { method: 'POST', body: JSON.stringify(postBody) })
    .then((response) => response.json())
    .then((result) => {
      const sessionId = result.id;
      if (!result) {
        throw Error('Session could not be created. Please check input values.');
      } else if (!sessionId || sessionId === 'undefined') {
        throw Error('Session could not be created. Session ID is undefined.');
      } else {
        location.href = `${hostAndBasePath}/test_sessions/${sessionId}`;
      }
    })
    .catch((e) => {
      restoreText(target);
      showToast(e);
    });
};
