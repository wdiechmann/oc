class CoaEditor extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    this.loading = false;
    this.stopped = false;
    document.addEventListener("turbo:before-visit", event => {
      if (this.isConnected && this.openForm()?.dataset.dirty === "true") {
        event.preventDefault();
        this.status("Save or cancel your current line before leaving the chart.");
      }
    }, { signal: this.abort.signal });
    this.addEventListener("keydown", event => this.navigate(event), { signal: this.abort.signal });
    this.addEventListener("click", event => this.click(event), { signal: this.abort.signal });
    this.addEventListener("change", event => this.changed(event), { signal: this.abort.signal });
    this.addEventListener("input", event => this.changed(event), { signal: this.abort.signal });
    this.querySelectorAll("[data-coa-form]").forEach(form => {
      this.fields(form);
      if (form.closest("[data-draft='true']")) form.dataset.dirty = "true";
    });
    this.roving();
    const location = new URL(window.location.href);
    if (location.pathname === new URL(this.dataset.chartUrl, window.location.origin).pathname) {
      location.searchParams.set("page", this.dataset.page);
      if (this.dataset.focusId) location.searchParams.set("focus_id", this.dataset.focusId);
      history.replaceState(history.state, "", location);
    }
    const rows = this.rows();
    const requested = this.dataset.focusId && rows.find(row => row.dataset.accountId === this.dataset.focusId);
    const edge = this.dataset.focusEdge;
    const selected = requested || (edge === "last" ? rows.at(-1) : edge === "first" ? rows[0] : null);
    if (selected) this.focus(selected);
    const draft = this.querySelector("[data-draft='true'] [data-coa-form]");
    if (draft) draft.querySelector("input[name=name]")?.focus();
    this.watch();
    if (this.dataset.pending === "true") {
      this.refreshTimer = setTimeout(() => {
        if (this.isConnected && !this.openForm()) window.Turbo.visit(window.location.href, { action: "replace" });
      }, 1500);
    }
  }
  disconnectedCallback() {
    this.abort.abort();
    this.observer?.disconnect();
    clearTimeout(this.refreshTimer);
  }
  rows() { return [...this.querySelectorAll("[data-coa-row]:not([data-new-row='true'])")]; }
  openForm() { return [...this.querySelectorAll("[data-coa-form]")].find(form => !form.hidden); }
  status(text) { const status = this.querySelector("#coa-status"); if (status) status.textContent = text; }
  roving(selected) {
    const rows = this.rows();
    selected ||= rows.find(row => row.tabIndex === 0) || rows[0];
    rows.forEach(row => {
      row.tabIndex = row === selected ? 0 : -1;
      row.querySelectorAll("[data-coa-display] button").forEach(button => { button.tabIndex = row === selected ? 0 : -1; });
    });
  }
  focus(row) {
    if (!row) return;
    this.roving(row);
    row.focus({ preventScroll: true });
    row.scrollIntoView({ block: "nearest", inline: "nearest" });
  }
  fields(form) {
    const kind = form.querySelector("[data-coa-kind]").value;
    form.querySelectorAll("[data-coa-kinds]").forEach(cell => {
      const visible = cell.dataset.coaKinds.split(" ").includes(kind);
      cell.classList.toggle("coa-irrelevant", !visible);
      cell.querySelectorAll("input,select,textarea").forEach(input => {
        input.disabled = !visible;
        input.required = visible && ["number", "formula"].includes(input.name);
      });
    });
  }
  changed(event) {
    const form = event.target.closest("[data-coa-form]");
    if (!form) return;
    form.dataset.dirty = "true";
    if (event.target.matches("[data-coa-kind]")) this.fields(form);
  }
  edit(row) {
    const form = row.querySelector("[data-coa-form]");
    if (!form) return;
    const open = this.openForm();
    if (open && open !== form) {
      if (open.dataset.dirty === "true") {
        this.status("Save or cancel your current line before editing another.");
        return;
      }
      this.cancel(open);
    }
    row.querySelector("[data-coa-display]")?.setAttribute("hidden", "");
    form.hidden = false;
    this.fields(form);
    form.querySelector("[data-coa-kind]").focus();
    this.status("");
  }
  cancel(form) {
    form.reset();
    form.dataset.dirty = "false";
    form.hidden = true;
    const row = form.closest("[data-coa-row]");
    row.querySelector("[data-coa-display]")?.removeAttribute("hidden");
    row.querySelector(".coa-conflict")?.setAttribute("hidden", "");
    this.fields(form);
    if (row.dataset.newRow === "true") row.querySelector("[data-coa-edit]")?.focus();
    else this.focus(row);
    this.status("");
    this.watch();
  }
  click(event) {
    const reference = event.target.closest("[data-coa-reference]");
    if (reference) {
      navigator.clipboard.writeText(`[@${reference.dataset.coaReference}]`).then(() => this.status("Stable account reference copied."), () => this.status(`Formula reference: [@${reference.dataset.coaReference}]`));
      return;
    }
    const edit = event.target.closest("[data-coa-edit]");
    if (edit) { this.edit(edit.closest("[data-coa-row]")); return; }
    const cancel = event.target.closest("[data-coa-cancel]");
    if (cancel) { this.cancel(cancel.closest("form")); return; }
    const next = event.target.closest("[data-coa-next]");
    if (next && !this.stopped) { event.preventDefault(); this.loadNext(); return; }
    const row = event.target.closest("[data-coa-row]");
    if (row && !event.target.closest("input,select,textarea,button,a,form")) this.focus(row);
  }
  async navigate(event) {
    if (event.altKey || event.metaKey || event.ctrlKey) return;
    const form = event.target.closest("[data-coa-form]");
    if (form) {
      if (event.key === "Escape") { event.preventDefault(); this.cancel(form); }
      else if (event.key === "Enter" && !event.shiftKey && !event.target.matches("select,button,input[type=submit]")) {
        event.preventDefault(); form.requestSubmit();
      }
      return;
    }
    const row = event.target.closest("[data-coa-row]");
    if (!row || event.target !== row) return;
    const keys = ["Enter", "ArrowDown", "ArrowUp", "Home", "End", "PageDown", "PageUp"];
    if (!keys.includes(event.key)) return;
    event.preventDefault();
    if (event.key === "Enter") { this.edit(row); return; }
    const open = this.openForm();
    if (open?.dataset.dirty === "true") { this.status("Save or cancel your current line before navigating the chart."); return; }
    if (open) this.cancel(open);
    const rows = this.rows();
    const index = rows.indexOf(row);
    const page = Number(row.dataset.page);
    if (event.key === "Home") {
      if (Number(rows[0]?.dataset.page) === 1) this.focus(rows[0]);
      else this.jumpPage(1, "first");
    } else if (event.key === "End") {
      if (Number(rows.at(-1)?.dataset.page) === Number(this.dataset.pages)) this.focus(rows.at(-1));
      else this.jumpPage(Number(this.dataset.pages), "last");
    } else if (event.key === "PageDown" || event.key === "PageUp") {
      const targetPage = page + (event.key === "PageDown" ? 1 : -1);
      const loaded = rows.find(candidate => Number(candidate.dataset.page) === targetPage);
      if (loaded) this.focus(loaded);
      else if (targetPage >= 1 && targetPage <= Number(this.dataset.pages)) this.jumpPage(targetPage, "first");
    } else if (event.key === "ArrowUp") {
      if (index > 0) this.focus(rows[index - 1]);
      else if (page > 1) this.jumpPage(page - 1, "last");
    } else if (event.key === "ArrowDown") {
      if (index < rows.length - 1) this.focus(rows[index + 1]);
      else {
        await this.loadNext();
        if (this.isConnected) this.focus(this.rows()[index + 1] || row);
      }
    }
  }
  jumpPage(page, edge) {
    const url = new URL(this.dataset.chartUrl, window.location.origin);
    url.searchParams.set("page", page);
    url.searchParams.set("focus_edge", edge);
    window.Turbo.visit(url.href);
  }
  watch() {
    this.observer?.disconnect();
    if (this.stopped || this.dataset.pending === "true") return;
    const next = this.querySelector("[data-coa-next]");
    if (!next) return;
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting) && !this.openForm()) this.loadNext();
    }, { rootMargin: "250px" });
    this.observer.observe(next);
  }
  async loadNext() {
    const next = this.querySelector("[data-coa-next]");
    if (!next || this.loading || this.stopped || this.openForm()) return;
    this.loading = true;
    this.observer?.disconnect();
    this.status("Loading more rows…");
    const url = new URL(next.href);
    url.searchParams.set("append", "1");
    url.searchParams.set("source_version", this.dataset.sourceVersion);
    try {
      const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin", cache: "no-store", signal: this.abort.signal });
      const body = await response.text();
      if (!this.isConnected) return;
      if (response.headers.get("content-type")?.includes("text/vnd.turbo-stream.html")) window.Turbo.renderStreamMessage(body);
      if (!response.ok) {
        this.stopped = true;
        this.status(response.status === 409 ? "The chart changed. Refresh the chart to load a consistent list." : "More rows could not be loaded. Use the page links to try again.");
      } else {
        await new Promise(resolve => requestAnimationFrame(resolve));
        this.roving();
        this.querySelectorAll("[data-coa-form]").forEach(form => this.fields(form));
        this.status("");
      }
    } catch (error) {
      if (error.name !== "AbortError") { this.stopped = true; this.status("More rows could not be loaded. Use the page links to try again."); }
    } finally {
      this.loading = false;
      if (this.isConnected) this.watch();
    }
  }
}
if (!customElements.get("coa-editor")) customElements.define("coa-editor", CoaEditor);
