---
layout: test-kit
title: SMART App Launch Test Kit
test_kit_id: smart_app_launch_test_kit
maturity: 1
tags: [ SMART ]
date: 2026-11-21
version: 0.4.6
canonical_url: "http://hl7.org/fhir/smart-app-launch"
logo: /assets/images/icon_logo.png
preview_text: Test the authorisation server behind a FHIR API against SMART App Launch. Inferno acts as a SMART app, launches against your server and checks the discovery document, the authorisation flow and the tokens it gets back.
suites:
  - title: SMART App Launch STU2.2
    id: smart_stu2_2
  - title: SMART App Launch STU2
    id: smart_stu2
  - title: SMART App Launch STU1
    id: smart
  - title: SMART User-access Brands and Endpoints STU2.2
    id: smart_access_brands
sections:
  - title: "What this test kit checks"
    icon: /assets/images/checklist.svg
    content: >
      <p>The STU2 and STU2.2 suites each have four groups. Run the ones your server supports:</p>
      <ul>
        <li><b>Standalone Launch.</b> Discovery (<code>.well-known/smart-configuration</code>), the authorisation code flow started by the app, the token response and its scopes, token refresh, and OpenID Connect when you request an id token.</li>
        <li><b>EHR Launch.</b> The same checks for a launch started from your EHR, which sends Inferno a <code>launch</code> parameter.</li>
        <li><b>Backend Services.</b> The client credentials flow with a signed JWT client assertion, including requests your server must reject.</li>
        <li><b>Token Introspection.</b> Your introspection endpoint reports active and inactive tokens correctly.</li>
      </ul>
      <p>The STU1 suite covers standalone and EHR launch for servers that implement SMART App Launch 1.0.0. The User-access Brands suite retrieves and validates the brands Bundle a server publishes so that apps can show patients where to sign in.</p>
      <p>Open any test in the session to read exactly what it asserts and which part of the specification it comes from.</p>
  - title: "How to run a test"
    icon: /assets/images/rocket_launch.svg
    content: >
      <ol>
        <li>Register Inferno as a client on your authorisation server, using the redirect and launch URIs listed on this page (and the JWKS URL for Backend Services).</li>
        <li>Choose the SMART version your server implements and click <b>Create Test Session</b>. Keep the session URL; it is your record of the run.</li>
        <li>In the left panel choose a group, click <b>Run Tests</b> and enter your FHIR base URL, client id, client secret (for a confidential client) and the scopes to request.</li>
        <li>When Inferno asks, follow the link to sign in and approve access in your own authorisation server. Inferno resumes when your server redirects back to it.</li>
        <li>Open any failed test and read the <b>Messages</b> and <b>Requests</b> tabs. Fix, re-run the same group, repeat.</li>
      </ol>
      <p>See <a href="/guidance/#reading-results">Reading results</a> for what each result state means.</p>
  - title: "Before you start"
    icon: /assets/images/science.svg
    content: >
      <ul>
        <li><b>Use synthetic data and test accounts only.</b> This is a public service. The tokens your server issues during a run are stored in the session, which anyone with the session URL can open.</li>
        <li><b>Your server must be reachable from the internet.</b> Inferno on hl7.org.au calls your discovery, token and introspection endpoints from the internet, so it cannot reach localhost or anything behind a VPN. To test a private server, <a href="https://github.com/inferno-framework/smart-app-launch-test-kit">run the kit locally</a>.</li>
        <li><b>Backend Services uses Inferno's published test key.</b> Register the JWKS URL below with your server. The private key behind it is public in the kit's source, so never trust it outside a test environment.</li>
        <li><b>AU Core and SMART.</b> AU Core says systems SHOULD support SMART App Launch for client authentication and authorisation (<a href="https://hl7.org.au/fhir/core/security.html">AU Core security and privacy</a>). The AU Core kit does not run a SMART launch itself; it takes a bearer token. Use this kit to check how your server issues that token.</li>
      </ul>
  - title: "Feedback and issues"
    icon: /assets/images/feedback.svg
    content: >
      <p>For questions about running this kit at an HL7 AU event, use the <a href="https://chat.fhir.org/#narrow/channel/179173-australia/topic/Inferno.20Test.20Kit.20feedback.20and.20queries">Inferno Test Kit feedback and queries</a> topic on chat.fhir.org and include the session URL.</p>
      <p>The tests themselves are maintained by the Inferno team. Report a problem with a test in <a href="https://github.com/inferno-framework/smart-app-launch-test-kit/issues">inferno-framework/smart-app-launch-test-kit</a>, or ask in the <a href="https://chat.fhir.org/#narrow/channel/179309-inferno">#inferno channel</a>.</p>
  - title: "Source, versions and licence"
    icon: /assets/images/code.svg
    content: >
      <p>Tests <a href="https://hl7.org/fhir/smart-app-launch/1.0.0/">SMART App Launch 1.0.0 (STU1)</a>, <a href="https://hl7.org/fhir/smart-app-launch/STU2/">2.0.0 (STU2)</a> and <a href="https://hl7.org/fhir/smart-app-launch/STU2.2/">2.2.0 (STU2.2)</a>, including <a href="https://hl7.org/fhir/smart-app-launch/STU2.2/brands.html">User-access Brands and Endpoints</a>. See the <a href="https://hl7.org/fhir/smart-app-launch/history.html">specification history</a> for other publications.</p>
      <p>Source: <a href="https://github.com/inferno-framework/smart-app-launch-test-kit">github.com/inferno-framework/smart-app-launch-test-kit</a>, the same kit hosted on <a href="https://inferno.healthit.gov/test-kits/smart-app-launch/">inferno.healthit.gov</a>, released under the <a href="https://www.apache.org/licenses/LICENSE-2.0">Apache License 2.0</a>. HL7 Australia hosts it unchanged so that SMART testing is available on an Australian host at HL7 AU test events. This site may run an older release than inferno.healthit.gov; the version is shown above.</p>
      <p>This is a reference test kit for development and testing. Results are not a statement of compliance; see <a href="/about/#available-test-kits">About</a>.</p>
---

<p><b>Use this kit if you run an authorisation server that issues access tokens for a FHIR API.</b> Inferno acts as a SMART app: it reads your SMART discovery document, launches against your authorisation server, and checks every response along the way, from the authorisation code to the access, refresh and id tokens.</p>
<p>Register these URIs for Inferno on your authorisation server before you start. Each suite has its own, so register the ones for the version you test:</p>
<table class="table">
  <thead><tr><th>Suite</th><th>Redirect URI</th><th>Launch URI (EHR launch)</th></tr></thead>
  <tbody>
    <tr><td>STU2.2</td><td><code>{{ site.inferno_host }}/suites/custom/smart_stu2_2/redirect</code></td><td><code>{{ site.inferno_host }}/suites/custom/smart_stu2_2/launch</code></td></tr>
    <tr><td>STU2</td><td><code>{{ site.inferno_host }}/suites/custom/smart_stu2/redirect</code></td><td><code>{{ site.inferno_host }}/suites/custom/smart_stu2/launch</code></td></tr>
    <tr><td>STU1</td><td><code>{{ site.inferno_host }}/suites/custom/smart/redirect</code></td><td><code>{{ site.inferno_host }}/suites/custom/smart/launch</code></td></tr>
  </tbody>
</table>
<p>For Backend Services, register Inferno's JWKS URL: <code>{{ site.inferno_host }}/suites/custom/smart_stu2_2/.well-known/jwks.json</code> (STU2.2) or <code>{{ site.inferno_host }}/suites/custom/smart_stu2/.well-known/jwks.json</code> (STU2). The session description repeats these URIs.</p>
