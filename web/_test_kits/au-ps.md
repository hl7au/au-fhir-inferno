---
layout: test-kit
title: AU PS Test Kit
test_kit_id: au_ps_suite
tags: [ AU ]
date: 2025-08-29
version: 0.1.1.pre
canonical_url: "http://hl7.org.au/fhir/ps"
logo: /assets/images/au-core-logo.png
preview_text: The AU PS Test Kit validates the conformance of a server implementation to a specific version of the AU PS IG
suites:
  - title: AU PS 0.4.0-draft
    id: au_ps_suite
sections:
  - title: "Status"
    icon: /assets/images/checklist.svg
    content: >
      <p>The AU PS Test Kit is actively developed and regularly updated. The test kit currently tests the following requirements:</p>
      <ul>
        <li>Validity of the AU Patient Summary document bundle profile</li>
      </ul>
      <p>See the test descriptions within the test kit for detail on the specific validations performed as part of testing these requirements.</p>
  - title: "Repository"
    icon: /assets/images/code.svg
    content: >
      The AU PS Inferno Test Kit GitHub repository can be found <a href="https://github.com/hl7au/au-ps-inferno">here</a>.
  - title: "Providing Feedback and Reporting Issues"
    icon: /assets/images/feedback.svg
    content: >
      <p>We welcome feedback on the tests, including but not limited to the following areas:</p>
      <ul>
      <li>Validation logic, such as potential bugs, lax checks, and unexpected failures.</li>
      <li>Requirements coverage, such as requirements that have been missed, tests that necessitate features that the IG does not require, or other issues with the interpretation of the IG’s requirements.</li>
      <li>User experience, such as confusing or missing information in the test UI.</li>
      </ul>
      <p>Please report any issues with this set of tests in the <a href="https://github.com/hl7au/au-ps-inferno/issues">issues section</a> of the repository.</p>
      <p>Please read this <a href="https://github.com/hl7au/au-ps-inferno/issues">README</a> section before providing feedback and reporting issues.</p>
---

<p>The AU PS Test Kit validates the content of patient summary documents with respect to the AU Patient Summary FHIR Implementation Guide specification.</p>
<p>This test kit is open source and freely available for use or adoption by the health IT community, including EHR vendors, health app developers, and testing labs. It is built using the <a href="https://inferno-framework.github.io">Inferno Framework</a>. The Inferno Framework is designed for reuse and aims to make it easier to build test kits for any FHIR-based data exchange.</p>
<p>This test kit is based on the <a href="https://build.fhir.org/ig/hl7au/au-fhir-ps/index.html">AU PS Implementation Guide</a>, which defines the base set of profiles and requirements for Australian FHIR implementations. For detailed information on IG versions, change history, and publication status, see the <a href="https://hl7.org.au/fhir/ps/history.html">AU PS IG History Page</a>.</p>
<p>This project is licensed under the <a href="https://www.apache.org/licenses/LICENSE-2.0">Apache License, Version 2.0</a>.</p>
