---
layout: test-kit
title: AU Core Test Kit
test_kit_id: au_core_test_kit
tags: [ AU ]
date: 2025-08-06
version: 1.2.0
canonical_url: "http://hl7.org.au/fhir/core"
logo: /assets/images/au-core-logo.png
preview_text: The AU Core Test Kit validates the conformance of a server implementation to a specific version of the AU Core IG
suites:
  - title: AU Core v1.0.0
    id: au_core_v100
  - title: AU Core v2.0.0-ballot
    id: au_core_v200_ballot
sections:
  - title: "Status"
    icon: /assets/images/checklist.svg
    content: >
      <p>The AU Core Test Kit is actively developed and regularly updated. The test kit currently tests the following requirements:</p>
      <ul>
        <li>Support for Capability Statement</li>
        <li>Support for all AU Core Profiles</li>
        <li>Searches required for each resource</li>
        <li>Support for Must Support Elements</li>
        <li>Profile Validation</li>
        <li>Reference Validation</li>
      </ul>
      <p>See the test descriptions within the test kit for detail on the specific validations performed as part of testing these requirements.</p>
  - title: "Repository"
    icon: /assets/images/code.svg
    content: >
      The AU Core Inferno Test Kit GitHub repository can be found <a href="#">here</a>.
  - title: "Providing Feedback and Reporting Issues"
    icon: /assets/images/feedback.svg
    content: >
      <p>We welcome feedback on the tests, including but not limited to the following areas:</p>
      <ul>
      <li>Validation logic, such as potential bugs, lax checks, and unexpected failures.</li>
      <li>Requirements coverage, such as requirements that have been missed, tests that necessitate features that the IG does not require, or other issues with the interpretation of the IG’s requirements.</li>
      <li>User experience, such as confusing or missing information in the test UI.</li>
      </ul>
      <p>Please report any issues with this set of tests in the <a href="#">issues section</a> of the repository.</p>
      <p>Please read this <a href="#">README</a> section before providing feedback and reporting issues.</p>
---

<p>The AU Core Test Kit validates the conformance of a server implementation to a specific version of the AU Core IG.</p>
<p>This test kit is open source and freely available for use or adoption by the health IT community, including EHR vendors, health app developers, and testing labs. It is built using the <a href="#">Inferno Framework</a>. The Inferno Framework is designed for reuse and aims to make it easier to build test kits for any FHIR-based data exchange.</p>
<p>This test kit is based on the <a href="#">AU Core Implementation Guide</a>, which defines the base set of profiles and requirements for Australian FHIR implementations. For detailed information on IG versions, change history, and publication status, see the <a href="#">AU Core IG History Page</a>.</p>
<p>This project is licensed under the <a href="#">Apache License, Version 2.0</a>.</p>
