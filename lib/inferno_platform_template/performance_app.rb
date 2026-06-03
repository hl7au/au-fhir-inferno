require 'sinatra/base'
require 'json'
require 'sequel'
require 'uri'

module InfernoPlatformTemplate
  class PerformanceApp < Sinatra::Base
    TX_SERVER_URL = ENV.fetch('TX_SERVER_URL', '').freeze
    VALIDATOR_URL = ENV.fetch('FHIR_RESOURCE_VALIDATOR_URL', 'http://validator-api:3500').freeze

    def self.db
      @db ||= if Sequel::DATABASES.any?
                Sequel::DATABASES.first
              else
                Sequel.connect(
                  adapter:  'postgres',
                  host:     ENV.fetch('POSTGRES_HOST', 'localhost'),
                  port:     ENV.fetch('POSTGRES_PORT', '5432').to_i,
                  database: ENV.fetch('POSTGRES_DB', 'inferno'),
                  user:     ENV.fetch('POSTGRES_USER', 'postgres'),
                  password: ENV.fetch('POSTGRES_PASSWORD', '')
                )
              end
    end

    def extract_host(url)
      return nil if url.nil? || url.empty?
      uri = URI.parse(url)
      "#{uri.scheme}://#{uri.host}#{uri.port && ![80, 443].include?(uri.port) ? ":#{uri.port}" : ''}"
    rescue URI::InvalidURIError
      nil
    end

    # ------------------------------------------------------------------
    # JSON API
    # ------------------------------------------------------------------
    get '/test_sessions/:id' do
      content_type :json
      headers 'Access-Control-Allow-Origin' => '*'

      session_id = params[:id]
      db = self.class.db

      halt 503, { error: 'requests table not found' }.to_json unless db.table_exists?(:requests)

      if db.table_exists?(:test_sessions) && db[:test_sessions].where(id: session_id).empty?
        halt 404, { error: 'session not found' }.to_json
      end

      cols        = db[:requests].columns
      has_duration = cols.include?(:duration_ms)
      has_results  = db.table_exists?(:results)
      result_cols  = has_results ? db[:results].columns : []
      has_test_id  = result_cols.include?(:test_id)

      base_query = db[:requests].where(
        Sequel[:requests][:test_session_id] => session_id,
        Sequel[:requests][:direction]       => 'outgoing'
      )

      rows = if has_results && has_test_id
               base_query
                 .left_join(:results, { id: Sequel[:requests][:result_id] }, table_alias: :r)
                 .select(
                   Sequel[:requests][:id],
                   Sequel[:requests][:url],
                   Sequel[:requests][:status],
                   Sequel[:requests][:created_at],
                   Sequel[:requests][:result_id],
                   *(has_duration ? [Sequel[:requests][:duration_ms]] : []),
                   Sequel[:r][:test_id]
                 )
                 .order(Sequel[:requests][:created_at])
                 .all
             else
               base_query
                 .select(*[
                   :id, :url, :status, :created_at, :result_id,
                   (has_duration ? :duration_ms : nil)
                 ].compact)
                 .order(:created_at)
                 .all
             end

      timed_count = 0
      fhir_ms     = 0
      by_server   = {}

      requests_out = rows.map do |r|
        host = extract_host(r[:url])
        ms   = r[:duration_ms]
        if ms
          timed_count += 1
          fhir_ms     += ms
          if host
            by_server[host] ||= { count: 0, total_ms: 0 }
            by_server[host][:count]    += 1
            by_server[host][:total_ms] += ms
          end
        end
        {
          url:         r[:url],
          status:      r[:status],
          duration_ms: ms,
          host:        host,
          test_id:     r[:test_id],
          created_at:  r[:created_at]&.iso8601
        }
      end

      by_server_sorted = by_server.sort_by { |_, v| -v[:total_ms] }
        .map { |host, v| { host: host, count: v[:count], total_ms: v[:total_ms] } }

      # Validator timing
      validator_ms         = 0
      validator_calls      = 0
      has_validator_timing = db.table_exists?(:validator_timing)
      vt_rows              = []
      if has_validator_timing
        vt_rows        = db[:validator_timing].where(test_session_id: session_id).all
        validator_calls = vt_rows.size
        validator_ms    = vt_rows.sum { |r| r[:duration_ms] || 0 }
      end

      # Session timing
      session_started_at = nil
      session_ended_at   = nil

      if db.table_exists?(:test_sessions)
        ts = db[:test_sessions].where(id: session_id).select(:created_at).first
        session_started_at = ts&.[](:created_at)
      end

      if has_results
        lr = db[:results].where(test_session_id: session_id)
               .order(Sequel.desc(:created_at)).select(:created_at).first
        session_ended_at = lr&.[](:created_at)
      end

      # Fallback: derive from requests / validator_timing timestamps
      if session_started_at.nil?
        all_times = rows.map { |r| r[:created_at] }.compact
        all_times += vt_rows.map { |r| r[:created_at] }.compact
        session_started_at = all_times.min
      end

      session_duration_ms = nil
      if session_started_at && session_ended_at
        diff = session_ended_at.to_time - session_started_at.to_time
        session_duration_ms = (diff * 1000).to_i if diff > 0
      end

      {
        session_id:           session_id,
        session_started_at:   session_started_at&.iso8601,
        session_ended_at:     session_ended_at&.iso8601,
        session_duration_ms:  session_duration_ms,
        tx_server_url:        TX_SERVER_URL,
        validator_url:        VALIDATOR_URL,
        total_requests:       rows.size,
        requests_with_timing: timed_count,
        has_duration_column:  has_duration,
        has_validator_timing: has_validator_timing,
        summary: {
          fhir_ms:         fhir_ms,
          validator_ms:    validator_ms,
          fhir_requests:   rows.size,
          validator_calls: validator_calls,
          by_server:       by_server_sorted
        },
        requests: requests_out
      }.to_json
    end

    # ------------------------------------------------------------------
    # HTML performance page
    # ------------------------------------------------------------------
    get '/' do
      content_type :html
      PERFORMANCE_HTML
    end

    PERFORMANCE_HTML = <<~'HTML'
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Performance Analysis · Inferno</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>
          :root {
            --c-primary:  #2C3E50;
            --c-accent:   #D94A2A;
            --c-link:     #316DB1;
            --c-fhir:     #316DB1;
            --c-val:      #059669;
            --c-border:   #E5E7EB;
            --c-bg:       #F2F2F2;
            --c-card:     #ffffff;
            --c-text:     #2C3E50;
            --c-muted:    #6C757D;
            --c-dark:     #1F2937;
            --r-card:     12px;
            --font:       'Inter', system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
          }
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: var(--font);
            background: var(--c-bg);
            color: var(--c-text);
            -webkit-font-smoothing: antialiased;
            min-height: 100vh;
          }

          /* ── Site header ────────────────────────────── */
          .site-header {
            background: rgb(248,249,250);
            border-bottom: 1px solid var(--c-border);
            height: 60px;
            display: flex;
            align-items: center;
            padding: 0 24px;
            position: sticky;
            top: 0;
            z-index: 100;
          }
          .site-header-inner {
            display: flex;
            justify-content: space-between;
            align-items: center;
            width: 100%;
            max-width: 1200px;
            margin: 0 auto;
          }
          .site-logo {
            font-size: 1.4rem;
            font-weight: 450;
            color: rgba(0,0,0,.9);
            text-decoration: none;
            white-space: nowrap;
          }
          .header-tag {
            font-size: 0.78rem;
            font-weight: 600;
            color: var(--c-link);
            text-transform: uppercase;
            letter-spacing: 0.09em;
          }

          /* ── Hero ───────────────────────────────────── */
          .hero {
            background: var(--c-dark);
            padding: 60px 24px;
            color: white;
          }
          .hero-inner {
            max-width: 760px;
            margin: 0 auto;
          }
          .hero-eyebrow {
            font-size: 0.72rem;
            font-weight: 600;
            letter-spacing: 0.14em;
            text-transform: uppercase;
            color: rgba(255,255,255,0.45);
            margin-bottom: 14px;
          }
          .hero h1 {
            font-size: 2.4rem;
            font-weight: 700;
            color: white;
            margin-bottom: 12px;
            line-height: 1.15;
          }
          .hero-sub {
            color: rgba(255,255,255,0.6);
            font-size: 1rem;
            line-height: 1.6;
            margin-bottom: 36px;
            max-width: 540px;
          }

          /* Search form */
          .search-form {
            display: flex;
            gap: 10px;
            max-width: 580px;
          }
          .search-form input {
            flex: 1;
            padding: 13px 16px;
            border: 1px solid rgba(255,255,255,0.18);
            border-radius: 8px;
            background: rgba(255,255,255,0.07);
            color: white;
            font-size: 0.95rem;
            font-family: var(--font);
            outline: none;
            transition: border-color 0.2s, background 0.2s;
          }
          .search-form input::placeholder { color: rgba(255,255,255,0.3); }
          .search-form input:focus {
            border-color: rgba(255,255,255,0.45);
            background: rgba(255,255,255,0.11);
          }
          .search-form button {
            padding: 13px 30px;
            background: var(--c-accent);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 0.95rem;
            font-weight: 600;
            font-family: var(--font);
            cursor: pointer;
            transition: background 0.15s, opacity 0.15s;
            white-space: nowrap;
          }
          .search-form button:hover { background: #c43e22; }
          .search-form button:disabled { opacity: 0.65; cursor: not-allowed; }
          .search-error {
            margin-top: 12px;
            color: #FCA5A5;
            font-size: 0.87rem;
          }

          /* Session loaded hero */
          .hero-session-id {
            font-size: 1.65rem;
            font-weight: 600;
            color: white;
            font-family: 'Courier New', Consolas, monospace;
            margin-bottom: 20px;
            letter-spacing: 0.02em;
          }
          .hero-chips {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
          }
          .hero-chip {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 14px;
            background: rgba(255,255,255,0.09);
            border: 1px solid rgba(255,255,255,0.18);
            border-radius: 20px;
            font-size: 0.82rem;
            color: rgba(255,255,255,0.8);
            line-height: 1.3;
          }
          .hero-chip strong { color: white; }
          .hero-chip.chip-duration {
            background: rgba(49,109,177,0.22);
            border-color: rgba(49,109,177,0.45);
          }
          .hero-chip.chip-date {
            background: rgba(255,255,255,0.06);
          }
          .hero-back {
            margin-top: 20px;
            font-size: 0.82rem;
            color: rgba(255,255,255,0.45);
            text-decoration: none;
            cursor: pointer;
            background: none;
            border: none;
            font-family: var(--font);
            padding: 0;
          }
          .hero-back:hover { color: rgba(255,255,255,0.75); }

          /* ── Main content ────────────────────────────── */
          main { padding: 32px 24px 80px; }
          .content-wrap {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            flex-direction: column;
            gap: 20px;
          }

          /* ── Stat cards ──────────────────────────────── */
          .stat-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
            gap: 16px;
          }
          .stat-card {
            background: var(--c-card);
            border: 1px solid var(--c-border);
            border-radius: var(--r-card);
            padding: 24px 26px;
            display: flex;
            flex-direction: column;
            gap: 5px;
          }
          .stat-icon { font-size: 1.15rem; margin-bottom: 6px; }
          .stat-value {
            font-size: 2rem;
            font-weight: 700;
            line-height: 1.1;
            color: var(--c-text);
          }
          .stat-label {
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: var(--c-muted);
            margin-top: 2px;
          }
          .stat-sub { font-size: 0.8rem; color: var(--c-muted); }
          .stat-card.c-fhir .stat-value { color: var(--c-fhir); }
          .stat-card.c-val  .stat-value { color: var(--c-val); }
          .stat-card.c-dur  .stat-value { color: var(--c-primary); }

          /* ── Card ────────────────────────────────────── */
          .card {
            background: var(--c-card);
            border: 1px solid var(--c-border);
            border-radius: var(--r-card);
            padding: 28px 32px;
          }
          .card-head {
            display: flex;
            align-items: baseline;
            gap: 12px;
            margin-bottom: 24px;
            flex-wrap: wrap;
          }
          .card-head h2 {
            font-size: 1.05rem;
            font-weight: 700;
            color: var(--c-text);
          }
          .card-sub {
            font-size: 0.82rem;
            color: var(--c-muted);
          }

          /* ── Breakdown bars ──────────────────────────── */
          .bk-row { margin-bottom: 20px; }
          .bk-row-head {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
            flex-wrap: wrap;
            gap: 6px;
          }
          .bk-name {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 0.92rem;
            font-weight: 600;
            color: var(--c-text);
          }
          .bk-dot {
            width: 10px; height: 10px;
            border-radius: 50%;
            flex-shrink: 0;
          }
          .bk-meta { font-size: 0.82rem; color: var(--c-muted); }
          .bar-track {
            background: var(--c-border);
            border-radius: 6px;
            height: 26px;
            overflow: hidden;
          }
          .bar-fill {
            height: 100%;
            border-radius: 6px;
            transition: width 0.65s cubic-bezier(0.4,0,0.2,1);
          }
          .bar-fill.fhir { background: var(--c-fhir); }
          .bar-fill.val  { background: var(--c-val); }

          .bk-legend {
            display: flex;
            gap: 20px;
            margin-top: 16px;
            flex-wrap: wrap;
          }
          .leg-item {
            display: flex;
            align-items: center;
            gap: 7px;
            font-size: 0.82rem;
            color: var(--c-muted);
          }
          .leg-dot {
            width: 11px; height: 11px;
            border-radius: 3px;
            flex-shrink: 0;
          }
          .leg-dot.fhir { background: var(--c-fhir); }
          .leg-dot.val  { background: var(--c-val); }

          .verdict {
            margin-top: 20px;
            padding: 14px 18px;
            background: #F8FAFC;
            border: 1px solid var(--c-border);
            border-left: 4px solid var(--c-accent);
            border-radius: 8px;
            font-size: 0.9rem;
            line-height: 1.6;
            color: var(--c-text);
          }
          .verdict strong { color: var(--c-accent); }

          /* ── Sub breakdown ───────────────────────────── */
          .sb-row {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 10px;
          }
          .sb-label {
            width: 260px;
            font-size: 0.81rem;
            color: var(--c-muted);
            text-align: right;
            flex-shrink: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .sb-track {
            flex: 1;
            background: var(--c-border);
            border-radius: 4px;
            height: 18px;
            overflow: hidden;
          }
          .sb-fill {
            height: 100%;
            border-radius: 4px;
            transition: width 0.5s ease;
          }
          .sb-fill.s0 { background: #316DB1; }
          .sb-fill.s1 { background: #4a8acf; }
          .sb-fill.s2 { background: #6aa3de; }
          .sb-fill.s3 { background: #8dbde8; }
          .sb-fill.s4 { background: #aacfee; }
          .sb-meta {
            width: 150px;
            font-size: 0.79rem;
            color: var(--c-muted);
            flex-shrink: 0;
          }

          /* ── Table ───────────────────────────────────── */
          .table-wrap { overflow-x: auto; }
          table { width: 100%; border-collapse: collapse; font-size: 0.84rem; }
          th {
            padding: 10px 12px;
            text-align: left;
            font-size: 0.72rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: var(--c-muted);
            border-bottom: 2px solid var(--c-border);
            cursor: pointer;
            user-select: none;
            white-space: nowrap;
            background: var(--c-card);
          }
          th:hover { color: var(--c-text); }
          td {
            padding: 9px 12px;
            border-bottom: 1px solid #F3F4F6;
            vertical-align: middle;
          }
          tr:last-child td { border-bottom: none; }
          tr:hover td { background: #FAFAFA; }
          .url-cell {
            max-width: 340px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-family: 'Courier New', Consolas, monospace;
            font-size: 0.79rem;
            color: var(--c-link);
          }
          .test-cell {
            font-size: 0.78rem;
            color: var(--c-muted);
            max-width: 180px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .badge {
            display: inline-flex;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.76rem;
            font-weight: 600;
            white-space: nowrap;
          }
          .badge-ok  { background: #D1FAE5; color: #065F46; }
          .badge-err { background: #FEE2E2; color: #991B1B; }
          .badge-neu { background: #F3F4F6; color: var(--c-muted); }
          .dur-cell { font-weight: 500; white-space: nowrap; }
          .dur-none { color: #D1D5DB; font-style: italic; }
          .time-cell { font-size: 0.77rem; color: var(--c-muted); white-space: nowrap; }

          /* ── Scope note ──────────────────────────────── */
          .scope-note {
            background: #EBF5FB;
            border: 1px solid #BFDBFE;
            border-radius: 8px;
            padding: 12px 18px;
            font-size: 0.83rem;
            color: #1E3A8A;
            line-height: 1.6;
          }
          .scope-note strong { font-weight: 600; }

          /* ── Warning ─────────────────────────────────── */
          .warning-box {
            background: #FFFBEB;
            border: 1px solid #FCD34D;
            border-radius: 8px;
            padding: 10px 14px;
            font-size: 0.83rem;
            color: #92400E;
            margin-bottom: 14px;
          }

          /* ── Empty state ─────────────────────────────── */
          .empty-state {
            text-align: center;
            padding: 40px 20px;
            color: var(--c-muted);
            font-size: 0.9rem;
          }

          /* ── Responsive ──────────────────────────────── */
          @media (max-width: 700px) {
            .hero { padding: 40px 16px; }
            .hero h1 { font-size: 1.8rem; }
            .search-form { flex-direction: column; }
            .stat-grid { grid-template-columns: repeat(2, 1fr); }
            main { padding: 20px 12px 60px; }
            .card { padding: 20px 16px; }
            .sb-label { width: 100px; font-size: 0.75rem; }
            .sb-meta  { width: 100px; font-size: 0.75rem; }
            .header-tag { display: none; }
          }
        </style>
      </head>
      <body>

        <!-- Site header -->
        <header class="site-header">
          <div class="site-header-inner">
            <a href="/" class="site-logo">Inferno on hl7.org.au</a>
            <span class="header-tag">Performance Analysis</span>
          </div>
        </header>

        <!-- Search hero -->
        <section class="hero" id="hero-search">
          <div class="hero-inner">
            <div class="hero-eyebrow">Inferno · Diagnostics</div>
            <h1>Performance Analysis</h1>
            <p class="hero-sub">Understand where time was spent in your test run — FHIR server, validator API, and total session duration.</p>
            <div class="search-form">
              <input type="text" id="sessionInput"
                     placeholder="Enter a test session ID…"
                     autocomplete="off"
                     onkeydown="if(event.key==='Enter')loadSession()" />
              <button id="analyseBtn" onclick="loadSession()">Analyse</button>
            </div>
            <div id="search-error" style="display:none" class="search-error"></div>
          </div>
        </section>

        <!-- Session loaded hero -->
        <section class="hero" id="hero-loaded" style="display:none; padding-top:44px; padding-bottom:44px;">
          <div class="hero-inner">
            <div class="hero-eyebrow">Performance Analysis</div>
            <div class="hero-session-id" id="hero-sid"></div>
            <div class="hero-chips" id="hero-chips"></div>
            <button class="hero-back" onclick="resetToSearch()">← Analyse a different session</button>
          </div>
        </section>

        <!-- Results -->
        <main id="results" style="display:none;">
          <div class="content-wrap">

            <!-- Stat cards -->
            <div class="stat-grid" id="stat-grid"></div>

            <!-- Scope note -->
            <div class="scope-note">
              <strong>What's measured:</strong>
              (1) Round-trip time for every HTTP request the Inferno worker makes to your <strong>FHIR server under test</strong>, and
              (2) every <strong>validator API</strong> call (worker → validator-api pod).
              Terminology server calls are made inside the validator JVM and are not visible here —
              see the <strong>Inferno Run Analysis</strong> Grafana dashboard for that layer.
            </div>

            <!-- Breakdown -->
            <div class="card">
              <div class="card-head">
                <h2>Was it my server or the infra?</h2>
                <span class="card-sub">Proportion of instrumented external wait time</span>
              </div>
              <div id="breakdown"></div>
            </div>

            <!-- By server -->
            <div class="card">
              <div class="card-head">
                <h2>FHIR wait by server</h2>
                <span class="card-sub" id="fhir-server-sub"></span>
              </div>
              <div id="by-server"></div>
            </div>

            <!-- Request table -->
            <div class="card">
              <div class="card-head">
                <h2>All outgoing FHIR requests</h2>
              </div>
              <div id="tbl-warning"></div>
              <div class="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th onclick="sortTable(0)">URL ↕</th>
                      <th onclick="sortTable(1)">Test ↕</th>
                      <th onclick="sortTable(2)">Status ↕</th>
                      <th onclick="sortTable(3)">Duration ↕</th>
                      <th onclick="sortTable(4)">Time ↕</th>
                    </tr>
                  </thead>
                  <tbody id="req-body"></tbody>
                </table>
              </div>
            </div>

          </div>
        </main>

        <script>
          let sortDir = {};
          let currentData = null;

          // ── Helpers ────────────────────────────────────────────────────
          function fmtMs(ms) {
            if (ms == null) return '<span class="dur-none">—</span>';
            if (ms < 1000)  return ms + 'ms';
            if (ms < 60000) return (ms / 1000).toFixed(1) + 's';
            const m = Math.floor(ms / 60000);
            const s = Math.round((ms % 60000) / 1000);
            return `${m}m ${s}s`;
          }
          function fmtMsPlain(ms) {
            if (ms == null) return '—';
            if (ms < 1000)  return ms + 'ms';
            if (ms < 60000) return (ms / 1000).toFixed(1) + 's';
            const m = Math.floor(ms / 60000);
            const s = Math.round((ms % 60000) / 1000);
            return `${m}m ${s}s`;
          }
          function fmtDt(iso) {
            if (!iso) return '—';
            return new Date(iso).toLocaleString(undefined, {
              year: 'numeric', month: 'short', day: 'numeric',
              hour: '2-digit', minute: '2-digit', second: '2-digit',
              timeZoneName: 'short'
            });
          }
          function fmtTime(iso) {
            if (!iso) return '';
            return new Date(iso).toLocaleTimeString();
          }
          function pct(n, d) {
            return d > 0 ? ((n / d) * 100).toFixed(1) : '0.0';
          }

          // ── Load session ────────────────────────────────────────────────
          async function loadSession() {
            const id = document.getElementById('sessionInput').value.trim();
            if (!id) { showErr('Please enter a session ID.'); return; }
            setLoading(true);
            clearErr();
            try {
              const res = await fetch('/api/performance/test_sessions/' + encodeURIComponent(id));
              if (!res.ok) {
                const body = await res.json().catch(() => ({ error: res.statusText }));
                showErr(body.error || `Error ${res.status}`); return;
              }
              currentData = await res.json();
              render(currentData);
            } catch(e) {
              showErr('Failed to load: ' + e.message);
            } finally {
              setLoading(false);
            }
          }

          function setLoading(v) {
            const btn = document.getElementById('analyseBtn');
            btn.disabled = v;
            btn.textContent = v ? 'Loading…' : 'Analyse';
          }
          function showErr(msg) {
            const el = document.getElementById('search-error');
            el.textContent = msg; el.style.display = 'block';
          }
          function clearErr() {
            document.getElementById('search-error').style.display = 'none';
          }
          function resetToSearch() {
            document.getElementById('hero-search').style.display  = '';
            document.getElementById('hero-loaded').style.display  = 'none';
            document.getElementById('results').style.display      = 'none';
            currentData = null;
          }

          // ── Render dashboard ────────────────────────────────────────────
          function render(data) {
            document.getElementById('hero-search').style.display = 'none';
            document.getElementById('hero-loaded').style.display = '';
            document.getElementById('results').style.display     = '';

            const s      = data.summary;
            const fhirMs = s.fhir_ms || 0;
            const valMs  = s.validator_ms || 0;
            const durMs  = data.session_duration_ms;

            // Hero
            document.getElementById('hero-sid').textContent = data.session_id;
            const chips = document.getElementById('hero-chips');
            chips.innerHTML = '';
            if (durMs) {
              chips.innerHTML += chip('⏱', 'Duration: <strong>' + fmtMsPlain(durMs) + '</strong>', 'chip-duration');
            }
            if (data.session_started_at) {
              chips.innerHTML += chip('📅', fmtDt(data.session_started_at), 'chip-date');
            }
            chips.innerHTML += chip('📋', `<strong>${s.fhir_requests || 0}</strong> FHIR · <strong>${s.validator_calls || 0}</strong> validator calls`);

            // Stat cards
            const timedPct = data.total_requests > 0
              ? Math.round((data.requests_with_timing / data.total_requests) * 100)
              : 0;
            document.getElementById('stat-grid').innerHTML = [
              { icon: '⏱', val: durMs ? fmtMsPlain(durMs) : '—', label: 'Session Duration',   sub: durMs ? 'total wall time' : 'not available', cls: 'c-dur' },
              { icon: '🖥', val: fmtMsPlain(fhirMs),               label: 'FHIR Server Wait',  sub: `${s.fhir_requests || 0} requests`,        cls: 'c-fhir' },
              { icon: '🔍', val: fmtMsPlain(valMs),                label: 'Validator Wait',    sub: `${s.validator_calls || 0} calls`,          cls: 'c-val' },
              { icon: '📊', val: data.total_requests,              label: 'FHIR Requests',     sub: `${timedPct}% timed`,                       cls: '' },
            ].map(c => `
              <div class="stat-card ${c.cls}">
                <div class="stat-icon">${c.icon}</div>
                <div class="stat-value">${c.val}</div>
                <div class="stat-label">${c.label}</div>
                <div class="stat-sub">${c.sub}</div>
              </div>`).join('');

            renderBreakdown(fhirMs, valMs, s);
            renderByServer(s.by_server || [], fhirMs);

            // Table warning
            const missing = data.total_requests - data.requests_with_timing;
            document.getElementById('tbl-warning').innerHTML = missing > 0
              ? `<div class="warning-box">${missing} request(s) recorded before timing instrumentation was deployed.</div>` : '';

            renderTable(data.requests);
          }

          function chip(icon, html, cls = '') {
            return `<span class="hero-chip ${cls}">${icon}&nbsp;<span>${html}</span></span>`;
          }

          function renderBreakdown(fhirMs, valMs, s) {
            const el = document.getElementById('breakdown');
            const total = fhirMs + valMs;
            if (total === 0) {
              el.innerHTML = '<div class="empty-state">No timing data available for this session.</div>';
              return;
            }
            const fp = pct(fhirMs, total);
            const vp = pct(valMs,  total);
            let verdict = '';
            if (valMs === 0) {
              verdict = 'Validator call timing is not yet recorded for this session — run a new test to see the full breakdown.';
            } else if (fhirMs > valMs * 3) {
              verdict = `Your <strong>FHIR server</strong> dominated this run — <strong>${fp}%</strong> of instrumented wait time (${fmtMsPlain(fhirMs)}). The validator API was comparatively fast.`;
            } else if (valMs > fhirMs * 3) {
              verdict = `The <strong>validator API</strong> was the bottleneck — <strong>${vp}%</strong> of instrumented wait time (${fmtMsPlain(valMs)}). Your FHIR server was comparatively fast.`;
            } else {
              verdict = `Time is split fairly evenly — FHIR server <strong>${fp}%</strong> (${fmtMsPlain(fhirMs)}) vs validator API <strong>${vp}%</strong> (${fmtMsPlain(valMs)}).`;
            }
            el.innerHTML = `
              <div class="bk-row">
                <div class="bk-row-head">
                  <span class="bk-name"><span class="bk-dot" style="background:var(--c-fhir)"></span>Your FHIR server</span>
                  <span class="bk-meta">${fmtMsPlain(fhirMs)} &nbsp;·&nbsp; ${s.fhir_requests || 0} requests &nbsp;·&nbsp; ${fp}%</span>
                </div>
                <div class="bar-track"><div class="bar-fill fhir" style="width:${fp}%"></div></div>
              </div>
              <div class="bk-row">
                <div class="bk-row-head">
                  <span class="bk-name">
                    <span class="bk-dot" style="background:var(--c-val)"></span>
                    Validator API
                    <span style="font-weight:400;color:var(--c-muted);font-size:0.76rem">(Sparked infra)</span>
                  </span>
                  <span class="bk-meta">${fmtMsPlain(valMs)} &nbsp;·&nbsp; ${s.validator_calls || 0} calls &nbsp;·&nbsp; ${vp}%</span>
                </div>
                <div class="bar-track"><div class="bar-fill val" style="width:${vp}%"></div></div>
              </div>
              <div class="bk-legend">
                <span class="leg-item"><span class="leg-dot fhir"></span>FHIR server (your system)</span>
                <span class="leg-item"><span class="leg-dot val"></span>Validator API (Sparked infra)</span>
              </div>
              <div class="verdict">${verdict}</div>`;
          }

          function renderByServer(servers, fhirMs) {
            document.getElementById('fhir-server-sub').textContent =
              servers.length ? `${servers.length} server${servers.length !== 1 ? 's' : ''}` : '';
            const el = document.getElementById('by-server');
            if (!servers.length) {
              el.innerHTML = '<div class="empty-state">No FHIR timing data available yet.</div>'; return;
            }
            el.innerHTML = servers.map((sv, i) => {
              const p = pct(sv.total_ms, fhirMs);
              const label = sv.host || 'unknown';
              return `<div class="sb-row">
                <div class="sb-label" title="${label}">${label}</div>
                <div class="sb-track"><div class="sb-fill s${i % 5}" style="width:${p}%"></div></div>
                <div class="sb-meta">${sv.count} req · ${fmtMsPlain(sv.total_ms)} (${p}%)</div>
              </div>`;
            }).join('');
          }

          function renderTable(reqs) {
            document.getElementById('req-body').innerHTML = reqs.map(r => {
              const sc = !r.status ? 'badge-neu' : r.status < 400 ? 'badge-ok' : 'badge-err';
              const tl = r.test_id
                ? `<span title="${r.test_id}">${r.test_id.split('-').slice(-1)[0] || r.test_id}</span>`
                : '<span style="color:#D1D5DB">—</span>';
              return `<tr>
                <td class="url-cell" title="${r.url || ''}">${r.url || ''}</td>
                <td class="test-cell">${tl}</td>
                <td><span class="badge ${sc}">${r.status || '—'}</span></td>
                <td class="dur-cell">${fmtMs(r.duration_ms)}</td>
                <td class="time-cell">${fmtTime(r.created_at)}</td>
              </tr>`;
            }).join('');
          }

          function sortTable(col) {
            if (!currentData) return;
            sortDir[col] = !sortDir[col];
            const reqs = [...currentData.requests];
            const keys = ['url', 'test_id', 'status', 'duration_ms', 'created_at'];
            reqs.sort((a, b) => {
              const va = a[keys[col]] ?? '', vb = b[keys[col]] ?? '';
              return (va < vb ? -1 : va > vb ? 1 : 0) * (sortDir[col] ? 1 : -1);
            });
            renderTable(reqs);
          }

          // Auto-load from URL param
          (function() {
            const id = new URLSearchParams(location.search).get('session')
                    || new URLSearchParams(location.search).get('session_id');
            if (id) {
              document.getElementById('sessionInput').value = id;
              loadSession();
            }
          })();
        </script>
      </body>
      </html>
    HTML
  end
end
