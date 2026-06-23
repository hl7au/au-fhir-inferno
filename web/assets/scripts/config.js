---
---
var siteConfig = {
  // Use the current origin so the static build is host-agnostic. The site, its API
  // (/suites/api/...) and the session pages are always served from the SAME host
  // (nginx proxies /suites to the inferno backend), so same-origin is always correct.
  // Baking site.inferno_host broke things under the build-once model: staging and every
  // preview ship the same image as prod, so the prod (or dev) host was hard-coded and the
  // UI POSTed cross-origin to a different host, which the browser blocks via CORS.
  infernoHost: window.location.origin,
};
