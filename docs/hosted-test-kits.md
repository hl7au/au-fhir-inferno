# Hosted test kits

Which test kits this platform hosts, where each one is declared, and how each is kept
current. A suite is hosted only when a gem that defines it is loaded at boot, and Inferno
loads `lib/*.rb`, so `lib/inferno_platform_template.rb` is the list that matters. A kit
that arrives only because another kit happens to require it is hosted by accident, and
the next release of that other kit can remove it without any change here.

## The kits

| Kit | Gem and where it is declared | Suites (ids) | Page | Maintained by |
| --- | --- | --- | --- | --- |
| AU Core | `au_core_test_kit`, `Gemfile` / `Gemfile.dev` / `Gemfile.ci-build` | `au_core_v100`, `au_core_v200`, `au_core_v210_draft`, `au_core_v300_ballot1` (and `au_core_ci_build` on ci-build) | `web/_test_kits/au-core.md` | hl7au/au-fhir-core-inferno |
| AU PS | `au_ps_inferno`, `Gemfile` / `Gemfile.dev` / `Gemfile.ci-build` | `au_ps_v100` (and `au_ps_ci_build` on ci-build) | `web/_test_kits/au-ps.md` | hl7au/au-ps-inferno |
| SMART App Launch | `smart_app_launch_test_kit`, `Gemfile.common` | `smart`, `smart_stu2`, `smart_stu2_2`, `smart_access_brands` | `web/_test_kits/smart-app-launch.md` | inferno-framework/smart-app-launch-test-kit |

Two further suites come with the AU Core kit rather than being declared here: `validations`
(the AU Core kit's validation suite, built on `validation_test_kit`) and `tls`
(`tls_test_kit`, also required by the SMART kit). They have no kit page.

`spec/inferno_deployment/hosted_suites_spec.rb` boots the app and fails if any released
suite listed on a kit page is not registered, so a kit bump that drops or renames a suite
fails `quality-control` instead of reaching production.

## SMART App Launch

### Why it is hosted

Production hosted the four SMART suites without anyone choosing to: `au_core_test_kit` 1.4.6 required `smart_app_launch_test_kit` from a
generated suite, which registered every SMART suite. The regenerated suites in 1.4.7 no
longer require it, so the first image built on 1.4.7 dropped them silently (found in the
review of promotion PR #223). They are now hosted on purpose:

- Vendors with SMART-enabled authorisation servers can test standalone launch, EHR
  launch, Backend Services and token introspection on an Australian host at HL7 AU
  events, instead of finding a US-hosted instance.
- AU Core says systems SHOULD support SMART App Launch for authorisation, and the AU Core
  kit takes a bearer token rather than launching itself, so this kit is how a server's
  token issuance is tested.

The kit is hosted unchanged from upstream. Problems with a test go to the Inferno team's
repository, not to the HL7 AU kits.

### How it is kept current

- **Declared in `Gemfile.common`**, so dev, ci-build and production run the same release:
  the SMART kit does not track IG CI builds, and staging should show what production will
  host.
- **Pinned with `~> 0.4.6`** and locked in all three lockfiles. Relock all three after
  changing it: `bundle lock`, then `BUNDLE_GEMFILE=Gemfile.dev bundle lock` and
  `BUNDLE_GEMFILE=Gemfile.ci-build bundle lock`. `quality-control` installs each one
  frozen.
- **Held below the latest release.** Every release from 0.5.0 on depends on
  `tls_test_kit` 0.3 or 1.x, while every `au_core_test_kit` release so far (to 1.4.7)
  depends on `tls_test_kit ~> 0.2.0`, so bundler cannot resolve a newer SMART kit next to
  the AU Core kit. The latest SMART release, 1.0.3, needs `inferno_core ~> 1.4, >= 1.4.2`,
  which the platform's 1.4.4 already satisfies; the AU Core kit's `tls_test_kit`
  constraint is the only blocker. When an AU Core kit release relaxes it, move the SMART
  kit to the latest release that fits the `inferno_core` pin and update the `version` on
  its page.
- **Check on every bump:** a participant who has registered Inferno's URIs on their
  authorisation server depends on the suite ids and the redirect, launch and JWKS paths
  (`/custom/<suite id>/...`). They are the same in 0.4.6 and 1.0.3. 1.0.3 also adds a
  SMART client suite (`smart_client_stu2_2`), which the `smart` prefix in `KIT_PAGES`
  already redirects; add it to the kit page or decide not to advertise it. Read the
  upstream release notes before moving across a minor or major version.
- **Version on the page:** `version:` in `web/_test_kits/smart-app-launch.md` is
  hand-maintained, like the other kit pages; bump it with the gem.
