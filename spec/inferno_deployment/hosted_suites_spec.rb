# Guards which suites this platform registers, against the suites its site advertises.
#
# A hosted suite can disappear without any change in this repository: the SMART App
# Launch suites were registered only because au_core_test_kit 1.4.6 required
# smart_app_launch_test_kit, and its 1.4.7 release stopped doing so. Nothing failed; the
# suites were simply gone from the next image. These examples boot Inferno the way the
# app does (spec_helper loads lib/*.rb) and read the repository it serves
# /api/test_suites from, so a kit bump that drops or renames a suite fails here instead of
# in production.
require 'yaml'

RSpec.describe 'Suites hosted by the platform' do
  let(:registered_ids) { Inferno::Repositories::TestSuites.new.all.map(&:id) }

  kit_files = Dir[File.expand_path('../../web/_test_kits/*.md', __dir__)]

  kit_files.each do |kit_file|
    front_matter = YAML.safe_load(File.read(kit_file).split(/^---\s*$/)[1], permitted_classes: [Date])

    # CI-build suites register only where INFERNO_CI_BUILD_SUITES is 'true' (see
    # docs/ci-build-environment.md), which the test environment does not set.
    released = (front_matter['suites'] || []).reject { |suite| suite['ci_build'] }

    released.each do |suite|
      suite_id = suite['id'].to_s.strip

      it "registers #{suite_id}, advertised on #{File.basename(kit_file)}" do
        expect(registered_ids).to include(suite_id)
      end
    end
  end

  it 'registers the SMART App Launch suites from the version the platform pins' do
    smart_ids = ['smart', 'smart_stu2', 'smart_stu2_2', 'smart_access_brands']
    suites = Inferno::Repositories::TestSuites.new.all.select { |suite| smart_ids.include?(suite.id) }

    expect(suites.map(&:id)).to match_array(smart_ids)
    expect(suites.map(&:version).uniq).to eq([SMARTAppLaunch::VERSION])
  end
end
