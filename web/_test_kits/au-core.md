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
  - title: AU Core v1.1.0-preview
    id: au_core_v110_preview
  - title: AU Core v2.0.0-draft
    id: au_core_v200_draft
  - title: AU Core v2.0.0-ballot
    id: au_core_v200_ballot
---

The AU Core Test Kit validates the conformance of a server implementation to a specific version of the AU Core IG.

<!-- break -->

This test kit is open source and freely available for use or adoption by the health IT community including EHR vendors, health app developers, and testing labs. It is built using the [Inferno Framework](https://inferno-framework.github.io/inferno-core/). The Inferno Framework is designed for reuse and aims to make it easier to build test kits for any FHIR-based data exchange. 

## Status

The AU Core Test Kit is actively developed and regularly updated. The test kit currently tests the following requirements:

* Support for Capability Statement
* Support for all AU Core Profiles
* Searches required for each resource
* Support for Must Support Elements
* Profile Validation
* Reference Validation

See the test descriptions within the test kit for detail on the specific validations performed as part of testing these requirements.

## Repository

The AU Core Test Kit GitHub repository can be found [here](https://github.com/hl7au/au-fhir-core-inferno).

## Providing Feedback and Reporting Issues

We welcome feedback on the tests, including but not limited to the following areas:

* Validation logic, such as potential bugs, lax checks, and unexpected failures.
* Requirements coverage, such as requirements that have been missed, tests that necessitate features that the IG does not require, or other issues with the interpretation of the IG’s requirements.
* User experience, such as confusing or missing information in the test UI.

Please report any issues with this set of tests in the [issues section](https://github.com/hl7au/au-fhir-core-inferno/issues) of the repository.

Please read [this README](https://github.com/hl7au/au-fhir-core-inferno?tab=readme-ov-file#contributing-to-inferno-and-reporting-issues) section before providing feedback and reporting issues.

