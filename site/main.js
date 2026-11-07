// config.js is written by the pipeline and sets window.API_BASE.
const api = window.API_BASE;

async function loadVisitors() {
  const el = document.getElementById("visitor-count");
  if (!api) { el.textContent = "n/a (no API configured)"; return; }
  try {
    const res = await fetch(`${api}/visitors`, { method: "POST" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    el.textContent = data.count.toLocaleString();
  } catch (err) {
    el.textContent = "unavailable";
    console.error("Visitor counter failed:", err);
  }
}

async function loadUptime() {
  const el = document.getElementById("uptime");
  if (!api) { el.textContent = "n/a"; return; }
  try {
    const res = await fetch(`${api}/status`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    el.textContent = data.checks ? `${data.uptime_percent}% (${data.checks} checks)` : "no checks yet";
  } catch (err) {
    el.textContent = "unavailable";
    console.error("Uptime status failed:", err);
  }
}

loadVisitors();
loadUptime();