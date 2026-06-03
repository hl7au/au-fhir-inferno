# Bug: `MSChecker#find_slice_via_discriminator` fails with `undefined local variable or method 'metadata'`

**Affects:** `inferno_suite_generator` gem  
**Upstream repo:** https://github.com/hl7au/inferno_suite_generator  
**Triggered by:** `au_core_test_kit >= 1.4.1`

---

## Error

```
Error: undefined local variable or method `metadata' for an instance of InfernoSuiteGenerator::MSChecker

/usr/local/bundle/bundler/gems/inferno_suite_generator-b7d359027273/lib/inferno_suite_generator/utils/fhir_resource_navigation.rb:149:in `find_slice_via_discriminator'
```

## Root cause

`MSChecker#initialize` stores the group metadata in `@metadata` but the class has no `attr_reader :metadata`:

```ruby
# ms_checker.rb
def initialize(group_metadata, config = {})
  @metadata = group_metadata   # instance variable set here
  @config = config
end
```

`MSChecker` includes `FHIRResourceNavigation`, and that module's `find_slice_via_discriminator` calls `metadata` as a method call (not `@metadata`):

```ruby
# fhir_resource_navigation.rb:149
def find_slice_via_discriminator(element, property)
  return nil unless metadata.present?          # <-- method call, not @metadata
  ...
  slice_configs = metadata.must_supports&.[](:slices)
  ...
end
```

Because `MSChecker` has no `attr_reader :metadata`, Ruby raises `NoMethodError` instead of reading `@metadata`.

`FHIRResourceNavigation` was originally designed to be mixed into Inferno test group classes, which provide a `metadata` method from the test framework. When the module was re-used in `MSChecker` (a plain Ruby class), the `metadata` accessor was not added to `MSChecker` to match.

## Fix required (one line in `inferno_suite_generator`)

In `lib/inferno_suite_generator/test_utils/ms_checker.rb`, add an `attr_reader` for `metadata` (and `config` for consistency):

```ruby
class MSChecker
  include FHIRResourceNavigation
  include Extensions
  include Slices

  attr_reader :metadata, :config   # <-- add this

  def initialize(group_metadata, config = {})
    @metadata = group_metadata
    @config = config
  end
  ...
end
```

## How it was uncovered

Production uses the published gem `au_core_test_kit ~> 1.4.0` which resolves to `1.4.0`. The development environment was updated to use a git ref pointing to `au_core_test_kit 1.4.1`. Version 1.4.1 exercises a slice-checking code path in `MSChecker` that `1.4.0` did not reach, surfacing the missing accessor.

Both environments use `inferno_suite_generator` at the same git ref (`b7d35902`). Production will hit the same error the next time `au_core_test_kit` is updated beyond `1.4.0`.

## Current workaround (au-fhir-inferno)

A monkey-patch is applied at startup in `lib/inferno_platform_template/patches.rb`:

```ruby
require 'inferno_suite_generator/test_utils/ms_checker'

unless InfernoSuiteGenerator::MSChecker.method_defined?(:metadata)
  InfernoSuiteGenerator::MSChecker.attr_reader :metadata
end
```

This file is required in both `config.ru` and `worker.rb`. It should be removed once `inferno_suite_generator` is patched and the Gemfile ref is updated.
