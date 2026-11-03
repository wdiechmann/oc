class ChartOrderEditor extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    this.dirty = false;
    this.focused = this.rows()[0];
    this.addEventListener("focusin", event => {
      const row = event.target.closest("[data-order-row]");
      if (row) this.focused = row;
    }, { signal: this.abort.signal });
    this.addEventListener("click", event => this.click(event), { signal: this.abort.signal });
    this.addEventListener("keydown", event => this.key(event), { signal: this.abort.signal });
    this.addEventListener("change", () => this.selection(), { signal: this.abort.signal });
    this.querySelector("form").addEventListener("submit", event => this.preview(event), { signal: this.abort.signal });
    document.addEventListener("turbo:before-visit", event => {
      if (this.isConnected && this.dirty && !this.discarding) {
        event.preventDefault();
        this.status("Review or discard the draft order before leaving.");
      }
    }, { signal: this.abort.signal });
    window.addEventListener("beforeunload", event => {
      if (this.dirty && !this.submitting && !this.discarding) { event.preventDefault(); event.returnValue = ""; }
    }, { signal: this.abort.signal });
    this.selection();
  }
  async preview(event) {
    event.preventDefault();
    if (this.submitting) return;
    this.submitting = true;
    this.status("Preparing a version-checked review…");
    const form = event.target;
    try {
      const response = await fetch(form.action, { method: "POST", body: new FormData(form), credentials: "same-origin", cache: "no-store", signal: this.abort.signal });
      if (!this.isConnected) return;
      if (response.ok && new URL(response.url).searchParams.has("review_id")) {
        window.location.assign(response.url); return;
      }
      if ([401, 403, 404].includes(response.status)) {
        this.dirty = false;
        this.replaceChildren();
        window.location.assign(window.location.pathname); return;
      }
      const errorDocument = new DOMParser().parseFromString(await response.text(), "text/html");
      const message = errorDocument.querySelector("[role=alert]")?.textContent || "The review could not be prepared.";
      this.submitting = false;
      this.status(`${message} Your draft order is still here; discard it to start again from the current chart.`);
    } catch (error) {
      if (error.name !== "AbortError") {
        this.submitting = false;
        this.status("The review could not be confirmed. Your draft order is still here; try reviewing again when EP is available.");
      }
    }
  }
  disconnectedCallback() { this.abort.abort(); }
  rows() { return [...this.querySelectorAll("[data-order-row]")]; }
  status(message) { this.querySelector("#order-status").textContent = message; }
  selection() {
    const rows = this.rows();
    rows.forEach(row => { row.dataset.selected = String(row.querySelector("[data-order-select]").checked); });
    this.status(`${rows.filter(row => row.querySelector("[data-order-select]").checked).length} selected. ${this.dirty ? "Draft order changed; review before acceptance." : "Accepted order shown."}`);
  }
  focus(row) {
    if (!row) return;
    this.rows().forEach(item => { item.tabIndex = item === row ? 0 : -1; });
    this.focused = row;
    row.focus({ preventScroll: true });
    row.scrollIntoView({ block: "nearest" });
  }
  click(event) {
    if (event.target.closest("[data-order-discard]")) { this.discarding = true; return; }
    const action = event.target.closest("[data-order-move]");
    if (action) { this.move(action.dataset.orderMove); return; }
    if (event.target.closest("[data-order-clear]")) {
      this.rangeAnchor = null;
      this.rows().forEach(row => { row.querySelector("[data-order-select]").checked = false; });
      this.selection(); return;
    }
    const checkbox = event.target.closest("[data-order-select]");
    const row = event.target.closest("[data-order-row]");
    if (checkbox && row) {
      const rows = this.rows();
      if (event.shiftKey && this.rangeAnchor && rows.includes(this.rangeAnchor)) {
        const [start, end] = [rows.indexOf(this.rangeAnchor), rows.indexOf(row)].sort((a, b) => a - b);
        rows.slice(start, end + 1).forEach(item => { item.querySelector("[data-order-select]").checked = checkbox.checked; });
      }
      this.rangeAnchor = row;
      this.selection();
    } else if (row && !event.target.closest("input,button,select,a")) this.focus(row);
  }
  move(action) {
    const rows = this.rows();
    const checked = rows.filter(row => row.querySelector("[data-order-select]").checked);
    const selected = checked.length ? checked : [this.focused || rows[0]];
    const remaining = rows.filter(row => !selected.includes(row));
    let index;
    if (action === "first") index = 0;
    else if (action === "last") index = remaining.length;
    else if (action === "before") {
      const target = remaining.find(row => row.dataset.accountId === this.querySelector("[data-order-target]").value);
      if (!target) { this.status("Choose a destination outside the selected rows."); return; }
      index = remaining.indexOf(target);
    } else if (action === "up") index = Math.max(0, rows.slice(0, rows.indexOf(selected[0])).filter(row => !selected.includes(row)).length - 1);
    else index = Math.min(remaining.length, rows.slice(0, rows.indexOf(selected.at(-1)) + 1).filter(row => !selected.includes(row)).length + 1);
    const ordered = [...remaining.slice(0, index), ...selected, ...remaining.slice(index)];
    if (ordered.every((row, i) => row === rows[i])) { this.status("The selection is already at that position."); return; }
    this.querySelector("[data-order-list]").append(...ordered);
    this.dirty = true;
    ordered.forEach((row, i) => {
      row.querySelector("[data-order-rank]").textContent = String(i + 1);
      row.querySelector("[data-order-position]").textContent = `${row.dataset.originalPosition} → ${(i + 1) * 100}`;
    });
    this.focus(this.focused && selected.includes(this.focused) ? this.focused : selected[0]);
    this.selection();
  }
  key(event) {
    const row = event.target.closest("[data-order-row]");
    if (!row || event.target !== row || event.metaKey || event.ctrlKey) return;
    if (event.altKey && ["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) {
      event.preventDefault();
      this.move({ ArrowUp: "up", ArrowDown: "down", Home: "first", End: "last" }[event.key]); return;
    }
    if (event.altKey) return;
    const rows = this.rows();
    const index = rows.indexOf(row);
    if (event.key === " ") {
      event.preventDefault(); const checkbox = row.querySelector("[data-order-select]"); checkbox.checked = !checkbox.checked; this.selection(); return;
    }
    const next = { ArrowUp: index - 1, ArrowDown: index + 1, Home: 0, End: rows.length - 1, PageUp: index - 20, PageDown: index + 20 }[event.key];
    if (next !== undefined) { event.preventDefault(); this.focus(rows[Math.max(0, Math.min(rows.length - 1, next))]); }
  }
}
if (!customElements.get("chart-order-editor")) customElements.define("chart-order-editor", ChartOrderEditor);
