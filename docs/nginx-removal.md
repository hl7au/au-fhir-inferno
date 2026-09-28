# Removing the nginx layer

This change spanned two PRs, both merged, plus one small follow-up. Here is the
sequencing that made each step safe, and the one step left. Delete this file once it is
done.

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
| `proxy_redirect` patching absolute `Location` headers | `lib/inferno_platform_template/request_host_redirects.rb`, plus `INFERNO_HOST` set per environment from the first ingress hostname (`templates/configs/inferno-configmap.yaml`) |
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
* `RequestHostRedirects` mounted around the Inferno app, rewriting an absolute `Location`
  on our own origin under `/suites` back onto the hostname the client used. This is
  nginx's `proxy_redirect` rule, scoped to our own origin so a test kit's OAuth redirect
  is never touched. Without it, removing nginx would regress every environment serving
  more than one hostname.
* `INFERNO_HOST` written from the first ingress hostname, overridable with
  `inferno.host`. Nothing set it here before, so the value came from the `.env` baked
  into the image: the dev-flavoured image, which every preview also runs, carries the dev
  host, and prod's image carries `hl7.org.au`. inferno_core builds an absolute redirect
  from it on session creation, so a preview would have sent its user to dev. It is now
  the environment's canonical origin, and with the middleware above it no longer decides
  which hostname a user ends up on.
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

### PR two (done)

Landed once prod was promoted to an image containing `_site` (da27559).

* `nginx.Dockerfile`, `nginx.conf` and the local-only `config/nginx.conf` deleted, with
  `config/development-certs`, which existed only for that local nginx's TLS listener.
  `compose.yml` publishes `inferno_web` on host port 80, so `http://localhost` still
  serves the whole platform.
* The chart's nginx Deployment, Service, ConfigMap and the sidecar in the inferno-app pod
  deleted. The HTTPRoute sends `/` to `inferno:4567` unconditionally, the `inferno`
  Service exposes only 4567, and prod's `nginx` block and `nginx-app` PodDisruptionBudget
  are gone. No template reads `.Values.nginx`.
* The nginx image build, its promotion `sed` and its `-nginx` release alias removed from
  the workflows; the quality-control preview render no longer passes
  `nginx.platformImageUri`.
* `values.schema.json` keeps a schema-only `nginx` property accepting just `enabled` and
  `platformImageUri`, marked deprecated and ignored, because aehrc/sparked-argo still
  sent those keys when this merged and the top-level schema rejects unknown properties.
* In **aehrc/sparked-argo**, a companion PR drops `nginx.platformImageUri` from
  `apps/inferno-dev/image-values.yaml` and the Image Updater's nginx alias, and the
  `nginx.*` keys from the `inferno-previews` and `kit-previews` ApplicationSets.

### Remaining step

Once the sparked-argo PR has merged and Argo CD has synced it (check that
`apps/inferno-dev/image-values.yaml` has no `nginx:` key and that neither ApplicationSet
passes one), delete the `nginx` property from `values.schema.json` and the sentence about
it in the preview-render comment in `.github/workflows/quality-control.yaml`. Nothing
else in the chart references it. Then delete this file.
