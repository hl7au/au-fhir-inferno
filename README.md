# Inferno Test Kit Platform Template

Important: this repository is based on an experimental template extracted from
the source of [Inferno on HealthIT.gov](https://inferno.healthit.gov) and will
need to be updated as components of Inferno are updated.  As such, this should
not yet be considered stable and a moderate amount of effort will be necessary
to upgrade this site in coordination with updates to Inferno.  Using this
template requires web application development knowledge.

The contents of this README will be moved into [Inferno Framework
documentation](https://inferno-framework.github.io) once the concept and
implementation of Inferno Platforms is more mature.

Additionally, some aspects of this repository are a work in progress, including
the contents of the README and organization of the styles and html templates.

## Background
Inferno tests are packaged into testing applications called Test Kits.  These
Test Kits are designed to be portable, standalone applications that can be
downloaded and run in a local environment.  They also can be hosted in a shared
environment for use by multiple users, but by default Test Kit applications do
not provide a turnkey solution for hosting multiple Test Kits on a single host.

Sometimes, it is useful to provide a single web that hosts multiple test kits.  The
[Inferno on HealthIT.gov](htps://inferno.healthit.gov) host is one such example.
It hosts Test Kits that are relevant to ONC's mission, and provides a UI that is
suited for multi-Test Kit installations.

These sites are called Inferno Test Kit Platforms.  They provide a platform for
loading multiple Test Kits.  Besides providing a UI that enable navigation
across multiple Test Kits, they also:

* Provide a configuration that assumes a larger, shared environment.  Such as
  using a Postgres database by default.
* Provide tools to manage the data on the system, such as data retention purging
  tools and a dashboard providing an overview of test usage on the platform.

If you would like to set up a platform, this is the place to start.  Please
remember that this is under heavy development and is not yet stable.

## Reporting Issues
We appreciate your contributions to improving hl7au/au-fhir-inferno. **If you encounter a bug or wish to make a feature request, please follow the steps below to raise an issue**:

### 1. Search for Existing Issues
Before submitting a new issue, please search the GitHub [Issues list](https://github.com/hl7au/au-fhir-inferno/issues) to check if your issue has already been reported. If you find an existing issue, you can add your comments or additional information to it.

### 2. Open a New Issue
If you do not find a similar issue, you can open a [new one](https://github.com/hl7au/au-fhir-inferno/issues). Click on the New Issue button and provide details, e.g., for a bug report:

```
Title: A brief and descriptive title for the issue.
Description: A detailed description of the issue, including:
1. Steps to reproduce the issue.
2. Expected and actual behaviour.
3. Screenshots or another related information (if applicable).
```

### 3. Labelling
Help us categorise the issue by adding relevant labels (e.g., bug, enhancement). This helps us prioritise and address the issues more efficiently.

### Resolving Issues
To support effective issue resolution, reporters may be engaged in the review process to help confirm that resolutions address their concerns. This can involve notifying the reporter when a fix is implemented and inviting them to validate the solution or provide feedback before the issue is formally closed.

### Questions?
If you have a question, the best place to start is Zulip e.g. the https://chat.fhir.org/#narrow/channel/179309-inferno channel.

## How to Contribute to the HL7 AU Inferno Test Kit Platform
If you would like to add an Inferno test kit for a published HL7 AU FHIR IG, here’s how you can contribute:

### 1. Communicate Before You Start
- Open a [GitHub issue](https://github.com/hl7au/au-fhir-inferno/issues) to discuss your plans to help avoid duplication of effort, align and prioritise your contributions.
- Join the fortnightly HL7 AU Infrastructure and Tooling Community Meetings ([register here](https://confluence.hl7.org/display/HAFWG/Infrastructure+and+Tooling+Contact+List)) where we discuss and triage issues. Feel free to add your issue to the [meeting agenda](https://confluence.hl7.org/pages/viewpage.action?pageId=265492851#CommunityMeetingAgendaandMinutes-MeetingDetails) and we'll aim to discuss your issue/ proposed contribution when you are present at the meeting.
- Use Zulip to connect with the team and community asynchronously: 
  - Specific topic for HL7 AU Inferno Test Kit feedback and queries: [australia > Inferno Test Kit feedback and queries](https://chat.fhir.org/#narrow/channel/179173-australia/topic/Inferno.20Test.20Kit.20feedback.20and.20queries)
  - General: [Inferno channel](https://chat.fhir.org/#narrow/channel/179309-inferno)

### 2. Contribute Code
1. Fork this repository.
2. Create a branch and use the GitHub issue number followed by a meaningful description as the branch name for your contribution.
3. Make your contributions/ changes.
4. Submit a pull request (PR) for review.
5. Once the PR has been reviewed, feedback addressed collaboratively, and approved (by the designated HL7 AU project facilitator or their delegate - refer to the [HL7 AU Project Registry](https://confluence.hl7.org/display/HA/HL7+Australia+Project+Registry)), it may be merged into the main branch.

## Getting Started

1. Clone the Inferno Platform Template repository: To get started, you can
create a new git repository by cloning the [Inferno Platform
Template](https://github.com/inferno-framework/inferno-platform-template)
repository or using GitHub's built in "Use this template" action.  The template
provides a couple of pre-configured Test Kits and templated content, but you are
expected to remove these and replace with custom content.
1. Install Docker or Podman.  Note that instructions are written for using
Docker currently, but use of Podman is possible.
1. Customize .env to point to a different host if you are running this from
somewhere other than localhost to start.
1. If your network requires special client certificates to access the internet,
update Dockerfile to install these certificates.
1. Run `./setup.sh`.  This wil download and build required Docker images based
on the `docker-compose.yml` file.
1. Run `./run.sh`.  This will launch the
application.  By default you can access this from `http://localhost`.  It may take
a little while for the site to come up.  You can view progress using `docker compose logs --follow`.

Once you have successfully launched the default platform template on your local machine, you are ready to
customize it to include the relevant Test Kits and content for your platform.

## Customizing the platform
* Adding Test Kits
* Updating non-test kit content
* Configuring the Platform

### Adding Test Kits
* Add Test Kit gem to Gemfile.  This preferably is published on RubyGems, but
  this could also point to a local file or GitHub repo.  See Gemfile
  documentation for information on publishing content to RubyGems.org.
* Update /lib/inferno_platform_template.rb to include your test kit in the running Inferno application.
* Currently, Test Kit gems do not quite have enough information to populate the
  Test Kit list page (/test-kits/) nor the Test Kit details page (e.g. /test-kits/us-core/).  Therefore, you have to add in custom content.
  * In _test_kits, copy us-core.md to `your-test-kit.md`
  * Update the content and metadata as needed
  * Run `./setup.sh`, which includes a command to rebuild the platforms front end.  Changes are reflected in `_site`
* Add your IG package to lib/inferno_platform_template/igs directory.  This will preload your IG into the validator service
* Note that all IGs will be loaded into single instance of the validator currently.
* Also note that we have an improved version of the validator service that will allow you to avoid this step. This will be incorporated into the template soon.
* Update nginx.conf to override the 'suite' landing page with the 'test kit landing page'.  While not technically needed, this will ensure
  that users that navigate out of a test session will be put on a test kit page.

## Updating non-test Kit content (e.g. news, etc)
* First, you should install Ruby to make changes to the platform static content. While not technically required,
  rerunning `./setup.sh` and `./run.sh` will be slow
* This will allow you to rebuild using Jekyll locally, and serve a copy of the static files
* You can run `bundle exec rake web:serve` to generate the files and view them at `http://localhost:4000`
* Alternatively, you can run `docker compose run inferno_web bundle exec rake web:generate` to only generate the files
* All static platform content is contained in `web`, and when generated is placed in `_site`. You
  not need to commit _site content to github as it is regenerated at build time in `./setup.sh`
* This uses a standard Jekyll setup, so you are free to leverage the capabilities of Jekyll for your site
* By default, the site is set up like inferno.healthit.gov, but you are free to change how you would like
* `/suites` (by default) is a special directory handled by Inferno's Suite Running application
* You have limited customization abilities for content under `/suites`, but you can adjust the content in the Banner. This is located in `/config/banner.html.erb`
* This is for historic reasons -- we would like to unify this with the Jekyll generation in a future update.

## Updating configuration
* Updating host
   * update .env file to point to your domain
   * By default, this site is served over ssl using a self-signed cert.  You can update the docker-compose.yml
     file to mount a cert for your site
* Update data retention policy.
   * Note that by default, this is set up to periodically remove data because test sessions can get quite large.
     A notice in the user interface itself prominently notes this.  You can alter this within /lib/inferno_platform_template/delete_old_sessions.rb


## License

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at
```
http://www.apache.org/licenses/LICENSE-2.0
```
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.