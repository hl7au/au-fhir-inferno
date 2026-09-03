# Platform workstreams in flight

Work that spans more than one PR, with the sequencing that makes each step safe. One
section per workstream; delete a section once nothing is left in it.

## 1. Remove the nginx layer

The platform used to ship two images per release: the application image, and an nginx
image (`nginx.Dockerfile`) that baked the generated Jekyll site in and proxied `/suites`
to the app. That layer bought nothing the app could not do itself and cost a second image
to build, tag, promote and keep in step: every release produced an app image and a
matching `-nginx` image, and a skew between them was a silent content mismatch.

Everything nginx.conf did now has a home in the application image:

| nginx.conf did | now |
| --- | --- |
| serve `_site` at `/` | `lib/inferno_platform_template/static_site.rb`, plus `COPY ./_site` in the Dockerfile |
| `rewrite ^/suites/...` to `/test-kits/...` | `lib/inferno_platform_template/suite_redirects.rb` |
| `gzip on` | `Rack::Deflater` in `config.ru` |
| `Cache-Control` / `expires` maps | `static_site.rb` (same extensions, same values) |
| `proxy_redirect` patching absolute `Location` headers | `INFERNO_HOST` set properly, from the first ingress hostname (`templates/configs/inferno-configmap.yaml`) |
| `proxy_pass /hl7validatorapi` | already the gateway's job (`inferno-httproute.yaml`) |
| `client_max_body_size 4G` | not needed; Envoy streams request bodies with no cap, the 1MB default was nginx's own |

### Why it takes two PRs

Prod's ArgoCD Application renders this chart from **master, immediately on merge**, but
pins the application image via `values-prod.yaml`, which only advances on a separate
promotion PR. Deleting the nginx layer in one change would therefore put prod on a chart
with nothing serving `/` while its image still predated the static site: no landing page
until the promotion landed. Dev and previews do not have this problem, because ArgoCD
Image Updater tracks master builds there and their image is minutes behind the chart.

### PR one (done)

* `_site` copied into the application image; `StaticSite` and `SuiteRedirects`
  middlewares plus `Rack::Deflater` mounted in `config.ru`, above the OpenTelemetry
  handler and the request logger so pages and assets cost neither a span nor a log line.
* `INFERNO_HOST` written from the first ingress hostname, overridable with
  `inferno.host`. This was never set, so inferno_core defaulted to
  `http://localhost:4567` for the absolute redirect it issues on session creation, and
  nginx's `proxy_redirect` was quietly repairing it.
* Kit pages fetch `/suites/api/test_suites` and hide suites the running app does not
  have, because the site is generated once and shipped to environments whose test kit
  gems differ.
* `nginx.enabled` default flipped to **false**. `values-prod.yaml` sets it back to
  **true** explicitly, with a comment saying why and when it goes. `values-dev.yaml`
  dropped its nginx block.
* `values.schema.json` still accepts the whole `nginx` block (sparked-argo passes
  `nginx.enabled` and `nginx.platformImageUri`), but `platformImageUri` is no longer
  required and `nginx` is no longer in the top-level `required` list.
* The `redirect-nginx` Deployment, Service and ConfigMap are **gone already**, replaced
  by a Gateway API `RequestRedirect` filter on `inferno-redirect-route`. That workload
  was a two-replica nginx whose whole config was one `return 301`, it is unrelated to the
  image pin, and Envoy Gateway v1.8.2 implements the filter fully, so it had no reason to
  wait for PR two. Its PodDisruptionBudget went with it.
* The nginx image is still built and still aliased on release. Nothing was removed from
  `build-and-release-package.yaml`, `prod-release.yaml` or the promotion step.

### PR two (after prod is promoted)

Gated on a promotion PR landing a `values-prod.yaml` image that contains `_site`. Verify
the promoted image serves the landing page in dev first, then:

* Delete `nginx.Dockerfile` and `nginx.conf`.
* Delete `templates/deployments/nginx.deployment.yaml`,
  `templates/services/nginx.service.yaml`, `templates/configs/nginx-configmap.yaml`, and
  the nginx **sidecar** container and its volume from
  `templates/deployments/inferno.deployment.yaml`. That sidecar receives no traffic at all
  today: the `nginx` Service selects the separate `nginx-app` Deployment, so the sidecar
  in the app pod has been dead weight in every environment.
* Delete the `nginx` block from `values.yaml`, `values-prod.yaml` and
  `values.schema.json`, and the `enabled`/`else` branch from `inferno-httproute.yaml`.
* Remove `- app: nginx-app` from `podDisruptionBudgets` in `values-prod.yaml`.
* Remove the nginx image build from `.github/workflows/build-and-release-package.yaml`,
  the `-nginx` alias from `.github/workflows/prod-release.yaml`, and the
  `nginx.platformImageUri` line from the promotion `sed`.
* Remove `--set nginx.platformImageUri=...` from the preview render in
  `.github/workflows/quality-control.yaml`, and the `-nginx-pr` mentions from
  `docs/preview-environments.md` and `docs/cicd-overhaul-plan.md`.
* In **aehrc/sparked-argo**, drop `nginx.platformImageUri` from
  `apps/inferno-dev/image-values.yaml`, and the `nginx.*` keys from the
  `inferno-previews` and `kit-previews` ApplicationSets. Order matters: the schema keeps
  accepting the keys, so sparked-argo can be cleaned up before or after this PR, but the
  keys must not be removed from the schema until sparked-argo has stopped sending them.
* Delete this section.
