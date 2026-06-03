require 'sinatra/base'
require 'json'
require 'sequel'

module InfernoPlatformTemplate
  class PerformanceApp < Sinatra::Base
    TX_SERVER_URL   = ENV.fetch('TX_SERVER_URL', '').freeze
    VALIDATOR_URL   = ENV.fetch('FHIR_RESOURCE_VALIDATOR_URL', 'http://validator-api:3500').freeze

    # ------------------------------------------------------------------
    # DB connection (lazy, reuses Sequel's existing pool if already open)
    # ------------------------------------------------------------------
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

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def categorise(url)
      return 'unknown' if url.nil? || url.empty?
      return 'validator'    if url.start_with?(VALIDATOR_URL)
      return 'terminology'  if !TX_SERVER_URL.empty? && url.start_with?(TX_SERVER_URL)
      'fhir_server'
    end

    def format_ms(ms)
      return nil if ms.nil?
      ms < 1000 ? "#{ms}ms" : "#{'%.1f' % (ms / 1000.0)}s"
    end

    # ------------------------------------------------------------------
    # JSON API
    # ------------------------------------------------------------------
    get '/test_sessions/:id' do
      content_type :json
      headers 'Access-Control-Allow-Origin' => '*'

      session_id = params[:id]
      db = self.class.db

      unless db.table_exists?(:requests)
        halt 503, { error: 'requests table not found' }.to_json
      end

      # Check session exists
      sessions_table = db.table_exists?(:test_sessions) ? :test_sessions : nil
      if sessions_table && db[sessions_table].where(id: session_id).empty?
        halt 404, { error: 'session not found' }.to_json
      end

      # Fetch outgoing requests for session
      cols = db[:requests].columns
      has_duration = cols.include?(:duration_ms)

      rows = db[:requests]
        .where(test_session_id: session_id)
        .where(direction: 'outgoing')
        .select(*[:id, :url, :status, :created_at, :result_id, (has_duration ? :duration_ms : nil)].compact)
        .order(:created_at)
        .all

      # Build response
      categorised = rows.map do |r|
        cat = categorise(r[:url])
        {
          url:         r[:url],
          status:      r[:status],
          duration_ms: r[:duration_ms],
          category:    cat,
          created_at:  r[:created_at]&.iso8601
        }
      end

      summary = { fhir_server_ms: 0, terminology_ms: 0, validator_ms: 0, unknown_ms: 0 }
      timed_count = 0
      categorised.each do |r|
        next unless r[:duration_ms]
        timed_count += 1
        key = :"#{r[:category]}_ms"
        summary[key] = (summary[key] || 0) + r[:duration_ms]
      end
      summary[:total_ms] = summary.values.sum

      {
        session_id:          session_id,
        tx_server_url:       TX_SERVER_URL,
        validator_url:       VALIDATOR_URL,
        total_requests:      rows.size,
        requests_with_timing: timed_count,
        has_duration_column: has_duration,
        summary:             summary,
        requests:            categorised
      }.to_json
    end

    # ------------------------------------------------------------------
    # HTML performance page
    # ------------------------------------------------------------------
    get '/' do
      content_type :html
      PERFORMANCE_HTML
    end

    # ------------------------------------------------------------------
    # HTML template (inline so it ships with the image, no extra assets)
    # ------------------------------------------------------------------
    PERFORMANCE_HTML = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Inferno Performance Analysis</title>
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
                 background: #f8f9fa; color: #212529; padding: 24px; }
          h1 { font-size: 1.6rem; font-weight: 600; color: #1d5090; margin-bottom: 4px; }
          .subtitle { color: #6c757d; margin-bottom: 24px; font-size: 0.9rem; }
          .card { background: white; border-radius: 8px; border: 1px solid #dee2e6;
                  padding: 20px; margin-bottom: 20px; }
          .input-row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
          input[type=text] { flex: 1; min-width: 260px; padding: 8px 12px;
                              border: 1px solid #ced4da; border-radius: 6px; font-size: 0.95rem; }
          button { padding: 8px 20px; background: #1d5090; color: white; border: none;
                   border-radius: 6px; font-size: 0.95rem; cursor: pointer; }
          button:hover { background: #164070; }
          #status { margin-top: 12px; font-size: 0.9rem; color: #6c757d; }
          #results { display: none; }
          .summary-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
                          gap: 12px; margin-bottom: 20px; }
          .stat-card { background: #f8f9fa; border-radius: 6px; padding: 14px; text-align: center;
                       border: 1px solid #e9ecef; }
          .stat-value { font-size: 1.6rem; font-weight: 700; color: #1d5090; }
          .stat-label { font-size: 0.78rem; color: #6c757d; margin-top: 4px; text-transform: uppercase;
                        letter-spacing: 0.05em; }
          .breakdown { margin-bottom: 20px; }
          .breakdown h3 { font-size: 1rem; margin-bottom: 12px; color: #343a40; }
          .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
          .bar-label { width: 120px; font-size: 0.85rem; color: #495057; text-align: right;
                       flex-shrink: 0; }
          .bar-track { flex: 1; background: #e9ecef; border-radius: 4px; height: 22px; overflow: hidden; }
          .bar-fill { height: 100%; border-radius: 4px; transition: width 0.4s ease; }
          .bar-fill.fhir_server  { background: #2F6BAC; }
          .bar-fill.terminology  { background: #20c997; }
          .bar-fill.validator    { background: #fd7e14; }
          .bar-fill.unknown      { background: #adb5bd; }
          .bar-value { width: 90px; font-size: 0.82rem; color: #6c757d; flex-shrink: 0; }
          table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
          th { background: #f8f9fa; padding: 8px 10px; text-align: left; border-bottom: 2px solid #dee2e6;
               font-weight: 600; cursor: pointer; user-select: none; white-space: nowrap; }
          th:hover { background: #e9ecef; }
          td { padding: 7px 10px; border-bottom: 1px solid #f0f0f0; vertical-align: middle; }
          tr:hover td { background: #f8f9fa; }
          .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem;
                   font-weight: 600; color: white; }
          .badge.fhir_server  { background: #2F6BAC; }
          .badge.terminology  { background: #20c997; }
          .badge.validator    { background: #fd7e14; color: #212529; }
          .badge.unknown      { background: #adb5bd; color: #212529; }
          .status-ok   { color: #198754; font-weight: 600; }
          .status-err  { color: #dc3545; font-weight: 600; }
          .url-cell { max-width: 420px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .no-timing { color: #adb5bd; font-style: italic; }
          .warning-box { background: #fff3cd; border: 1px solid #ffc107; border-radius: 6px;
                         padding: 12px 16px; font-size: 0.85rem; margin-bottom: 16px; }
          @media (max-width: 700px) {
            .bar-label { width: 80px; font-size: 0.78rem; }
            .summary-grid { grid-template-columns: repeat(2, 1fr); }
          }
        </style>
      </head>
      <body>
        <h1>Inferno Performance Analysis</h1>
        <p class="subtitle">Per-request HTTP timing breakdown for a test session</p>

        <div class="card">
          <div class="input-row">
            <input type="text" id="sessionInput" placeholder="Test session ID (e.g. abc123xyz)" />
            <button onclick="loadSession()">Analyse</button>
          </div>
          <div id="status"></div>
        </div>

        <div id="results">
          <div class="card">
            <div class="summary-grid" id="summaryGrid"></div>
          </div>
          <div class="card breakdown">
            <h3>Time distribution (outgoing HTTP only)</h3>
            <div id="barChart"></div>
          </div>
          <div class="card">
            <h3 style="margin-bottom:14px;">All outgoing requests</h3>
            <div id="warningBox"></div>
            <div style="overflow-x:auto;">
              <table id="reqTable">
                <thead>
                  <tr>
                    <th onclick="sortTable(0)">URL</th>
                    <th onclick="sortTable(1)">Category</th>
                    <th onclick="sortTable(2)">Status</th>
                    <th onclick="sortTable(3)">Duration</th>
                    <th onclick="sortTable(4)">Time</th>
                  </tr>
                </thead>
                <tbody id="reqBody"></tbody>
              </table>
            </div>
          </div>
        </div>

        <script>
          let sortDir = {};
          let currentData = null;

          function fmtMs(ms) {
            if (ms == null) return '<span class="no-timing">no data</span>';
            if (ms < 1000) return ms + 'ms';
            return (ms / 1000).toFixed(1) + 's';
          }

          function fmtMsPlain(ms) {
            if (ms == null) return '';
            if (ms < 1000) return ms + 'ms';
            return (ms / 1000).toFixed(1) + 's';
          }

          function categoryLabel(cat) {
            return { fhir_server: 'FHIR Server', terminology: 'Terminology', validator: 'Validator', unknown: 'Other' }[cat] || cat;
          }

          const CATEGORY_COLORS = {
            fhir_server: '#2F6BAC',
            terminology: '#20c997',
            validator: '#fd7e14',
            unknown: '#adb5bd'
          };

          async function loadSession() {
            const id = document.getElementById('sessionInput').value.trim();
            if (!id) { setStatus('Please enter a session ID.', 'error'); return; }
            setStatus('Loading…');
            document.getElementById('results').style.display = 'none';
            try {
              const res = await fetch('/api/performance/test_sessions/' + encodeURIComponent(id));
              if (!res.ok) {
                const err = await res.json().catch(() => ({ error: res.statusText }));
                setStatus((err.error || res.statusText), 'error'); return;
              }
              currentData = await res.json();
              renderResults(currentData);
              setStatus('');
            } catch(e) {
              setStatus('Failed to load: ' + e.message, 'error');
            }
          }

          function setStatus(msg, type) {
            const el = document.getElementById('status');
            el.textContent = msg;
            el.style.color = type === 'error' ? '#dc3545' : '#6c757d';
          }

          function renderResults(data) {
            const s = data.summary;
            const total = s.total_ms || 0;
            const categories = [
              { key: 'fhir_server', label: 'FHIR Server' },
              { key: 'terminology', label: 'Terminology' },
              { key: 'validator',   label: 'Validator' },
              { key: 'unknown',     label: 'Other' }
            ].filter(c => s[c.key + '_ms'] > 0);

            // Summary cards
            const grid = document.getElementById('summaryGrid');
            grid.innerHTML = [
              { value: fmtMs(total),             label: 'Total HTTP time' },
              { value: data.total_requests,       label: 'Outgoing requests' },
              { value: data.requests_with_timing, label: 'Requests with timing' },
              { value: fmtMs(s.fhir_server_ms),  label: 'FHIR Server' },
              { value: fmtMs(s.terminology_ms),  label: 'Terminology' },
              { value: fmtMs(s.validator_ms),    label: 'Validator' }
            ].map(c => `<div class="stat-card"><div class="stat-value">${c.value}</div><div class="stat-label">${c.label}</div></div>`).join('');

            // Bar chart
            const chart = document.getElementById('barChart');
            chart.innerHTML = categories.map(c => {
              const ms = s[c.key + '_ms'] || 0;
              const pct = total > 0 ? ((ms / total) * 100).toFixed(1) : 0;
              return `<div class="bar-row">
                <div class="bar-label">${c.label}</div>
                <div class="bar-track"><div class="bar-fill ${c.key}" style="width:${pct}%"></div></div>
                <div class="bar-value">${fmtMs(ms)} (${pct}%)</div>
              </div>`;
            }).join('') || '<p style="color:#6c757d;font-size:0.85rem;">No timing data available yet — requests may have been recorded before the duration_ms migration was applied.</p>';

            // Warning if no timing data
            const warn = document.getElementById('warningBox');
            if (data.requests_with_timing < data.total_requests) {
              const missing = data.total_requests - data.requests_with_timing;
              warn.innerHTML = `<div class="warning-box">${missing} request(s) have no timing data (recorded before instrumentation was deployed).</div>`;
            } else {
              warn.innerHTML = '';
            }

            // Request table
            renderTable(data.requests);
            document.getElementById('results').style.display = 'block';
          }

          function renderTable(reqs) {
            const tbody = document.getElementById('reqBody');
            tbody.innerHTML = reqs.map(r => {
              const statusClass = r.status && r.status < 400 ? 'status-ok' : 'status-err';
              const ts = r.created_at ? new Date(r.created_at).toLocaleTimeString() : '';
              return `<tr>
                <td class="url-cell" title="${r.url || ''}">${r.url || ''}</td>
                <td><span class="badge ${r.category}">${categoryLabel(r.category)}</span></td>
                <td class="${statusClass}">${r.status || '—'}</td>
                <td>${fmtMs(r.duration_ms)}</td>
                <td>${ts}</td>
              </tr>`;
            }).join('');
          }

          function sortTable(col) {
            if (!currentData) return;
            sortDir[col] = !sortDir[col];
            const reqs = [...currentData.requests];
            const keys = ['url', 'category', 'status', 'duration_ms', 'created_at'];
            reqs.sort((a, b) => {
              const va = a[keys[col]] ?? '';
              const vb = b[keys[col]] ?? '';
              if (va < vb) return sortDir[col] ? -1 : 1;
              if (va > vb) return sortDir[col] ? 1 : -1;
              return 0;
            });
            renderTable(reqs);
          }

          // Auto-load from URL param
          (function() {
            const params = new URLSearchParams(location.search);
            const id = params.get('session') || params.get('session_id');
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
