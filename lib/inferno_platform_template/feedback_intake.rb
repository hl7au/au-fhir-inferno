# A small same-origin intake for public community feedback. The GitHub credential
# stays in the web process; the browser never receives it or the raw issue API.
require 'json'
require 'digest'
require 'net/http'
require 'redis-client'
require 'time'

module InfernoPlatformTemplate
  class FeedbackIntake
    PATH = '/feedback/api/reports'.freeze
    PREVIEW_PATH = '/feedback/api/preview'.freeze
    CONFIG_PATH = '/feedback/api/config'.freeze
    MAX_BODY_BYTES = 4096
    REFERENCE = /\A[A-Za-z0-9_-]{1,160}\z/
    VERSION = /\A[A-Za-z0-9_.-]{1,80}\z/
    OUTCOMES = %w[pass fail error skip omit other].freeze
    SESSION_URL = %r{https?://\S*/suites/(?:test_sessions/|[A-Za-z0-9_-]+/)[A-Za-z0-9_-]+}i

    def initialize(app, token: ENV['FEEDBACK_GITHUB_TOKEN'], issue_client: nil, limiter: nil)
      @app = app
      @issue_client = issue_client || GitHubIssueClient.new(token) unless token.to_s.empty?
      @limiter = limiter || RedisLimiter.new if @issue_client
    end

    def call(env)
      request = Rack::Request.new(env)
      return json(200, enabled: !@issue_client.nil?) if request.get? && request.path == CONFIG_PATH
      return @app.call(env) unless [PATH, PREVIEW_PATH].include?(request.path)
      return json(405, error: 'Method not allowed') unless request.post?
      return json(503, error: 'Anonymous submission is not configured here yet.') if request.path == PATH && !@issue_client
      return json(403, error: 'Open this form on the Inferno site to submit feedback.') unless same_origin?(request)
      return json(415, error: 'Expected JSON') unless request.media_type == 'application/json'

      raw = request.body.read(MAX_BODY_BYTES + 1)
      return json(413, error: 'Feedback is too long.') if raw.bytesize > MAX_BODY_BYTES

      data = JSON.parse(raw)
      report = build_report(data)
      return json(200, report.slice(:title, :context, :expected, :actual, :reporter)) if request.path == PREVIEW_PATH

      return json(429, error: 'Too many reports just now. Please try again later.') unless @limiter.allow?(request.ip)

      url = @issue_client.create(title: report[:title], body: report[:body])
      json(201, url: url)
    rescue JSON::ParserError, InvalidReport => e
      json(422, error: e.is_a?(InvalidReport) ? e.message : 'The report could not be read.')
    rescue RedisClient::Error
      json(503, error: 'Feedback intake is temporarily unavailable. Please try again later.')
    rescue GitHubIssueClient::Failure
      json(502, error: 'The issue could not be posted. Please try again later or use GitHub directly.')
    end

    class InvalidReport < StandardError; end

    private

    def same_origin?(request)
      origin = request.get_header('HTTP_ORIGIN')
      origin && origin == request.base_url
    end

    def build_report(data)
      raise InvalidReport, 'The report is incomplete.' unless data.is_a?(Hash)
      raise InvalidReport, 'The report is incomplete.' unless data['website'].to_s.empty?

      kind = data['type']
      raise InvalidReport, 'Choose a feedback type.' unless %w[result general].include?(kind)

      expected = prose(data['expected'])
      actual = prose(data['actual'])
      raise InvalidReport, 'Describe what you expected and what happened.' if expected.empty? || actual.empty?
      raise InvalidReport, 'Remove the full session URL before submitting.' if [expected, actual].any? { |v| v.match?(SESSION_URL) }

      session_id = reference(data['sessionId'], optional: true)
      if session_id && [expected, actual].any? { |v| v.include?(session_id) }
        raise InvalidReport, 'Remove the session ID before submitting.'
      end
      suite_id = reference(data['suiteId'], optional: kind == 'general')
      test_id = reference(data['testId'], optional: kind == 'general')
      outcome = data['outcome'].to_s
      if kind == 'result' && !OUTCOMES.include?(outcome)
        raise InvalidReport, 'Choose a result outcome.'
      end

      identity = data['identity']
      raise InvalidReport, 'Choose how your report will be attributed.' unless %w[anonymous named].include?(identity)
      name = plain(data['name'], 100)
      email = plain(data['email'], 254, neutralize_mentions: false)
      if identity == 'named'
        raise InvalidReport, 'Enter a name or contact email.' if name.empty? && email.empty?
        raise InvalidReport, 'Confirm that your contact details will be public.' unless data['publishContact'] == true
        raise InvalidReport, 'Enter a valid contact email.' if !email.empty? && !email.match?(URI::MailTo::EMAIL_REGEXP)
      else
        name = ''
        email = ''
      end

      kit = suite_id.to_s.start_with?('au_core_') ? 'AU Core Test Kit' :
        (suite_id.to_s.start_with?('au_ps_') ? 'AU PS Test Kit' : 'Not specified')
      test_name = plain(data['testName'], 150)
      kit_version = version(data['kitVersion'])
      suite_version = version(data['suiteVersion'])
      result_time = timestamp(data['resultTime'])
      feedback_time = timestamp(data['feedbackTime'])
      raise InvalidReport, 'The feedback time is invalid. Reload the form and try again.' unless feedback_time
      title = kind == 'result' ? "AU Inferno result feedback: #{(test_name.empty? ? test_id : test_name)[0, 120]}" :
        'AU Inferno general feedback'
      context = [
        "Test kit: #{kit}",
        "Test kit version: #{kit_version || 'Not available'}",
        "Suite ID: #{suite_id || 'Not specified'}",
        "Suite version: #{suite_version || 'Not available'}",
        "Test: #{kind == 'result' ? (test_name.empty? ? 'Not available' : test_name) : 'Not applicable'}",
        "Test ID: #{kind == 'result' ? test_id : 'Not applicable'}",
        "Outcome: #{kind == 'result' ? outcome : 'Not applicable'}",
        "Result time (UTC): #{kind == 'result' ? (result_time || 'Not available') : 'Not applicable'}",
        "Feedback time (UTC): #{feedback_time}",
        "Feedback reference: #{session_id ? "fb-#{Digest::SHA256.hexdigest("au-inferno-feedback:v1:#{session_id}")[0, 24]}" : 'Not available'}"
      ]
      reporter = identity == 'anonymous' ? 'Anonymous community member' :
        [name, (email.empty? ? nil : "Contact email (public): #{email}")].compact.join("\n")
      body = [
        '> Submitted through the AU Inferno feedback form. Reporter text has not been independently verified.',
        "**Feedback type:** #{kind == 'result' ? 'Problem with a test result' : 'General feedback'}",
        "**Reporter:** #{reporter}",
        "## Test context\n\n```text\n#{context.join("\n")}\n```",
        "## What I expected\n\n#{expected}",
        "## What happened\n\n#{actual}"
      ].join("\n\n")
      { title: title, body: body, context: context.join("\n"), expected: expected, actual: actual, reporter: reporter }
    end

    def reference(value, optional: false)
      return nil if optional && value.to_s.empty?
      raise InvalidReport, 'A suite, test or session reference is invalid.' unless value.is_a?(String) && value.match?(REFERENCE)

      value
    end

    def version(value)
      value.is_a?(String) && value.match?(VERSION) ? value : nil
    end

    def timestamp(value)
      return nil if value.to_s.empty?
      return nil unless value.is_a?(String) && value.length <= 50

      Time.iso8601(value)
      value
    rescue ArgumentError
      nil
    end

    def plain(value, max, neutralize_mentions: true)
      return '' unless value.is_a?(String)
      raise InvalidReport, 'A report field is too long.' if value.length > max

      text = value.gsub(/[\x00-\x1f\x7f`]/, ' ').strip
      neutralize_mentions ? text.gsub('@', "@\u200b") : text
    end

    def prose(value)
      return '' unless value.is_a?(String)
      raise InvalidReport, 'A description is too long.' if value.length > 800

      value.gsub(/\r\n?/, "\n").gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/, '').strip.gsub('@', "@\u200b")
    end

    def json(status, object)
      [status, { 'Content-Type' => 'application/json', 'Cache-Control' => 'no-store',
                 'X-Content-Type-Options' => 'nosniff' }, [JSON.generate(object)]]
    end

    class RedisLimiter
      SCRIPT = <<~LUA.freeze
        local ip_count = redis.call('INCR', KEYS[1])
        if ip_count == 1 then redis.call('EXPIRE', KEYS[1], 7200) end
        local total_count = redis.call('INCR', KEYS[2])
        if total_count == 1 then redis.call('EXPIRE', KEYS[2], 7200) end
        return {ip_count, total_count}
      LUA

      def initialize
        @pool = RedisClient.config(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379')).new_pool(size: 5, timeout: 0.5)
      end

      def allow?(ip)
        bucket = Time.now.to_i / 3600
        source = Digest::SHA256.hexdigest(ip.to_s)[0, 24]
        counts = @pool.with { |redis| redis.call('EVAL', SCRIPT, 2, "feedback:ip:#{source}:#{bucket}", "feedback:all:#{bucket}") }
        counts[0] <= 20 && counts[1] <= 100
      end
    end

    class GitHubIssueClient
      class Failure < StandardError; end

      URL = URI('https://api.github.com/repos/hl7au/au-fhir-inferno/issues')

      def initialize(token)
        @token = token
      end

      def create(title:, body:)
        request = Net::HTTP::Post.new(URL)
        request['Accept'] = 'application/vnd.github+json'
        request['Authorization'] = "Bearer #{@token}"
        request['User-Agent'] = 'au-inferno-feedback'
        request['X-GitHub-Api-Version'] = '2026-03-10'
        request.body = JSON.generate(title: title, body: body)
        response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 3, read_timeout: 8) do |http|
          http.request(request)
        end
        raise Failure unless response.code == '201'

        url = JSON.parse(response.body)['html_url']
        raise Failure unless url.is_a?(String) && url.match?(%r{\Ahttps://github\.com/hl7au/au-fhir-inferno/issues/\d+\z})

        url
      rescue JSON::ParserError, Timeout::Error, SocketError, IOError, SystemCallError
        raise Failure
      end
    end
  end
end
