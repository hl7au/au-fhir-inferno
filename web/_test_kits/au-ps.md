---
layout: test-kit
title: AU PS Test Kit
test_kit_id: au_ps_suite
maturity: 0
tags: [ AU ]
date: 2026-09-10
version: 1.0.1
canonical_url: "http://hl7.org.au/fhir/ps"
logo: /assets/images/au-core-logo.png
preview_text: Check that a patient summary document conforms to the AU Patient Summary (AU PS) implementation guide. Paste a Bundle, fetch one from a server, or have Inferno call $summary on your server.
suites:
  - title: AU PS 1.0.0
    id: au_ps_v100
sections:
  - title: "What this test kit checks"
    icon: /assets/images/checklist.svg
    content: >
      <p>Every path runs the same validation over the patient summary Bundle it obtains:</p>
      <ul>
        <li>The Bundle is a valid AU PS Bundle (and optionally a valid IPS Bundle as well).</li>
        <li>Must Support elements on the Bundle and the Composition are populated when a value is known.</li>
        <li>Mandatory sections (Problems, Allergies and Intolerances, Medication Summary) are present and populated with the right profiles. Recommended and optional sections are checked the same way when present.</li>
        <li>Mandatory sections use an explicit "no known ..." entry rather than <code>emptyReason = nilknown</code>. This is a warning, not a failure.</li>
        <li>The Composition subject, author, custodian and attester resolve to correctly populated AU PS Patient, Practitioner, PractitionerRole, Organization, RelatedPerson or Device resources, including identifier slices such as IHI, Medicare and DVA numbers.</li>
      </ul>
      <p>The server path also checks that your CapabilityStatement declares the AU PS profiles and the IPS operations (<code>$summary</code>, <code>$docref</code>).</p>
      <p>Open any test in the session to read exactly what it asserts and which part of the IG it comes from.</p>
  - title: "How to run a test"
    icon: /assets/images/rocket_launch.svg
    content: >
      <ol>
        <li>Click <b>Create Test Session</b>. Keep the session URL as your record of the run and share it only with trusted reviewers.</li>
        <li>In the left panel choose the group that matches how you want to test (see the three ways above). You do not need to run the whole suite.</li>
        <li>Click <b>Run Tests</b> and fill in the inputs. Only the fields for the path you chose are needed; leave the rest empty.</li>
        <li>Wait for the run to finish, then open any failed test and read the <b>Messages</b> tab. Validator messages point at the exact element in your Bundle.</li>
      </ol>
      <p>Fix, re-run the same group, repeat. See <a href="/guidance/#reading-results">Reading results</a> for what pass, fail, skip and omit mean.</p>
  - title: "Before you start"
    icon: /assets/images/science.svg
    content: >
      <ul>
        <li><b>Use synthetic data only.</b> This is a public service. Do not paste or expose real patient data.</li>
        <li><b>Server paths need a reachable endpoint.</b> Inferno on hl7.org.au calls your server from the internet, so it cannot reach localhost or anything behind a VPN. Use the paste-a-Bundle path for local work, or <a href="/guidance/#run-locally">run the kit locally</a>.</li>
        <li><b>Authentication</b> is optional. Supply a bearer token via OAuth credentials, or a custom header name and value, when the session asks.</li>
        <li><b>Need a sample?</b> The <a href="https://hl7.org.au/fhir/ps/1.0.0/examples.html">AU PS IG examples</a> and the <a href="https://github.com/hl7au/au-fhir-test-data">HL7 AU FHIR test data</a> repository have Bundles you can paste to see what a passing run looks like.</li>
      </ul>
  - title: "Feedback and issues"
    icon: /assets/images/feedback.svg
    content: >
      <p>If a test fails and you believe your Bundle is right, or a check is missing, use the <a href="/feedback/">public feedback flow</a>. From a session page, the Feedback link lets you choose a result and opens a prefilled GitHub issue draft. The issue includes a trace-searchable feedback reference, not your session URL. Please keep patient data, tokens and test payloads out of public issues.</p>
      <p>Maintainers can link accepted test-kit bugs to <a href="https://github.com/hl7au/au-ps-inferno/issues">hl7au/au-ps-inferno</a> for implementation while keeping the community report visible.</p>
  - title: "Source, versions and licence"
    icon: /assets/images/code.svg
    content: >
      <p>Tests <a href="https://hl7.org.au/fhir/ps/1.0.0/">AU PS 1.0.0</a>. See the <a href="https://hl7.org.au/fhir/ps/history.html">IG history</a> for other publications.</p>
      <p>Source: <a href="https://github.com/hl7au/au-ps-inferno">github.com/hl7au/au-ps-inferno</a>, built on the <a href="https://inferno-framework.github.io">Inferno Framework</a> and released under the <a href="https://www.apache.org/licenses/LICENSE-2.0">Apache License 2.0</a>. Free to run locally or adopt in your own test programme.</p>
      <p>This is a reference test kit, not a certification. Passing here does not confer conformance status; see <a href="/about/#available-test-kits">About</a>.</p>
---

<p><b>Use this kit if your system produces or serves an AU Patient Summary document.</b> It validates a patient summary Bundle against the <a href="https://hl7.org.au/fhir/ps/1.0.0/">AU PS 1.0.0</a> implementation guide and tells you exactly which element or section is wrong.</p>
<p>There are three ways to test, pick the one that matches what you have:</p>
<ul>
  <li><b>Paste a Bundle.</b> You have a patient summary document as JSON or XML. No server needed. Choose <i>AU PS Bundle Instance</i>.</li>
  <li><b>Fetch a Bundle from your server.</b> Give Inferno a Bundle URL, or your FHIR base URL and a Bundle id. Choose <i>Retrieve AU PS Bundle</i>.</li>
  <li><b>Generate one with <code>$summary</code>.</b> Your server implements the IPS <code>$summary</code> operation. Give Inferno the base URL and a patient id or identifier. Choose <i>Generate AU PS using IPS $summary</i>.</li>
</ul>
<p>A separate <i>Retrieve Capability Statement</i> group checks that a server advertises AU PS support. Run it alongside either server path.</p>
