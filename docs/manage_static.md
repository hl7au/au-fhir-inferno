# Managing Static Content

The **AU FHIR INFERNO** project uses Jekyll to manage static pages written in Markdown, YML, and HTML. Key content types include Test Kits, News, Events, the About Page, the Disclaimer Bar, and various elements on the Main Page. The document explains how to create and edit these content types by either copying and modifying template files or directly editing specific configuration files. Each section outlines the file paths to edit and the content elements to manage.

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
