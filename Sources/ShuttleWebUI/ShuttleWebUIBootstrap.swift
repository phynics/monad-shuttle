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
      .queue-grid {
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
      error: null
    };

    const lanes = [
      ["running", "Running"],
      ["needs_input", "Needs Input"],
      ["integrating", "Integrating"],
      ["done", "Recently Done"]
    ];

    const byId = (id) => document.getElementById(id);

    async function getJSON(path) {
      const response = await fetch(path, { headers: { "Accept": "application/json" } });
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
          </article>
        `).join("")
        : `<div class="empty">No open conflicts</div>`;
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
      renderEvents();
    }

    async function load() {
      try {
        state.error = null;
        const [status, shards, conflicts, events] = await Promise.all([
          getJSON("/api/status"),
          getJSON("/api/shards"),
          getJSON("/api/conflicts"),
          getJSON("/api/events?limit=8")
        ]);
        state.status = status;
        state.shards = shards;
        state.conflicts = conflicts;
        state.events = events.items || [];
      } catch (error) {
        state.error = error;
      }
      render();
    }

    byId("refresh-button").addEventListener("click", load);
    load();
    setInterval(load, 10000);
    """
}
