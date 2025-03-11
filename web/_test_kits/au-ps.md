---
layout: test-kit
title: AU PS Test Kit
test_kit_id: au_ps_suite
tags: [ AU ]
date: 2025-03-11
version: 0.1.0-preview
maturity: Low
suites:
  - title: 0.4.0-draft
    id: au_ps_suite
---

The AU PS Test Kit validates the conformance of a server implementation to a specific version of the AU PS IG.

<!-- break -->

This test kit is open source and freely available for use or adoption by the health IT community including EHR vendors, health app developers, and testing labs. It is built using the [Inferno Framework](https://inferno-framework.github.io/inferno-core/). The Inferno Framework is designed for reuse and aims to make it easier to build test kits for any FHIR-based data exchange.

## Status

The AU PS Test Kit is actively developed and regularly updated. The test kit currently tests the following requirements:

* Validity of the resources according to the IG

See the test descriptions within the test kit for detail on the specific validations performed as part of testing these requirements.

## Repository

The AU PS Test Kit GitHub repository can be found [here](https://github.com/hl7au/au-ps-inferno).

## Providing Feedback and Reporting Issues

We welcome feedback on the tests, including but not limited to the following areas:

* Validation logic, such as potential bugs, lax checks, and unexpected failures.
* Requirements coverage, such as requirements that have been missed, tests that necessitate features that the IG does not require, or other issues with the interpretation of the IG’s requirements.
* User experience, such as confusing or missing information in the test UI.

Please report any issues with this set of tests in the [issues section](https://github.com/hl7au/au-ps-inferno/issues) of the repository.

Please read [this README](https://github.com/hl7au/au-fhir-core-inferno?tab=readme-ov-file#contributing-to-inferno-and-reporting-issues) section before providing feedback and reporting issues.

