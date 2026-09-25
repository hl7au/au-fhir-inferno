require_relative '../../lib/inferno_platform_template/feedback_links'

RSpec.describe InfernoPlatformTemplate::FeedbackLinks do
  Suite = Struct.new(:id, :links)

  it 'puts feedback with the existing AU suite links and leaves other suites alone' do
    core = Suite.new('au_core_v200', [
      { label: 'Report Issue', url: 'https://example.test/issues' },
      { label: 'Source Code', url: 'https://example.test/source' }
    ])
    ps = Suite.new('au_ps_v100', [])
    other = Suite.new('smart_app_launch', [{ label: 'Report Issue', url: 'https://example.test/other' }])

    described_class.apply!([core, ps, other])
    described_class.apply!([core, ps, other])

    expect(core.links).to eq([
      { label: 'Give feedback', url: '/feedback/' },
      { label: 'Source Code', url: 'https://example.test/source' }
    ])
    expect(ps.links).to eq([{ label: 'Give feedback', url: '/feedback/' }])
    expect(other.links).to eq([{ label: 'Report Issue', url: 'https://example.test/other' }])
  end
end
