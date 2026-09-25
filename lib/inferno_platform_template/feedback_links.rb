# Configure the link list that Inferno Core renders in each suite footer.
# The platform owns the feedback intake, while the kit repositories remain
# reachable from their test kit pages and the footer's source link.
module InfernoPlatformTemplate
  module FeedbackLinks
    FEEDBACK_LINK = { label: 'Give feedback', url: '/feedback/' }.freeze

    def self.apply!(suites = Inferno::Repositories::TestSuites.new.all)
      suites.each do |suite|
        next unless suite.id.to_s.match?(/\Aau_(?:core|ps)_/)

        links = suite.links
        links.reject! { |link| ['Report Issue', FEEDBACK_LINK[:label]].include?(link[:label]) }
        links.unshift(FEEDBACK_LINK.dup)
      end
    end
  end
end
