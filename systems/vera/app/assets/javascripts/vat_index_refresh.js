class VatIndexRefresh extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    this.timer = setTimeout(() => this.refresh(), 1000);
  }
  disconnectedCallback() { clearTimeout(this.timer); this.abort.abort(); }
  async refresh() {
    try {
      const response = await fetch(this.dataset.url, {headers: {Accept: "text/vnd.turbo-stream.html"}, credentials: "same-origin", signal: this.abort.signal});
      const body = await response.text();
      if (!this.isConnected) return;
      if (response.headers.get("content-type")?.includes("text/vnd.turbo-stream.html")) {
        window.Turbo.renderStreamMessage(body);
      }
    } catch (error) {
      if (error.name === "AbortError") return;
    }
    if (this.isConnected) this.timer = setTimeout(() => this.refresh(), 3000);
  }
}
customElements.define("vat-index-refresh", VatIndexRefresh);
