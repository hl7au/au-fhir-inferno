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
        <h6 class="mb-1">
          <a href="${session.url}" class="text-decoration-none">
            ${session.title}
          </a>
        </h6>
        <small class="text-muted">${new Date(session.date).toLocaleString()}</small><br>
      </li>
    `));
    $(`#${containerId}`).append(element);
  });
};

const clearSessions = () => {
  localStorage.removeItem('sessions');
  location.reload();
};

const createSession = () => {
  // Get Suite ID
  const suiteId = Array.from(document.getElementsByTagName('input'))
    .filter((elem) => elem.checked && elem.name === 'suite')
    .map((elem) => elem.value)[0]; // should only have one selected option

  // Get checked options and map to id and value
  const checkedOptions = Array.from(document.getElementsByTagName('input'))
    .filter((elem) => elem.checked && elem.name !== 'suite' && $(elem).is(':visible'))
    .map((elem) => ({
      id: elem.name,
      value: elem.value
    }));

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
      showToast(e);
    });
};
