public enum ShuttleWebUIBootstrap {
    public static let targetName = "ShuttleWebUI"
}

public enum ShuttleWebUIAsset: Equatable, Sendable {
    case html
    case css
    case javascript

    public var path: String {
        switch self {
        case .html:
            return "/"
        case .css:
            return "/assets/shuttle.css"
        case .javascript:
            return "/assets/shuttle.js"
        }
    }

    public var contentType: String {
        switch self {
        case .html:
            return "text/html; charset=utf-8"
        case .css:
            return "text/css; charset=utf-8"
        case .javascript:
            return "application/javascript; charset=utf-8"
        }
    }

    public var body: String {
        switch self {
        case .html:
            return ShuttleWebUIAssets.html
        case .css:
            return ShuttleWebUIAssets.css
        case .javascript:
            return ShuttleWebUIAssets.javascript
        }
    }
}

public enum ShuttleWebUIAssets {
    public static let html = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Shuttle Operator</title>
      <link rel="stylesheet" href="/assets/shuttle.css">
    </head>
    <body>
      <main class="shell">
        <header class="topbar">
          <div>
            <h1>Shuttle</h1>
            <p id="repo-line">Repository status loading</p>
          </div>
          <button id="refresh-button" class="icon-button" title="Refresh" aria-label="Refresh">Refresh</button>
        </header>

        <section class="status-band" aria-label="Server status">
          <div>
            <span class="label">Server</span>
            <strong id="server-state">loading</strong>
          </div>
          <div>
            <span class="label">Repository</span>
            <strong id="repo-state">loading</strong>
          </div>
          <div>
            <span class="label">Open conflicts</span>
            <strong id="conflict-count">0</strong>
          </div>
          <div>
            <span class="label">Active shards</span>
            <strong id="active-shard-count">0</strong>
          </div>
        </section>

        <section class="layout">
          <div class="main-column">
            <div class="section-heading">
              <h2>Queue</h2>
              <span id="queue-updated">Not loaded</span>
            </div>
            <div id="queue" class="queue-grid" aria-live="polite"></div>
          </div>

          <aside class="side-column">
            <section>
              <div class="section-heading">
                <h2>Conflicts</h2>
              </div>
              <div id="conflicts" class="stack"></div>
            </section>

            <section>
              <div class="section-heading">
                <h2>Push</h2>
              </div>
              <div id="push-panel" class="stack"></div>
            </section>

            <section>
              <div class="section-heading">
                <h2>Recent Events</h2>
              </div>
              <div id="events" class="stack"></div>
            </section>
          </aside>
        </section>
      </main>
      <script src="/assets/shuttle.js"></script>
    </body>
    </html>
    """

    public static let css = """
    :root {
      color-scheme: light;
      --bg: #f7f8fa;
      --panel: #ffffff;
      --ink: #17202a;
      --muted: #5d6875;
      --line: #d8dee6;
      --accent: #276749;
      --warning: #9a5b00;
      --danger: #a42424;
      --info: #275a8a;
      --shadow: 0 1px 2px rgba(20, 30, 42, 0.08);
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      background: var(--bg);
      color: var(--ink);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size: 14px;
      line-height: 1.45;
    }

    .shell {
      width: min(1440px, 100%);
      margin: 0 auto;
      padding: 20px;
    }

    .topbar,
    .status-band,
    .section-heading,
    .item-header,
    .item-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    .topbar {
      margin-bottom: 18px;
    }

    h1,
    h2,
    h3,
    p {
      margin: 0;
    }

    h1 {
      font-size: 26px;
      font-weight: 700;
    }

    h2 {
      font-size: 15px;
      font-weight: 700;
    }

    h3 {
      font-size: 14px;
      font-weight: 650;
    }

    .topbar p,
    .section-heading span,
    .label,
    .muted {
      color: var(--muted);
    }

    .icon-button,
    .action-button {
      min-height: 34px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      color: var(--ink);
      padding: 7px 10px;
      font: inherit;
      cursor: pointer;
      box-shadow: var(--shadow);
    }

    .icon-button:hover,
    .action-button:hover {
      border-color: #9aa8b8;
    }

    .status-band {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      margin-bottom: 18px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: var(--shadow);
    }

    .status-band > div {
      min-width: 0;
      padding: 14px 16px;
      border-right: 1px solid var(--line);
    }

    .status-band > div:last-child {
      border-right: 0;
    }

    .label {
      display: block;
      margin-bottom: 4px;
      font-size: 12px;
    }

    .layout {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 360px;
      gap: 18px;
      align-items: start;
    }

    .main-column,
    .side-column,
    .side-column section {
      min-width: 0;
    }

    .side-column {
      display: grid;
      gap: 18px;
    }

    .section-heading {
      margin-bottom: 10px;
    }

    .queue-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
    }

    .lane,
    .item {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: var(--shadow);
    }

    .lane {
      min-height: 180px;
      padding: 12px;
    }

    .lane-title {
      margin-bottom: 10px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
    }

    .stack {
      display: grid;
      gap: 8px;
    }

    .item {
      padding: 10px;
    }

    .item-header {
      align-items: start;
    }

    .item-row {
      margin-top: 8px;
      color: var(--muted);
      font-size: 12px;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 22px;
      border-radius: 999px;
      padding: 2px 8px;
      background: #eef2f6;
      color: var(--muted);
      font-size: 12px;
      white-space: nowrap;
    }

    .pill.running,
    .pill.ready,
    .pill.open {
      background: #e7f4ed;
      color: var(--accent);
    }

    .pill.needs_input,
    .pill.blocked,
    .pill.refreshing,
    .pill.integrating {
      background: #fff3d8;
      color: var(--warning);
    }

    .pill.failed,
    .pill.fatal {
      background: #fde8e8;
      color: var(--danger);
    }

    .empty,
    .error {
      border: 1px dashed var(--line);
      border-radius: 8px;
      padding: 12px;
      color: var(--muted);
      background: rgba(255, 255, 255, 0.58);
    }

    .error {
      border-color: #efb0b0;
      color: var(--danger);
    }

    .detail-layout {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 360px;
      gap: 18px;
      align-items: start;
    }

    .detail-panel {
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
      box-shadow: var(--shadow);
    }

    .detail-panel + .detail-panel,
    .detail-stack {
      margin-top: 12px;
    }

    .detail-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 12px;
    }

    .form-stack {
      display: grid;
      gap: 8px;
      margin-top: 12px;
    }

    textarea,
    input,
    select {
      width: 100%;
      min-height: 36px;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px;
      color: var(--ink);
      background: #ffffff;
      font: inherit;
    }

    textarea {
      min-height: 86px;
      resize: vertical;
    }

    pre {
      overflow: auto;
      max-height: 260px;
      margin: 8px 0 0;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #f3f5f7;
      padding: 10px;
      white-space: pre-wrap;
      word-break: break-word;
    }

    a {
      color: var(--info);
      text-decoration: none;
    }

    a:hover {
      text-decoration: underline;
    }

    @media (max-width: 900px) {
      .status-band,
      .layout,
      .queue-grid,
      .detail-layout {
        grid-template-columns: 1fr;
      }

      .status-band > div {
        border-right: 0;
        border-bottom: 1px solid var(--line);
      }

      .status-band > div:last-child {
        border-bottom: 0;
      }

      .shell {
        padding: 14px;
      }
    }
    """

    public static let javascript = """
    const state = {
      status: null,
      shards: [],
      conflicts: [],
      events: [],
      config: null,
      shard: null,
      shardEvents: [],
      shardLogs: [],
      completionReport: null,
      error: null
    };

    const lanes = [
      ["running", "Running"],
      ["needs_input", "Needs Input"],
      ["integrating", "Integrating"],
      ["done", "Recently Done"]
    ];

    const byId = (id) => document.getElementById(id);
    const routeShardID = (() => {
      const match = window.location.pathname.match(new RegExp("^/shards/([^/]+)$"));
      return match ? decodeURIComponent(match[1]) : null;
    })();

    async function getJSON(path) {
      const response = await fetch(path, { headers: { "Accept": "application/json" } });
      if (!response.ok) {
        throw new Error(`${path} returned ${response.status}`);
      }
      return response.json();
    }

    async function postJSON(path, body) {
      const headers = { "Content-Type": "application/json", "Accept": "application/json" };
      if (path === "/api/pushes") {
        headers["Idempotency-Key"] = `ui-push-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      }
      const response = await fetch(path, {
        method: "POST",
        headers,
        body: body === undefined ? undefined : JSON.stringify(body)
      });
      if (!response.ok) {
        throw new Error(`${path} returned ${response.status}`);
      }
      return response.json();
    }

    async function optionalJSON(path) {
      const response = await fetch(path, { headers: { "Accept": "application/json" } });
      if (response.status === 404) {
        return null;
      }
      if (!response.ok) {
        throw new Error(`${path} returned ${response.status}`);
      }
      return response.json();
    }

    function classNameFor(value) {
      return String(value || "").replace(/[^a-z0-9_ -]/gi, "").replaceAll(" ", "_");
    }

    function renderPill(value) {
      return `<span class="pill ${classNameFor(value)}">${value || "unknown"}</span>`;
    }

    function escapeHTML(value) {
      return String(value ?? "").replace(/[&<>"']/g, (character) => ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\\\"": "&quot;",
        "'": "&#39;"
      }[character]));
    }

    function renderShard(shard) {
      return `
        <article class="item">
          <div class="item-header">
            <h3><a href="/shards/${encodeURIComponent(shard.id)}">${escapeHTML(shard.title)}</a></h3>
            ${renderPill(shard.state)}
          </div>
          <div class="item-row">
            <span>${escapeHTML(shard.branchName || shard.id)}</span>
            <span>${escapeHTML(shard.containerStatus || "container unknown")}</span>
          </div>
        </article>
      `;
    }

    function renderQueue() {
      const queue = byId("queue");
      queue.innerHTML = lanes.map(([stateName, title]) => {
        const items = state.shards.filter((shard) => shard.state === stateName);
        return `
          <section class="lane">
            <div class="lane-title">${title} (${items.length})</div>
            <div class="stack">
              ${items.length ? items.map(renderShard).join("") : `<div class="empty">No ${title.toLowerCase()} shards</div>`}
            </div>
          </section>
        `;
      }).join("");
    }

    function renderConflicts() {
      const conflicts = state.conflicts.filter((conflict) => conflict.state === "open");
      byId("conflicts").innerHTML = conflicts.length
        ? conflicts.map((conflict) => `
          <article class="item">
            <div class="item-header">
              <h3>${escapeHTML(conflict.kind)}</h3>
              ${renderPill(conflict.state)}
            </div>
            <div class="item-row">
              <span>${escapeHTML(conflict.id)}</span>
              <span>${conflict.blocking ? "blocking" : "non-blocking"}</span>
            </div>
            <div class="detail-actions">
              <button class="action-button resolve-conflict-button" data-conflict-id="${escapeHTML(conflict.id)}" type="button">Resolve</button>
            </div>
          </article>
        `).join("")
        : `<div class="empty">No open conflicts</div>`;

      document.querySelectorAll(".resolve-conflict-button").forEach((button) => {
        button.addEventListener("click", async () => {
          await postJSON(`/api/conflicts/${encodeURIComponent(button.dataset.conflictId)}/resolve`, { resolutionShardID: null });
          await load();
        });
      });
    }

    function renderPushPanel() {
      const targets = state.config?.pushTargets || [];
      const repoState = state.status?.repository?.integrationState || "unknown";
      byId("push-panel").innerHTML = targets.length
        ? targets.map((target) => `
          <article class="item">
            <div class="item-header">
              <h3>${escapeHTML(target.name)}</h3>
              ${renderPill(target.branch)}
            </div>
            <div class="item-row">
              <span>${escapeHTML(target.remote)}</span>
              <span>${escapeHTML(target.branch)}</span>
            </div>
            <div class="detail-actions">
              <button class="action-button push-button" data-target-name="${escapeHTML(target.name)}" type="button">Push shuttle-main</button>
            </div>
          </article>
        `).join("")
        : `<div class="empty">No push targets configured</div>`;

      document.querySelectorAll(".push-button").forEach((button) => {
        button.addEventListener("click", async () => {
          if (repoState !== "open") {
            const proceed = window.confirm(`Repository state is ${repoState}. Push anyway?`);
            if (!proceed) {
              return;
            }
          }
          await postJSON("/api/pushes", {
            targetName: button.dataset.targetName,
            ref: { kind: "shuttle_main", shardID: null }
          });
          await load();
        });
      });
    }

    function renderEvents() {
      byId("events").innerHTML = state.events.length
        ? state.events.slice(0, 8).map((event) => `
          <article class="item">
            <div class="item-header">
              <h3>${escapeHTML(event.eventType)}</h3>
              <span class="pill">${escapeHTML(event.entityType)}</span>
            </div>
            <div class="item-row">
              <span>${escapeHTML(event.entityID)}</span>
              <span>${new Date(event.timestamp).toLocaleTimeString()}</span>
            </div>
          </article>
        `).join("")
        : `<div class="empty">No events yet</div>`;
    }

    function renderCompletionReport() {
      const report = state.completionReport;
      if (!report) {
        return `<div class="empty">No completion report</div>`;
      }
      return `
        <div class="detail-panel">
          <div class="section-heading"><h2>Completion Report</h2><span>${new Date(report.createdAt).toLocaleString()}</span></div>
          <p>${escapeHTML(report.summary)}</p>
          <div class="detail-stack">
            <h3>Files</h3>
            ${report.filesChanged.length ? `<pre>${escapeHTML(report.filesChanged.join("\\n"))}</pre>` : `<div class="empty">No files listed</div>`}
          </div>
          <div class="detail-stack">
            <h3>Checks</h3>
            ${report.checks.length ? `<pre>${escapeHTML(report.checks.map((check) => `${check.kind}: ${check.name} - ${check.status}`).join("\\n"))}</pre>` : `<div class="empty">No checks listed</div>`}
          </div>
          <div class="detail-stack">
            <h3>Risks</h3>
            ${report.risks.length ? `<pre>${escapeHTML(report.risks.join("\\n"))}</pre>` : `<div class="empty">No risks listed</div>`}
          </div>
        </div>
      `;
    }

    function renderShardActions() {
      const shard = state.shard;
      if (!shard) {
        return "";
      }
      if (shard.state === "needs_input") {
        return `
          <form id="answer-form" class="form-stack">
            <textarea id="answer-text" name="answer" placeholder="Answer"></textarea>
            <button class="action-button" type="submit">Answer</button>
          </form>
        `;
      }
      if (shard.state === "running") {
        return `
          <div class="detail-actions">
            <button id="request-finish-button" class="action-button" type="button">Request Finish</button>
            <button id="abandon-button" class="action-button" type="button">Abandon</button>
          </div>
        `;
      }
      return `<div class="empty">No actions available for ${escapeHTML(shard.state)}</div>`;
    }

    function renderShardDetail() {
      const root = document.querySelector(".shell");
      const shard = state.shard;
      if (!shard) {
        root.innerHTML = `<div class="error">${state.error ? escapeHTML(state.error.message) : "Shard not found"}</div>`;
        return;
      }

      root.innerHTML = `
        <header class="topbar">
          <div>
            <h1>${escapeHTML(shard.title)}</h1>
            <p><a href="/">Queue</a> / ${escapeHTML(shard.id)}</p>
          </div>
          <button id="refresh-button" class="icon-button" title="Refresh" aria-label="Refresh">Refresh</button>
        </header>
        <section class="detail-layout">
          <div>
            <section class="detail-panel">
              <div class="item-header">
                <h2>Shard</h2>
                ${renderPill(shard.state)}
              </div>
              <div class="item-row"><span>Branch</span><span>${escapeHTML(shard.branchName || "not created")}</span></div>
              <div class="item-row"><span>Worktree</span><span>${escapeHTML(shard.worktreePath || "not created")}</span></div>
              <div class="item-row"><span>Container</span><span>${escapeHTML(shard.containerStatus || "unknown")}</span></div>
              <pre>${escapeHTML(shard.spec)}</pre>
              ${renderShardActions()}
            </section>
            ${renderCompletionReport()}
          </div>
          <aside>
            <section class="detail-panel">
              <div class="section-heading"><h2>Events</h2></div>
              <div class="stack">
                ${state.shardEvents.length ? state.shardEvents.map((event) => `
                  <article class="item">
                    <div class="item-header"><h3>${escapeHTML(event.eventType)}</h3>${renderPill(event.entityType)}</div>
                    <div class="item-row"><span>${new Date(event.timestamp).toLocaleTimeString()}</span></div>
                  </article>
                `).join("") : `<div class="empty">No shard events</div>`}
              </div>
            </section>
            <section class="detail-panel">
              <div class="section-heading"><h2>Logs</h2></div>
              <div class="stack">
                ${state.shardLogs.length ? state.shardLogs.map((log) => `
                  <article class="item">
                    <div class="item-header"><h3>${escapeHTML(log.command.join(" "))}</h3>${renderPill(String(log.exitCode))}</div>
                    <pre>${escapeHTML([log.stdout, log.stderr].filter(Boolean).join("\\n"))}</pre>
                  </article>
                `).join("") : `<div class="empty">No logs indexed</div>`}
              </div>
            </section>
          </aside>
        </section>
      `;

      byId("refresh-button").addEventListener("click", loadDetail);
      const answerForm = byId("answer-form");
      if (answerForm) {
        answerForm.addEventListener("submit", async (event) => {
          event.preventDefault();
          await postJSON(`/api/shards/${encodeURIComponent(shard.id)}/answer`, { answer: byId("answer-text").value });
          await loadDetail();
        });
      }
      const requestFinishButton = byId("request-finish-button");
      if (requestFinishButton) {
        requestFinishButton.addEventListener("click", async () => {
          await postJSON(`/api/shards/${encodeURIComponent(shard.id)}/request-finish`);
          await loadDetail();
        });
      }
      const abandonButton = byId("abandon-button");
      if (abandonButton) {
        abandonButton.addEventListener("click", async () => {
          const reason = window.prompt("Reason");
          if (reason) {
            await postJSON(`/api/shards/${encodeURIComponent(shard.id)}/abandon`, { reason });
            await loadDetail();
          }
        });
      }
    }

    function renderStatus() {
      const repository = state.status?.repository;
      byId("server-state").innerHTML = renderPill(state.status?.serverState || "unknown");
      byId("repo-state").innerHTML = renderPill(repository?.integrationState || "unknown");
      byId("repo-line").textContent = repository
        ? `${repository.sourceBranch || "source"} -> ${repository.shuttleMainBranch || "shuttle-main"}`
        : "Repository unavailable";
      byId("conflict-count").textContent = state.conflicts.filter((conflict) => conflict.state === "open").length;
      byId("active-shard-count").textContent = state.shards.filter((shard) => ["running", "needs_input", "integrating"].includes(shard.state)).length;
      byId("queue-updated").textContent = state.error ? "Load failed" : `Updated ${new Date().toLocaleTimeString()}`;
    }

    function render() {
      if (state.error) {
        byId("queue").innerHTML = `<div class="error">${escapeHTML(state.error.message)}</div>`;
      }
      renderStatus();
      renderQueue();
      renderConflicts();
      renderPushPanel();
      renderEvents();
    }

    async function load() {
      try {
        state.error = null;
        const [status, shards, conflicts, events, config] = await Promise.all([
          getJSON("/api/status"),
          getJSON("/api/shards"),
          getJSON("/api/conflicts"),
          getJSON("/api/events?limit=8"),
          getJSON("/api/config")
        ]);
        state.status = status;
        state.shards = shards;
        state.conflicts = conflicts;
        state.events = events.items || [];
        state.config = config;
      } catch (error) {
        state.error = error;
      }
      render();
    }

    async function loadDetail() {
      try {
        state.error = null;
        const encodedID = encodeURIComponent(routeShardID);
        const [shard, events, logs, report] = await Promise.all([
          getJSON(`/api/shards/${encodedID}`),
          getJSON(`/api/shards/${encodedID}/events?limit=20`),
          getJSON(`/api/shards/${encodedID}/logs?limit=20`),
          optionalJSON(`/api/shards/${encodedID}/completion-report`)
        ]);
        state.shard = shard;
        state.shardEvents = events.items || [];
        state.shardLogs = logs.items || [];
        state.completionReport = report;
      } catch (error) {
        state.error = error;
      }
      renderShardDetail();
    }

    if (routeShardID) {
      loadDetail();
      setInterval(loadDetail, 10000);
    } else {
      byId("refresh-button").addEventListener("click", load);
      load();
      setInterval(load, 10000);
    }
    """
}
