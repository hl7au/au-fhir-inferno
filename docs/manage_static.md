# Managing Static Content

The **AU FHIR INFERNO** project uses Jekyll to manage static pages written in Markdown, YML, and HTML. Key content types include Test Kits, News, Events, the About Page, the Disclaimer Bar, and various elements on the Main Page. The document explains how to create and edit these content types by either copying and modifying template files or directly editing specific configuration files. Each section outlines the file paths to edit and the content elements to manage.

### How the Site Is Served

The generated site is served by the **application process itself**, not by a separate web
server. `bundle exec rake web:generate_*` writes Jekyll's output to `_site`, the Dockerfile
copies that into the image, and two Rack middlewares mounted in `config.ru` do what nginx
used to:

| Concern | Where it lives now |
| --- | --- |
| Serving `_site` at `/`, mime types, `Last-Modified`, `Cache-Control` | `lib/inferno_platform_template/static_site.rb` |
| `/suites` and `/suites/<suite_id>` to the kit page under `/test-kits/` | `lib/inferno_platform_template/suite_redirects.rb` |
| gzip for text responses | `Rack::Deflater` in `config.ru` |

Consequences worth knowing:

* There is **no `nginx.conf` to edit**. A new test kit needs its suite id prefix added to
  `KIT_PAGES` in `suite_redirects.rb`; a spec asserts every suite id listed under `suites:`
  in `web/_test_kits/*.md` is covered, so a missed one fails the build rather than the
  redirect.
* The site and Inferno's API always answer on **one origin**, which is why
  `web/assets/scripts/config.js` can use `window.location.origin` and why one image can
  serve dev, prod and every preview.
* Cache policy matches the old nginx config: `.png .svg .js .css .ico` get
  `public, max-age=86400`, everything else (chiefly the generated HTML) revalidates on
  every request, so a content deploy is visible immediately.
* Kit pages ask the running app which suites it actually has
  (`/suites/api/test_suites`) and hide the rest, because the site is generated once and
  shipped to environments whose test kit gems differ.

### Previewing Locally

Two ways, depending on whether you care about the `/suites` half of the site:

* **Jekyll only** (fastest loop for content work): `bundle exec rake web:serve_dev`
  regenerates and serves the static pages on `http://localhost:4000`. Anything under
  `/suites` 404s, because Inferno is not running.
* **The real thing**: `bundle exec rake web:generate_dev` then start the app
  (`bundle exec puma -p 4567`, or `make run`). `http://localhost:4567/` serves the site
  exactly as a deployed environment does, redirects included, with Inferno live under
  `/suites`. Regenerate after editing content; the middleware reads `_site` from disk, so
  a reload is enough and no restart is needed.

`_site` is gitignored and never committed. If it does not exist the middleware is a
pass-through, so the app still boots and serves `/suites` on a fresh checkout. Set
`STATIC_SITE_ROOT` to serve a site from somewhere other than `<app root>/_site`.

### Creating and Testing Static Pages:
1. Create a static page and push it to the repository. This will automatically trigger the deployment process, making your content available in the production environment. *(Note: This feature is currently unavailable as CI/CD is not yet configured.)*
2. Create or edit static pages, then push them to the repository. You can preview the Markdown directly in the GitHub interface.
3. Create or edit static pages, run the application locally to preview the results, and then push the changes to the repository.

### Types of Content We Manage:
* **Test Kits**
  * **How**: Use any file from `web/_test_kits/` as a template, copy its content into a new file, and save.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/_test_kits/au-core.md?plain=1
    * Title
    * Preview text
    * Full description
    * Tags
    * Date
    * Maturity
    * Version
    * Suites (for maintaining multiple versions, such as US Core)
    * Pinned status

* **News** (displayed on the `/news` page and homepage)
  * **How**: Use any file from `web/_news/` as a template, copy its content into a new file, and save.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/_news/2024-03-example-news-article.md?plain=1

* **Events** (displayed on the `/events` page and homepage)
  * **How**: Edit the file located at `web/_data/events.yml` and add a new item to the `event_list` array.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/_data/events.yml

* **About Page**
  * **How**: Edit the file at `web/about/index.html`.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/about/index.html

* **Disclaimer Bar**
  * **How**: Edit the file at `web/_includes/disclaimer_bar.html`.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/_includes/disclaimer_bar.html

* **Site Title in the Header** (We can also add a logo if needed.)
  * **How**: Edit the file at `web/_includes/header.html`.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/_includes/header.html

* **Footer Content**
  * **How**: Edit the file at `web/_includes/footer.html`.
  * **What**: https://github.com/hl7au/au-fhir-inferno/blob/master/web/_includes/footer.html

* **Main Page**
  * **Main Page Description**
    * **How**: Edit the file at `web/_config.yml`.
    * **What**: https://github.com/hl7au/au-fhir-inferno/blob/f52a3dc84b6411e191250420b0e98b5c4218e9dd/web/_config.yml#L7
  * **Quick Links on the Main Page**
    * **How**: Edit the file at `web/_config.yml`.
    * **What**: https://github.com/hl7au/au-fhir-inferno/blob/f52a3dc84b6411e191250420b0e98b5c4218e9dd/web/_config.yml#L27
