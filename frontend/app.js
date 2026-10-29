// SocialSpork dashboard: a small hash-routed SPA over the /api endpoints.
// Pages and KPIs come from GET /api/brands/{id}/config, so every industry renders from the same code.

const API = "/api";

const ICONS = {
  overview: '<rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/>',
  reviews: '<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.9L12 17.8 5.8 21l1.2-6.9-5-4.9 6.9-1z"/>',
  ai_replies: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
  listings: '<path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/>',
  reports: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
  tickets: '<path d="M3 8a2 2 0 0 0 0 4v4a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4a2 2 0 0 1 0-4V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2z"/><path d="M13 5v2M13 11v2M13 17v1"/>',
  competitors: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
  surveys: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V3h6v1M9 11h6M9 15h4"/>',
  social: '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="M8.6 13.5l6.8 4M15.4 6.5l-6.8 4"/>',
  alerts: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
  marketplace_sales: '<path d="M3 17l6-6 4 4 8-8"/><path d="M14 7h7v7"/>',
  marketplace_ops: '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l2 2M9 2h6"/>',
  marketplace_funnel: '<path d="M3 4h18l-7 8.5V19l-4 2v-8.5z"/>',
  marketplace_ads: '<path d="M3 11v3a1 1 0 0 0 1 1h3l5 4V6L7 10H4a1 1 0 0 0-1 1z"/><path d="M16 8a5 5 0 0 1 0 8M19 5a9 9 0 0 1 0 14"/>',
  marketplace_discounts: '<path d="M19 5L5 19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>',
  store_uptime: '<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>',
  stock_outs: '<path d="M21 8l-9-5-9 5v8l9 5 9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>',
  reconciliation: '<rect x="2" y="6" width="20" height="14" rx="2"/><path d="M2 10h20M6 15h4"/><path d="M6 6V4h12v2"/>',
};

const PLATFORM_COLORS = {
  google: "#408fca", zomato: "#e23744", swiggy: "#fc8019", magicpin: "#e91e63",
  tripadvisor: "#00aa6c", booking: "#003580", makemytrip: "#d63b3b", facebook: "#1877f2",
  instagram: "#c13584", practo: "#28328c", justdial: "#ff6f00", survey: "#64748b",
};
const SERIES = ["#408fca", "#0b1229", "#f5a524", "#12a150", "#8b5cf6", "#e5484d"];

// Modules that have a dedicated page; everything else with KPIs uses the generic module page.
const OVERVIEW_KPIS = ["avg_rating", "review_count", "response_rate", "negative_review_count",
  "gross_revenue", "delivered_orders", "online_pct", "avg_prep_time"];
const MODULE_PRIMARY = {
  marketplace_sales: "gross_revenue", marketplace_ops: "avg_prep_time", marketplace_funnel: "menu_views",
  marketplace_ads: "ad_roi", marketplace_discounts: "discount_pct_revenue", store_uptime: "online_pct",
  stock_outs: "stock_out_items", listings: "listing_rating", tickets: "open_tickets",
};

const state = {
  brands: [], brandId: null, config: null, locations: [],
  locationId: "", platform: "", days: 30, charts: [],
};

// ---------- helpers ----------
const $ = (s, el = document) => el.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const icon = (name) => `<svg viewBox="0 0 24 24">${ICONS[name] || ICONS.overview}</svg>`;
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
};

async function api(path, params = {}, opts = {}) {
  const url = new URL(API + path, location.origin);
  Object.entries(params).forEach(([k, v]) => { if (v !== "" && v != null) url.searchParams.set(k, v); });
  const res = await fetch(url, opts);
  if (!res.ok) throw new Error(`${res.status} ${(await res.json().catch(() => ({}))).detail || res.statusText}`);
  return res.json();
}

function isoDate(d) { return d.toISOString().slice(0, 10); }
function range() {
  const end = new Date();
  const start = new Date(); start.setDate(end.getDate() - (state.days - 1));
  return { start: isoDate(start), end: isoDate(end) };
}
function filterParams(extra = {}) {
  return { ...range(), location_id: state.locationId, platform: state.platform, ...extra };
}

const inr = new Intl.NumberFormat("en-IN", { maximumFractionDigits: 0 });
function compactINR(v) {
  const a = Math.abs(v);
  if (a >= 1e7) return `₹${(v / 1e7).toFixed(2)} Cr`;
  if (a >= 1e5) return `₹${(v / 1e5).toFixed(2)} L`;
  if (a >= 1e3) return `₹${(v / 1e3).toFixed(1)}K`;
  return `₹${inr.format(v)}`;
}
function fmt(value, unit, compact = true) {
  if (value == null) return "—";
  const v = Number(value);
  switch (unit) {
    case "currency": return compact ? compactINR(v) : `₹${inr.format(v)}`;
    case "percent": return `${v.toFixed(1)}%`;
    case "rating": return v.toFixed(2);
    case "ratio": return `${v.toFixed(2)}x`;
    case "seconds": { const m = Math.floor(v / 60), s = Math.round(v % 60); return `${m}m ${String(s).padStart(2, "0")}s`; }
    case "minutes": return `${v.toFixed(1)} min`;
    default: return compact && Math.abs(v) >= 1e5 ? `${(v / 1e5).toFixed(2)} L` : inr.format(Math.round(v));
  }
}
function changeChip(k) {
  if (k.change_pct == null) return `<span class="chip flat">—</span>`;
  const good = (k.change_pct >= 0) === k.higher_is_better;
  const cls = Math.abs(k.change_pct) < 0.05 ? "flat" : good ? "up" : "down";
  return `<span class="chip ${cls}">${k.change_pct >= 0 ? "▲" : "▼"} ${Math.abs(k.change_pct).toFixed(1)}%</span>`;
}
function stars(r) {
  const n = Math.round(Number(r) || 0);
  return `<span class="stars">${"★".repeat(n)}<span class="off">${"★".repeat(5 - n)}</span></span>`;
}
function timeAgo(ts) {
  const diff = (Date.now() - new Date(ts)) / 1000;
  if (diff < 60) return "just now";
  if (diff < 3600) return `${Math.max(1, Math.round(diff / 60))}m ago`;
  if (diff < 86400) return `${Math.round(diff / 3600)}h ago`;
  if (diff < 86400 * 30) return `${Math.round(diff / 86400)}d ago`;
  return new Date(ts).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}
function platformPill(code) {
  return `<span class="pill"><span class="dot" style="background:${PLATFORM_COLORS[code] || "#94a3b8"}"></span>${esc(code)}</span>`;
}
function toast(msg) {
  const t = document.createElement("div"); t.className = "toast"; t.textContent = msg;
  document.body.appendChild(t); setTimeout(() => t.remove(), 2200);
}
function kpiMeta(code) { return state.config.kpis.find((k) => k.code === code); }
function moduleName(code) { return state.config.modules.find((m) => m.code === code)?.name || code; }

// ---------- charts ----------
Chart.defaults.font.family = "Inter, sans-serif";
Chart.defaults.color = "#64748b";
Chart.defaults.plugins.legend.labels.boxWidth = 10;
Chart.defaults.plugins.legend.labels.usePointStyle = true;

function destroyCharts() { state.charts.forEach((c) => c.destroy()); state.charts = []; }
function chart(canvas, config) { const c = new Chart(canvas, config); state.charts.push(c); return c; }

function lineChart(canvas, labels, datasets, unit) {
  return chart(canvas, {
    type: "line",
    data: {
      labels,
      datasets: datasets.map((d, i) => ({
        borderColor: d.color || SERIES[i], backgroundColor: (d.color || SERIES[i]) + "1f",
        fill: datasets.length === 1, tension: 0.35, pointRadius: 0, pointHoverRadius: 4, borderWidth: 2, ...d,
      })),
    },
    options: {
      maintainAspectRatio: false, interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { display: datasets.length > 1, position: "top", align: "end" },
        tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${fmt(c.parsed.y, unit, false)}` } },
      },
      scales: {
        x: { grid: { display: false }, ticks: { maxTicksLimit: 8 } },
        y: { grid: { color: "#eef1f5" }, border: { display: false }, ticks: { callback: (v) => fmt(v, unit) } },
      },
    },
  });
}

function shortDate(d) { return new Date(d).toLocaleDateString("en-IN", { day: "numeric", month: "short" }); }

// ---------- shell ----------
function renderSidebar() {
  const mods = state.config.modules;
  const route = currentRoute();
  const link = (m) => {
    const hasData = m.code === "overview" || m.code === "reviews" || state.config.kpis.some((k) => k.module === m.code);
    return `<a class="nav-item ${route === m.code ? "active" : ""}" href="#/${m.code}" title="${esc(m.name)}">
      ${icon(m.code)}<span>${esc(m.name)}</span>${hasData ? "" : '<em class="soon">soon</em>'}</a>`;
  };
  const common = mods.filter((m) => m.scope === "common");
  const industry = mods.filter((m) => m.scope === "industry");
  $("#sidebar").innerHTML =
    `<div class="nav-group">Reputation</div>${common.map(link).join("")}` +
    (industry.length ? `<div class="nav-group">Marketplace</div>${industry.map(link).join("")}` : "");
}

function renderFilters() {
  $("#locationSelect").innerHTML = `<option value="">All outlets (${state.locations.length})</option>` +
    state.locations.map((l) => `<option value="${l.id}">${esc(l.name)}</option>`).join("");
  $("#locationSelect").value = state.locationId;
  $("#platformSelect").innerHTML = `<option value="">All platforms</option>` +
    state.config.connected_platforms.map((p) => `<option value="${p.code}">${esc(p.name)}</option>`).join("");
  $("#platformSelect").value = state.platform;
}

async function loadBrand(id) {
  state.brandId = id; store.set("ss_brand", id);
  state.locationId = ""; state.platform = "";
  const [config, locations] = await Promise.all([api(`/brands/${id}/config`), api(`/brands/${id}/locations`)]);
  state.config = config; state.locations = locations;
  $("#brandIndustry").textContent = config.brand.industry_name;
  renderFilters();
  const route = currentRoute();
  if (!config.modules.some((m) => m.code === route)) location.hash = "#/overview";
  else render();
}

function currentRoute() { return (location.hash.replace(/^#\//, "") || "overview").split("?")[0]; }

async function render() {
  if (!state.config) return;
  renderSidebar();
  destroyCharts();
  const route = currentRoute();
  const page = $("#page");
  page.innerHTML = `<div class="loading">Loading…</div>`;
  $("#pageTitle").textContent = moduleName(route);
  $("#pageSub").textContent = `${state.config.brand.name} · ${state.locationId ? state.locations.find((l) => l.id == state.locationId)?.name : "All outlets"} · last ${state.days} days`;
  document.body.classList.remove("nav-open");
  try {
    if (route === "overview") await renderOverview(page);
    else if (route === "reviews") await renderReviews(page);
    else if (state.config.kpis.some((k) => k.module === route)) await renderModule(page, route);
    else renderComingSoon(page, route);
  } catch (e) {
    page.innerHTML = `<div class="card empty-state"><h3>Couldn't load this page</h3><p>${esc(e.message)}</p></div>`;
  }
}

function kpiCards(kpis, moduleIcon) {
  if (!kpis.length) return "";
  if (moduleIcon) {
    const order = state.config.kpis.map((k) => k.code);
    kpis = [...kpis].sort((a, b) => order.indexOf(a.code) - order.indexOf(b.code));
  }
  return `<div class="grid kpis">${kpis.map((k) => `
    <div class="card kpi">
      <div class="kpi-top"><span class="kpi-label">${esc(k.name)}</span><span class="kpi-icon">${icon(moduleIcon || k.module)}</span></div>
      <div class="kpi-value">${fmt(k.value, k.unit)}</div>
      <div class="kpi-foot">${changeChip(k)}<span>vs previous ${state.days} days</span></div>
    </div>`).join("")}</div>`;
}

// ---------- overview ----------
async function renderOverview(page) {
  const hasMarketplace = state.config.modules.some((m) => m.code === "marketplace_sales");
  const trendKpi = hasMarketplace ? "gross_revenue" : "avg_rating";
  const [kpiRes, summary, trend, board, negatives] = await Promise.all([
    api(`/brands/${state.brandId}/kpis`, filterParams()),
    api(`/brands/${state.brandId}/reviews/summary`, range()),
    api(`/brands/${state.brandId}/kpis/${trendKpi}/trend`, filterParams()),
    api(`/brands/${state.brandId}/leaderboard/avg_rating`, range()),
    api(`/brands/${state.brandId}/reviews`, { location_id: state.locationId, platform: state.platform, max_rating: 2, limit: 5 }),
  ]);
  const byCode = Object.fromEntries(kpiRes.kpis.map((k) => [k.code, k]));
  const cards = OVERVIEW_KPIS.map((c) => byCode[c]).filter(Boolean);
  const trendMeta = kpiMeta(trendKpi);

  page.innerHTML = `
    ${kpiCards(cards)}
    <div class="grid cols-2">
      <div class="card"><div class="card-head"><h3>${esc(trendMeta.name)} trend</h3></div><div class="chart-box"><canvas id="cTrend"></canvas></div></div>
      <div class="card"><div class="card-head"><h3>Reviews by platform</h3><span class="muted">${inr.format(summary.total)} reviews</span></div><div class="chart-box"><canvas id="cPlat"></canvas></div></div>
    </div>
    <div class="grid cols-2-even" style="margin-top:16px">
      <div class="card"><div class="card-head"><h3>Rating distribution</h3><span class="muted">avg ${summary.avg_rating ?? "—"} ★</span></div><div class="chart-box sm"><canvas id="cDist"></canvas></div></div>
      <div class="card"><div class="card-head"><h3>Outlet leaderboard</h3><span class="muted">by average rating</span></div>${leaderboardTable(board, "rating")}</div>
    </div>
    <div class="card" style="margin-top:16px">
      <div class="card-head"><h3>Recent negative reviews</h3><a href="#/reviews" class="muted">Open inbox →</a></div>
      ${negatives.length ? negatives.map(reviewRow).join("") : `<p class="muted">No negative reviews in this filter. 🎉</p>`}
    </div>`;

  lineChart($("#cTrend"), trend.map((p) => shortDate(p.date)), [{ label: trendMeta.name, data: trend.map((p) => p.value) }], trendMeta.unit);
  chart($("#cPlat"), {
    type: "doughnut",
    data: {
      labels: summary.by_platform.map((p) => p.platform),
      datasets: [{ data: summary.by_platform.map((p) => p.count), backgroundColor: summary.by_platform.map((p) => PLATFORM_COLORS[p.platform] || "#94a3b8"), borderWidth: 0 }],
    },
    options: { maintainAspectRatio: false, cutout: "68%", plugins: { legend: { position: "bottom" } } },
  });
  const dist = [5, 4, 3, 2, 1].map((s) => summary.by_rating.find((r) => r.stars === s)?.count || 0);
  chart($("#cDist"), {
    type: "bar",
    data: { labels: ["5★", "4★", "3★", "2★", "1★"], datasets: [{ data: dist, backgroundColor: ["#12a150", "#62c26f", "#f5a524", "#f07d4a", "#e5484d"], borderRadius: 6, barThickness: 18 }] },
    options: {
      indexAxis: "y", maintainAspectRatio: false, plugins: { legend: { display: false } },
      scales: { x: { grid: { color: "#eef1f5" }, border: { display: false } }, y: { grid: { display: false } } },
    },
  });
  bindReplyBoxes(page);
}

function leaderboardTable(rows, unit) {
  const ranked = rows.filter((r) => r.value != null);
  if (!ranked.length) return `<p class="muted">No data for this period.</p>`;
  const max = Math.max(...ranked.map((r) => Math.abs(r.value)));
  return `<table><thead><tr><th>#</th><th>Outlet</th><th>City</th><th class="num">Value</th></tr></thead><tbody>
    ${ranked.map((r, i) => `<tr>
      <td><span class="rank ${i < 3 ? "top" : ""}">${i + 1}</span></td>
      <td>${esc(r.name)}</td><td class="muted">${esc(r.city || "")}</td>
      <td class="num"><div class="bar-cell"><div class="bar" style="width:${Math.round((Math.abs(r.value) / max) * 80)}px"></div>${fmt(r.value, unit)}</div></td>
    </tr>`).join("")}</tbody></table>`;
}

// ---------- generic module page ----------
async function renderModule(page, module) {
  const modKpis = state.config.kpis.filter((k) => k.module === module);
  const selected = new URLSearchParams(location.hash.split("?")[1] || "").get("kpi")
    || MODULE_PRIMARY[module] || modKpis[0].code;
  const meta = kpiMeta(selected) || modKpis[0];
  const platforms = state.platform ? [] : state.config.connected_platforms;

  const [kpiRes, trend, board, ...perPlatform] = await Promise.all([
    api(`/brands/${state.brandId}/kpis`, filterParams({ module })),
    api(`/brands/${state.brandId}/kpis/${meta.code}/trend`, filterParams()),
    api(`/brands/${state.brandId}/leaderboard/${meta.code}`, range()),
    ...platforms.map((p) => api(`/brands/${state.brandId}/kpis/${meta.code}/trend`, filterParams({ platform: p.code }))),
  ]);
  const platformSeries = platforms
    .map((p, i) => ({ platform: p, points: perPlatform[i] }))
    .filter((s) => s.points.length);

  const funnel = module === "marketplace_funnel" ? funnelCard(kpiRes.kpis) : "";
  page.innerHTML = `
    ${kpiCards(kpiRes.kpis, module)}
    ${funnel}
    <div class="card">
      <div class="card-head">
        <h3>${esc(meta.name)} trend</h3>
        <div class="tabs">${modKpis.map((k) => `<button class="tab ${k.code === meta.code ? "active" : ""}" data-kpi="${k.code}">${esc(k.name)}</button>`).join("")}</div>
      </div>
      <div class="chart-box"><canvas id="cTrend"></canvas></div>
    </div>
    <div class="card" style="margin-top:16px">
      <div class="card-head"><h3>Outlets ranked by ${esc(meta.name)}</h3><span class="muted">${meta.higher_is_better ? "higher is better" : "lower is better"}</span></div>
      ${leaderboardTable(board, meta.unit)}
    </div>`;

  const labels = trend.map((p) => shortDate(p.date));
  const datasets = platformSeries.length > 1
    ? platformSeries.map((s) => {
        const byDate = Object.fromEntries(s.points.map((p) => [p.date, p.value]));
        return { label: s.platform.name, data: trend.map((p) => byDate[p.date] ?? null), color: PLATFORM_COLORS[s.platform.code], fill: false };
      })
    : [{ label: meta.name, data: trend.map((p) => p.value) }];
  lineChart($("#cTrend"), labels, datasets, meta.unit);

  page.querySelectorAll(".tab").forEach((b) => b.addEventListener("click", () => {
    location.hash = `#/${module}?kpi=${b.dataset.kpi}`;
  }));
}

function funnelCard(kpis) {
  const by = Object.fromEntries(kpis.map((k) => [k.code, k.value]));
  const steps = [["Impressions", by.impressions], ["Menu views", by.menu_views], ["Add to cart", by.add_to_cart], ["Orders", by.funnel_orders]];
  if (!steps[0][1]) return "";
  return `<div class="card" style="margin-bottom:16px"><div class="card-head"><h3>Customer funnel</h3><span class="muted">step conversion</span></div>
    ${steps.map(([label, v], i) => `<div class="funnel-row">
      <span>${label}</span>
      <div><div class="funnel-bar" style="width:${Math.max(6, (v / steps[0][1]) * 100)}%">${fmt(v, "count")}</div></div>
      <span class="funnel-conv">${i ? `${((v / steps[i - 1][1]) * 100).toFixed(1)}%` : ""}</span>
    </div>`).join("")}</div>`;
}

// ---------- reviews inbox ----------
const reviewFilters = { rating: "", status: "", q: "", offset: 0 };

async function renderReviews(page) {
  const summary = await api(`/brands/${state.brandId}/reviews/summary`, range());
  const responseRate = summary.total ? (summary.replied / summary.total) * 100 : 0;
  page.innerHTML = `
    <div class="stat-strip">
      ${[["Reviews", inr.format(summary.total)], ["Average rating", `${summary.avg_rating ?? "—"} ★`],
         ["Replied", inr.format(summary.replied)], ["Pending", inr.format(summary.pending)], ["Response rate", `${responseRate.toFixed(1)}%`]]
        .map(([l, v]) => `<div class="card kpi"><span class="kpi-label">${l}</span><div class="kpi-value">${v}</div></div>`).join("")}
    </div>
    <div class="card">
      <div class="toolbar">
        <input id="rq" type="search" placeholder="Search review text…" value="${esc(reviewFilters.q)}">
        <select id="rRating">
          <option value="">All ratings</option><option value="neg">1–2 ★</option><option value="mid">3 ★</option><option value="pos">4–5 ★</option>
        </select>
        <select id="rStatus">
          <option value="">Any status</option><option value="pending">Pending</option><option value="drafted">Drafted</option><option value="replied">Replied</option>
        </select>
      </div>
      <div id="reviewList"><div class="loading">Loading…</div></div>
      <div style="text-align:center;margin-top:12px"><button class="btn light" id="moreBtn">Load more</button></div>
    </div>`;
  $("#rRating").value = reviewFilters.rating;
  $("#rStatus").value = reviewFilters.status;
  reviewFilters.offset = 0;

  let timer;
  $("#rq").addEventListener("input", (e) => { clearTimeout(timer); timer = setTimeout(() => { reviewFilters.q = e.target.value; loadReviews(true); }, 300); });
  $("#rRating").addEventListener("change", (e) => { reviewFilters.rating = e.target.value; loadReviews(true); });
  $("#rStatus").addEventListener("change", (e) => { reviewFilters.status = e.target.value; loadReviews(true); });
  $("#moreBtn").addEventListener("click", () => loadReviews(false));
  await loadReviews(true);
}

async function loadReviews(reset) {
  if (reset) reviewFilters.offset = 0;
  const ratingRange = { neg: [1, 2], mid: [3, 3], pos: [4, 5] }[reviewFilters.rating] || [];
  const rows = await api(`/brands/${state.brandId}/reviews`, {
    location_id: state.locationId, platform: state.platform, reply_status: reviewFilters.status, q: reviewFilters.q,
    min_rating: ratingRange[0], max_rating: ratingRange[1], limit: 25, offset: reviewFilters.offset,
  });
  reviewFilters.offset += rows.length;
  const list = $("#reviewList");
  const html = rows.map(reviewRow).join("");
  if (reset) list.innerHTML = html || `<div class="empty-state"><h3>No reviews match these filters</h3></div>`;
  else list.insertAdjacentHTML("beforeend", html);
  $("#moreBtn").style.display = rows.length < 25 ? "none" : "";
  bindReplyBoxes(list);
}

function reviewRow(r) {
  return `<div class="review" data-id="${r.id}">
    <div class="review-head">
      <span class="review-author">${esc(r.author_name || "Anonymous")}</span>${stars(r.rating)}${platformPill(r.platform)}
      <span class="status ${r.reply_status}">${r.reply_status}</span>
      <span class="review-meta">${esc(r.location_name)} · ${timeAgo(r.reviewed_at)}</span>
    </div>
    <div class="review-body ${r.body ? "" : "empty"}">${r.body ? esc(r.body) : "Rating only, no text"}</div>
    ${r.latest_reply ? `<div class="latest-reply">${esc(r.latest_reply)}</div>` : ""}
    ${r.reply_status === "replied" ? "" : `<div class="reply-box"><textarea rows="1" placeholder="Write a reply…"></textarea><button class="btn blue" data-save>Save draft</button></div>`}
  </div>`;
}

function bindReplyBoxes(root) {
  root.querySelectorAll("[data-save]").forEach((btn) => btn.addEventListener("click", async () => {
    const card = btn.closest(".review");
    const body = card.querySelector("textarea").value.trim();
    if (!body) return toast("Write a reply first");
    btn.disabled = true;
    try {
      await api(`/reviews/${card.dataset.id}/replies`, {}, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ body }) });
      card.querySelector(".status").className = "status drafted";
      card.querySelector(".status").textContent = "drafted";
      card.querySelector(".reply-box").insertAdjacentHTML("beforebegin", `<div class="latest-reply">${esc(body)}</div>`);
      card.querySelector("textarea").value = "";
      toast("Draft saved");
    } catch (e) { toast(e.message); }
    btn.disabled = false;
  }));
}

function renderComingSoon(page, module) {
  page.innerHTML = `<div class="card empty-state">${icon(module)}<h3>${esc(moduleName(module))} is coming soon</h3>
    <p>This module is enabled for ${esc(state.config.brand.name)} but has no data source connected yet.</p></div>`;
}

// ---------- boot ----------
async function boot() {
  const tenants = await api("/tenants");
  const lists = await Promise.all(tenants.map((t) => api(`/tenants/${t.id}/brands`)));
  state.brands = lists.flat();
  if (!state.brands.length) {
    $("#page").innerHTML = `<div class="card empty-state"><h3>No brands yet</h3><p>Run <code>scripts/seed_demo.py</code> or create a brand via the API.</p></div>`;
    return;
  }
  $("#brandSelect").innerHTML = state.brands.map((b) => `<option value="${b.id}">${esc(b.name)}</option>`).join("");
  const saved = store.get("ss_brand");
  const initial = state.brands.find((b) => String(b.id) === saved)?.id || state.brands[0].id;
  $("#brandSelect").value = initial;
  await loadBrand(initial);
}

$("#brandSelect").addEventListener("change", (e) => loadBrand(Number(e.target.value)));
$("#locationSelect").addEventListener("change", (e) => { state.locationId = e.target.value; render(); });
$("#platformSelect").addEventListener("change", (e) => { state.platform = e.target.value; render(); });
$("#rangeSeg").addEventListener("click", (e) => {
  const b = e.target.closest("button"); if (!b) return;
  $("#rangeSeg .active").classList.remove("active"); b.classList.add("active");
  state.days = Number(b.dataset.days); render();
});
$("#menuToggle").addEventListener("click", () => {
  if (window.matchMedia("(max-width: 860px)").matches) document.body.classList.toggle("nav-open");
  else document.body.classList.toggle("collapsed");
});
$("#scrim").addEventListener("click", () => document.body.classList.remove("nav-open"));
$("#fullscreenBtn").addEventListener("click", () => {
  if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen?.();
});
window.addEventListener("hashchange", render);

boot().catch((e) => { $("#page").innerHTML = `<div class="card empty-state"><h3>API not reachable</h3><p>${esc(e.message)}</p></div>`; });
