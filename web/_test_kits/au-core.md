---
layout: test-kit
title: AU Core Test Kit
test_kit_id: au_core_test_kit
maturity: 1
tags: [ AU ]
date: 2026-09-10
version: 1.4.6
canonical_url: "http://hl7.org.au/fhir/core"
logo: /assets/images/au-core-logo.png
preview_text: Check that a FHIR server's API conforms to AU Core. Inferno queries your server the way an AU Core client would and validates every resource it gets back.
suites:
  - title: AU Core v3.0.0-ballot1
    id: au_core_v300_ballot1
  - title: AU Core v2.0.0
    id: au_core_v200
  - title: AU Core v1.0.0
    id: au_core_v100
sections:
  - title: "What this test kit checks"
    icon: /assets/images/checklist.svg
    content: >
      <p>For each AU Core profile (Patient, Observation vital signs and results, AllergyIntolerance, Condition, Encounter, Immunization, MedicationRequest, MedicationStatement, Procedure, RelatedPerson, HealthcareService, Location, Organization, Practitioner, PractitionerRole) the kit runs the same sequence:</p>
      <ul>
        <li><b>Capability Statement.</b> Your server is reachable over TLS, is FHIR R4, supports JSON, and declares Patient plus at least one other AU Core resource.</li>
        <li><b>Searches.</b> Every search the IG marks SHALL, SHOULD or MAY is executed, and each returned resource is checked against the parameters you searched by.</li>
        <li><b>Must Support.</b> Across the resources returned, every Must Support element appears at least once. Supply several patient ids so that, between them, all elements are populated.</li>
        <li><b>Profile validation.</b> Every resource is validated against its AU Core profile, including terminology bindings, using the HL7 AU terminology server.</li>
        <li><b>References.</b> Must Support references resolve to a readable resource on your server.</li>
        <li><b>Missing data.</b> Suppressed or unknown data is represented the way AU Core requires.</li>
      </ul>
      <p>Open any test in the session to read exactly what it asserts.</p>
  - title: "How to run a test"
    icon: /assets/images/rocket_launch.svg
    content: >
      <ol>
        <li>Pick the IG version your server implements and click <b>Create Test Session</b>. The session URL is shareable; keep it.</li>
        <li>Click <b>Run Tests</b> on the top-level group to run everything, or on a single resource group to test one profile at a time.</li>
        <li>Enter your <b>FHIR endpoint</b> and a comma-separated list of <b>Patient IDs</b>. Add ids for HealthcareService, Location, Organization, Practitioner and PractitionerRole if you want those groups to run against known records. Add a bearer token or a custom header if your server needs one.</li>
        <li>Open any failed test. The <b>Messages</b> tab shows validator output; the <b>Requests</b> tab shows the exact HTTP request Inferno sent and what your server returned.</li>
      </ol>
      <p>Fix, re-run just that group, repeat. See <a href="/guidance/#reading-results">Reading results</a> for what pass, fail, skip and omit mean.</p>
  - title: "Before you start"
    icon: /assets/images/science.svg
    content: >
      <ul>
        <li><b>Try it first against the public test server.</b> The inputs default to <code>https://fhir.hl7.org.au/aucore/fhir/DEFAULT</code> with sample patient ids. Run once with the defaults to see what a passing session looks like, then swap in your own endpoint.</li>
        <li><b>Your server must be reachable from the internet</b> over HTTPS. Inferno on hl7.org.au cannot reach localhost or a VPN. To test a private server, <a href="/guidance/#run-locally">run the kit locally</a>.</li>
        <li><b>Load synthetic data first.</b> The <a href="https://github.com/hl7au/au-fhir-test-data">HL7 AU FHIR test data</a> repository has AU Core patients designed to cover every Must Support element. Never point this service at real patient data.</li>
        <li><b>Expect a full run to take several minutes.</b> Each profile runs many searches plus validation. Running a single resource group is much faster while you iterate.</li>
      </ul>
  - title: "Feedback and issues"
    icon: /assets/images/feedback.svg
    content: >
      <p>If a test fails and you believe your server is right, or a check is missing, tell us. The fastest route is the <a href="https://chat.fhir.org/#narrow/channel/179173-australia/topic/Inferno.20Test.20Kit.20feedback.20and.20queries">Inferno Test Kit feedback and queries</a> topic on chat.fhir.org. Include the session URL.</p>
      <p>For bugs and requests open an issue in <a href="https://github.com/hl7au/au-fhir-core-inferno/issues">hl7au/au-fhir-core-inferno</a>. The <a href="https://github.com/hl7au/au-fhir-core-inferno#contributing-to-inferno-and-reporting-issues">README</a> explains what to include.</p>
  - title: "Source, versions and licence"
    icon: /assets/images/code.svg
    content: >
      <p>Tests <a href="https://hl7.org.au/fhir/core/">AU Core</a> v1.0.0, v2.0.0 and v3.0.0-ballot1. See the <a href="https://hl7.org.au/fhir/core/history.html">IG history</a> for publication status. The tests are generated from the IG package with the <a href="https://github.com/hl7au/inferno_suite_generator">Inferno Suite Generator</a>, so a new IG release can be turned into a new suite quickly.</p>
      <p>Source: <a href="https://github.com/hl7au/au-fhir-core-inferno">github.com/hl7au/au-fhir-core-inferno</a>, built on the <a href="https://inferno-framework.github.io">Inferno Framework</a> and released under the <a href="https://www.apache.org/licenses/LICENSE-2.0">Apache License 2.0</a>. Free to run locally or adopt in your own test programme.</p>
      <p>This is a reference test kit, not a certification. Passing here does not confer conformance status; see <a href="/about/#available-test-kits">About</a>.</p>
---

<p><b>Use this kit if you run a FHIR server that other systems will query for AU Core data.</b> Inferno acts as an AU Core client: it reads your CapabilityStatement, runs the searches the IG requires for each profile, and validates every resource that comes back against the AU Core profiles and terminology.</p>
<p>You need a FHIR endpoint that is reachable from the internet and the ids of a few test patients on it. Everything else is optional.</p>
