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

      cols = db[:requests].columns
      has_duration = cols.include?(:duration_ms)

      has_results = db.table_exists?(:results)
      result_cols = has_results ? db[:results].columns : []
      has_test_id = result_cols.include?(:test_id)

      base_query = db[:requests].where(
        test_session_id: session_id,
        direction: 'outgoing'
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
      validator_ms    = 0
      validator_calls = 0
      has_validator_timing = db.table_exists?(:validator_timing)
      if has_validator_timing
        vt_rows = db[:validator_timing].where(test_session_id: session_id).all
        validator_calls = vt_rows.size
        validator_ms    = vt_rows.sum { |r| r[:duration_ms] || 0 }
      end

      {
        session_id:              session_id,
        tx_server_url:           TX_SERVER_URL,
        validator_url:           VALIDATOR_URL,
        total_requests:          rows.size,
        requests_with_timing:    timed_count,
        has_duration_column:     has_duration,
        has_validator_timing:    has_validator_timing,
        summary: {
          fhir_ms:          fhir_ms,
          validator_ms:     validator_ms,
          fhir_requests:    rows.size,
          validator_calls:  validator_calls,
          by_server:        by_server_sorted
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
          .scope-note { background: #e8f0fb; border: 1px solid #b8d0f0; border-radius: 6px;
                        padding: 12px 16px; font-size: 0.85rem; color: #1d5090; margin-bottom: 16px; }
          .scope-note strong { font-weight: 600; }

          /* Summary grid */
          .summary-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
                          gap: 12px; margin-bottom: 20px; }
          .stat-card { background: #f8f9fa; border-radius: 6px; padding: 14px; text-align: center;
                       border: 1px solid #e9ecef; }
          .stat-card.highlight { background: #e8f0fb; border-color: #b8d0f0; }
          .stat-value { font-size: 1.6rem; font-weight: 700; color: #1d5090; }
          .stat-label { font-size: 0.78rem; color: #6c757d; margin-top: 4px; text-transform: uppercase;
                        letter-spacing: 0.05em; }

          /* System breakdown stacked bar */
          .breakdown-section h3 { font-size: 1rem; margin-bottom: 16px; color: #343a40; }
          .breakdown-row { margin-bottom: 14px; }
          .breakdown-row-label { display: flex; justify-content: space-between; align-items: baseline;
                                  margin-bottom: 5px; }
          .breakdown-row-name { font-size: 0.88rem; font-weight: 600; color: #343a40; }
          .breakdown-row-meta { font-size: 0.82rem; color: #6c757d; }
          .bar-track { background: #e9ecef; border-radius: 4px; height: 26px; overflow: hidden; }
          .bar-fill { height: 100%; border-radius: 4px; transition: width 0.5s ease; }
          .bar-fill.fhir      { background: #2F6BAC; }
          .bar-fill.validator { background: #1a9e7a; }
          .stacked-legend { display: flex; gap: 16px; margin-top: 10px; flex-wrap: wrap; }
          .legend-item { display: flex; align-items: center; gap: 6px; font-size: 0.82rem; color: #495057; }
          .legend-dot { width: 12px; height: 12px; border-radius: 3px; flex-shrink: 0; }
          .legend-dot.fhir      { background: #2F6BAC; }
          .legend-dot.validator { background: #1a9e7a; }
          .verdict { margin-top: 14px; padding: 10px 14px; border-radius: 6px;
                     font-size: 0.88rem; background: #f8f9fa; border: 1px solid #e9ecef; color: #495057; }
          .verdict strong { color: #212529; }

          /* FHIR server sub-breakdown */
          .sub-breakdown h3 { font-size: 1rem; margin-bottom: 12px; color: #343a40; }
          .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
          .bar-label { width: 280px; font-size: 0.82rem; color: #495057; text-align: right;
                       flex-shrink: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .bar-track-sm { flex: 1; background: #e9ecef; border-radius: 4px; height: 22px; overflow: hidden; }
          .bar-fill-sm { height: 100%; border-radius: 4px; transition: width 0.4s ease; }
          .bar-fill-sm.s0 { background: #2F6BAC; }
          .bar-fill-sm.s1 { background: #4a90c4; }
          .bar-fill-sm.s2 { background: #6baed6; }
          .bar-fill-sm.s3 { background: #9ecae1; }
          .bar-fill-sm.s4 { background: #c6dbef; }
          .bar-value { width: 130px; font-size: 0.82rem; color: #6c757d; flex-shrink: 0; }

          /* Request table */
          table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
          th { background: #f8f9fa; padding: 8px 10px; text-align: left; border-bottom: 2px solid #dee2e6;
               font-weight: 600; cursor: pointer; user-select: none; white-space: nowrap; }
          th:hover { background: #e9ecef; }
          td { padding: 7px 10px; border-bottom: 1px solid #f0f0f0; vertical-align: middle; }
          tr:hover td { background: #f8f9fa; }
          .status-ok  { color: #198754; font-weight: 600; }
          .status-err { color: #dc3545; font-weight: 600; }
          .url-cell { max-width: 360px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          .test-cell { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
                       font-size: 0.78rem; color: #6c757d; }
          .no-timing { color: #adb5bd; font-style: italic; }
          .warning-box { background: #fff3cd; border: 1px solid #ffc107; border-radius: 6px;
                         padding: 12px 16px; font-size: 0.85rem; margin-bottom: 16px; }
          @media (max-width: 700px) {
            .bar-label { width: 120px; font-size: 0.78rem; }
            .summary-grid { grid-template-columns: repeat(2, 1fr); }
          }
        </style>
      </head>
      <body>
        <h1>Inferno Performance Analysis</h1>
        <p class="subtitle">FHIR server and validator API timing recorded by the Inferno worker</p>

        <div class="card">
          <div class="input-row">
            <input type="text" id="sessionInput" placeholder="Test session ID (e.g. abc123xyz)" />
            <button onclick="loadSession()">Analyse</button>
          </div>
          <div id="status"></div>
        </div>

        <div id="results">
          <div class="scope-note">
            <strong>What's tracked:</strong>
            (1) Every HTTP request the worker makes to the <strong>FHIR server under test</strong>, and
            (2) every <strong>validator API</strong> call (worker → validator-api pod). These are the two
            largest time sinks that live outside your FHIR server.
            Terminology server calls are made internally by the validator JVM — not visible here.
            For a full end-to-end trace see the <strong>Inferno Run Analysis</strong> Grafana dashboard.
          </div>

          <div class="card">
            <div class="summary-grid" id="summaryGrid"></div>
          </div>

          <div class="card">
            <div class="breakdown-section">
              <h3>Was it my server or the infra?</h3>
              <div id="systemBreakdown"></div>
            </div>
          </div>

          <div class="card sub-breakdown">
            <h3>FHIR wait by server</h3>
            <div id="barChart"></div>
          </div>

          <div class="card">
            <h3 style="margin-bottom:14px;">All outgoing FHIR requests</h3>
            <div id="warningBox"></div>
            <div style="overflow-x:auto;">
              <table id="reqTable">
                <thead>
                  <tr>
                    <th onclick="sortTable(0)">URL</th>
                    <th onclick="sortTable(1)">Test</th>
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
            if (ms == null) return '—';
            if (ms < 1000) return ms + 'ms';
            return (ms / 1000).toFixed(1) + 's';
          }

          async function loadSession() {
            const id = document.getElementById('sessionInput').value.trim();
            if (!id) { setStatus('Please enter a session ID.', 'error'); return; }
            setStatus('Loading…');
            document.getElementById('results').style.display = 'none';
            try {
              const res = await fetch('/api/performance/test_sessions/' + encodeURIComponent(id));
              if (!res.ok) {
                const err = await res.json().catch(() => ({ error: res.statusText }));
                setStatus(err.error || res.statusText, 'error'); return;
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
            const fhirMs = s.fhir_ms || 0;
            const valMs  = s.validator_ms || 0;

            // Summary cards
            const grid = document.getElementById('summaryGrid');
            const pct = data.total_requests > 0
              ? Math.round((data.requests_with_timing / data.total_requests) * 100)
              : 0;
            grid.innerHTML = [
              { value: fmtMsPlain(fhirMs), label: 'FHIR server wait', highlight: true },
              { value: fmtMsPlain(valMs),  label: 'Validator API wait', highlight: true },
              { value: data.total_requests,                          label: 'FHIR requests' },
              { value: s.validator_calls || 0,                       label: 'Validator calls' },
              { value: data.requests_with_timing + ' (' + pct + '%)', label: 'FHIR requests timed' }
            ].map(c =>
              `<div class="stat-card${c.highlight ? ' highlight' : ''}">
                <div class="stat-value">${c.value}</div>
                <div class="stat-label">${c.label}</div>
              </div>`
            ).join('');

            // System breakdown bars
            const breakdown = document.getElementById('systemBreakdown');
            const total = fhirMs + valMs;
            if (total === 0) {
              breakdown.innerHTML = '<p style="color:#6c757d;font-size:0.85rem;">No timing data for this session yet.</p>';
            } else {
              const fhirPct = ((fhirMs / total) * 100).toFixed(1);
              const valPct  = ((valMs  / total) * 100).toFixed(1);

              // Verdict text
              let verdict = '';
              if (valMs === 0) {
                verdict = 'Validator timing not yet recorded for this session (run a new session to see it).';
              } else if (fhirMs > valMs * 3) {
                verdict = `<strong>Your FHIR server</strong> was the dominant time sink — ${fhirPct}% of instrumented wait time.`;
              } else if (valMs > fhirMs * 3) {
                verdict = `The <strong>validator API</strong> was the dominant time sink — ${valPct}% of instrumented wait time. This is infra overhead, not your server.`;
              } else {
                verdict = `Time is split fairly evenly: FHIR server ${fhirPct}%, Validator API ${valPct}% of instrumented wait.`;
              }

              breakdown.innerHTML = `
                <div class="breakdown-row">
                  <div class="breakdown-row-label">
                    <span class="breakdown-row-name">Your FHIR server</span>
                    <span class="breakdown-row-meta">${fmtMsPlain(fhirMs)} &nbsp;·&nbsp; ${s.fhir_requests} requests &nbsp;·&nbsp; ${fhirPct}%</span>
                  </div>
                  <div class="bar-track"><div class="bar-fill fhir" style="width:${fhirPct}%"></div></div>
                </div>
                <div class="breakdown-row">
                  <div class="breakdown-row-label">
                    <span class="breakdown-row-name">Validator API (infra)</span>
                    <span class="breakdown-row-meta">${fmtMsPlain(valMs)} &nbsp;·&nbsp; ${s.validator_calls || 0} calls &nbsp;·&nbsp; ${valPct}%</span>
                  </div>
                  <div class="bar-track"><div class="bar-fill validator" style="width:${valPct}%"></div></div>
                </div>
                <div class="stacked-legend">
                  <span class="legend-item"><span class="legend-dot fhir"></span>FHIR server (your system)</span>
                  <span class="legend-item"><span class="legend-dot validator"></span>Validator API (Sparked infra)</span>
                </div>
                <div class="verdict">${verdict}</div>
              `;
            }

            // FHIR by-server sub-breakdown
            const chart = document.getElementById('barChart');
            const servers = s.by_server || [];
            if (servers.length === 0) {
              chart.innerHTML = '<p style="color:#6c757d;font-size:0.85rem;">No timing data available yet.</p>';
            } else {
              chart.innerHTML = servers.map((sv, i) => {
                const barPct = fhirMs > 0 ? ((sv.total_ms / fhirMs) * 100).toFixed(1) : 0;
                const label = sv.host || 'unknown';
                const countLabel = sv.count + ' req · ' + fmtMsPlain(sv.total_ms) + ' (' + barPct + '%)';
                return `<div class="bar-row">
                  <div class="bar-label" title="${label}">${label}</div>
                  <div class="bar-track-sm"><div class="bar-fill-sm s${i % 5}" style="width:${barPct}%"></div></div>
                  <div class="bar-value">${countLabel}</div>
                </div>`;
              }).join('');
            }

            // Warning if partial timing
            const warn = document.getElementById('warningBox');
            if (data.requests_with_timing < data.total_requests) {
              const missing = data.total_requests - data.requests_with_timing;
              warn.innerHTML = `<div class="warning-box">${missing} request(s) have no timing data (recorded before instrumentation was deployed).</div>`;
            } else {
              warn.innerHTML = '';
            }

            renderTable(data.requests);
            document.getElementById('results').style.display = 'block';
          }

          function renderTable(reqs) {
            const tbody = document.getElementById('reqBody');
            tbody.innerHTML = reqs.map(r => {
              const statusClass = r.status && r.status < 400 ? 'status-ok' : 'status-err';
              const ts = r.created_at ? new Date(r.created_at).toLocaleTimeString() : '';
              const testLabel = r.test_id
                ? `<span title="${r.test_id}">${r.test_id.split('-').slice(-1)[0] || r.test_id}</span>`
                : '<span style="color:#adb5bd">—</span>';
              return `<tr>
                <td class="url-cell" title="${r.url || ''}">${r.url || ''}</td>
                <td class="test-cell">${testLabel}</td>
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
            const keys = ['url', 'test_id', 'status', 'duration_ms', 'created_at'];
            reqs.sort((a, b) => {
              const va = a[keys[col]] ?? '';
              const vb = b[keys[col]] ?? '';
              if (va < vb) return sortDir[col] ? -1 : 1;
              if (va > vb) return sortDir[col] ? 1 : -1;
              return 0;
            });
            renderTable(reqs);
          }

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
