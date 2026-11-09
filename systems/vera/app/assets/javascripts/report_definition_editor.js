class ReportDefinitionEditor extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    this.addEventListener("click", event => {
      const button = event.target.closest("[data-edit-report-line]");
      const deletion = event.target.closest("[data-delete-report-line]");
      if (button) this.open(button);
      else if (deletion) this.open(deletion, "delete");
    }, { signal: this.abort.signal });
    this.addEventListener("keydown", event => {
      const button = event.target.closest("[data-edit-report-line]");
      if (!button?.matches("button[id^=report-line-]") || !["Home", "End", "PageUp", "PageDown", "ArrowUp", "ArrowDown"].includes(event.key)) return;
      const buttons = [...this.querySelectorAll("button[id^=report-line-]")].filter(button => !button.closest("[data-report-line]").hidden);
      const current = buttons.indexOf(button);
      const index = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1 : current + (["PageUp", "ArrowUp"].includes(event.key) ? -1 : 1);
      event.preventDefault();
      buttons[Math.max(0, Math.min(buttons.length - 1, index))]?.focus();
    }, { signal: this.abort.signal });
  }
  disconnectedCallback() { this.abort.abort(); }
  async open(button, action = "edit") {
    if (this.loading) return;
    this.loading = true;
    const error = this.querySelector("[data-report-editor-error]");
    error.textContent = "";
    const body = new FormData(this.querySelector("form"));
    body.set("line_index", button.dataset.editReportLine ?? button.dataset.deleteReportLine);
    body.set("dialog_action", action);
    try {
      const response = await fetch(this.dataset.dialogUrl, {
        method: "POST", body, credentials: "same-origin", signal: this.abort.signal,
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      });
      if (!response.ok) throw new Error("unavailable");
      window.Turbo.renderStreamMessage(await response.text());
    } catch (failure) {
      if (failure.name !== "AbortError") error.textContent = "Could not open the report line. Your draft is unchanged; refresh access or try again.";
    } finally { this.loading = false; }
  }
  removeLine(index) {
    const row = this.querySelector(`[data-report-line="${index}"]`);
    if (!row) return;
    row.querySelector(`input[name="lines[${index}][remove]"]`).value = "1";
    row.hidden = true;
    return [...this.querySelectorAll("button[id^=report-line-]")].find(button => !button.closest("[data-report-line]").hidden) || this.querySelector('button[name="intent"]');
  }
  apply(index, values, labels) {
    const row = this.querySelector(`[data-report-line="${index}"]`);
    if (!row) return;
    const inputs = row.querySelector("[data-line-inputs]");
    inputs.replaceChildren();
    const add = (key, value, label) => {
      const input = document.createElement("input");
      input.type = "hidden"; input.name = key.endsWith("[]") ? `lines[${index}][${key.slice(0, -2)}][]` : `lines[${index}][${key}]`; input.value = value || "";
      if (label) input.dataset.accountLabel = label;
      inputs.append(input);
    };
    for (const key of ["id", "code", "name", "kind", "position", "sign", "formula", "remove"]) add(key, values.get(key));
    for (const [position, id] of values.getAll("account_ids[]").filter(Boolean).entries()) add("account_ids[]", id, labels[position]);
    for (const key of ["kind", "code", "name", "position"]) row.querySelector(`[data-line-summary="${key}"]`).textContent = values.get(key) || (key === "name" ? "New line" : "");
    row.querySelector('[data-line-summary="sign"]').textContent = values.get("kind") === "mapping" ? (values.get("sign") === "-1" ? "−" : "+") : "";
    row.querySelector('[data-line-summary="detail"]').textContent = values.get("kind") === "total" ? values.get("formula") : labels.join("; ");
    row.classList.toggle("opacity-50", values.get("remove") === "1");
    row.classList.toggle("line-through", values.get("remove") === "1");
  }
}
class ReportLineDialog extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    const form = this.querySelector("form");
    const kind = form.elements.namedItem("kind");
    const sync = () => {
      this.querySelectorAll("[data-report-kind]").forEach(group => {
        group.hidden = group.dataset.reportKind !== kind.value;
        group.querySelectorAll("input,select,textarea").forEach(input => { input.disabled = group.hidden; });
      });
    };
    kind.addEventListener("change", sync, { signal: this.abort.signal });
    form.addEventListener("submit", event => {
      event.preventDefault();
      const values = new FormData(form);
      if (kind.value !== "mapping") values.set("sign", "1");
      const select = form.querySelector('select[name="account_ids[]"]');
      const labels = kind.value === "mapping" ? [...select.selectedOptions].map(option => option.textContent) : [];
      document.querySelector("report-definition-editor")?.apply(this.dataset.index, values, labels);
      this.closest("shared-dialog").close();
    }, { signal: this.abort.signal });
    sync();
    requestAnimationFrame(() => form.elements.namedItem("code").focus());
  }
  disconnectedCallback() { this.abort.abort(); }
}
customElements.define("report-definition-editor", ReportDefinitionEditor);
customElements.define("report-line-dialog", ReportLineDialog);

class ReportLineDeleteDialog extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    this.querySelector("form").addEventListener("submit", event => {
      event.preventDefault();
      const target = document.querySelector("report-definition-editor")?.removeLine(this.dataset.index);
      this.closest("shared-dialog").close();
      target?.focus();
    }, { signal: this.abort.signal });
  }
  disconnectedCallback() { this.abort.abort(); }
}
customElements.define("report-line-delete-dialog", ReportLineDeleteDialog);
