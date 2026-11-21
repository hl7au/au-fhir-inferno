require 'au_core_test_kit'
require 'au_ps_inferno'

# Registers the SMART App Launch STU1, STU2, STU2.2 and User-access Brands suites
# (smart, smart_stu2, smart_stu2_2, smart_access_brands). Required here, not left to a
# kit's own requires, so that hosting them is a platform decision: au_core_test_kit 1.4.6
# loaded this gem as a side effect and 1.4.7 does not. See docs/hosted-test-kits.md.
require 'smart_app_launch_test_kit'
