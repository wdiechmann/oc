class JournalWorkEditor extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    const opts = { signal: this.abort.signal };
    if (this.dataset.pending === "true") this.refreshTimer = setTimeout(()=>{ if (this.isConnected && !this.dirty) window.Turbo.visit(window.location.href,{action:"replace"}); },1500);
    this.addEventListener("input", event => this.input(event), opts);
    this.addEventListener("change", event => this.input(event), opts);
    this.addEventListener("click", event => this.click(event), opts);
    this.addEventListener("focusout",event=>{ if (event.target.matches("[data-account-search]")) this.closeLookup(); },opts);
    this.addEventListener("keydown", event => this.key(event), opts);
    this.addEventListener("pointerdown", event => { if (event.target.closest("[role=option]")) event.preventDefault(); }, opts);
    this.addEventListener("submit", event => {
      const form = event.target;
      if (this.dirty && this.dirty !== form) { event.preventDefault(); return this.status("Save or cancel your current row first."); }
      for (const host of form.querySelectorAll("[data-account-lookup]")) {
        if (host.querySelector("[data-account-search]").value && !host.querySelector("[data-account-id]").value) { event.preventDefault(); return this.status("Choose an account from the lookup results."); }
      }
    },opts);
    document.addEventListener("submit",event=>{ if (this.isConnected && this.dirty && event.target.matches("[data-journal-details]")) { event.preventDefault(); this.status("Save or cancel your row before changing journal details."); } },opts);
    document.addEventListener("turbo:before-visit", event => { if (this.isConnected && this.dirty) { event.preventDefault(); this.status("Save or cancel your current row before leaving the journal."); } },opts);
    this.querySelectorAll("[data-account-lookup]").forEach(host => { if (host.querySelector("[data-account-id]").value) host.querySelector("[data-account-search]").dataset.chosenLabel = host.querySelector("[data-account-search]").value; });
    this.querySelectorAll("[data-work-row]").forEach(form=>{ form.originalInputs = [...form.querySelectorAll("input")].map(input=>({input,value:input.value,checked:input.checked,dataset:{...input.dataset}})); if (form.dataset.editing === "true") this.accountBasis(form); else this.paintBasis(form); });
    this.querySelectorAll("[data-work-vat]").forEach(out => { out.dataset.original = out.textContent; out.dataset.originalTitle=out.title; });
    if (!this.querySelector("[data-work-row][data-draft=true]")) this.querySelector("#work-row-new input[name=reference]")?.focus();
    this.querySelectorAll("[data-work-row][data-draft=true]").forEach(form=>{ this.dirty=form; this.preview(form); });
  }
  disconnectedCallback() { clearTimeout(this.refreshTimer); this.abort.abort(); this.lookupAbort?.abort(); this.previewAbort?.abort(); clearTimeout(this.timer); clearTimeout(this.vatTimer); }
  status(text) { this.querySelector("[data-work-status]").textContent = text; }
  input(event) {
    const form = event.target.closest("[data-work-row]");
    if (!form) return;
    this.dirty = form;
    if (event.target.matches("[data-account-search]") && event.target.value !== event.target.dataset.chosenLabel) {
      const host = event.target.closest("[data-account-lookup]");
      host.querySelector("[data-account-id]").value = ""; event.target.dataset.accountBasis=""; event.target.dataset.accountVat="";
      this.search(event.target);
    }
    if (event.target.matches("[data-work-included]")) {
      form.querySelector("[data-basis-override]").value="true";
      form.querySelector("[data-work-basis]").value=event.target.checked ? "gross" : "net";
      event.target.indeterminate=false;
    } else if (event.target.matches("[data-account-search]")) this.accountBasis(form);
    if (event.target.matches("[data-work-credit]")) {
      form.querySelector("[data-credit-override]").value="true";
      form.querySelector("[data-credit-default]").hidden=false;
    }
    this.paintBasis(form);
    if (event.target.matches("[data-account-search],[data-work-amount],[data-work-included],[data-work-credit]")) this.preview(form);
  }
  async search(input) {
    this.closeLookup();
    if (!input.value.startsWith("/")) return;
    this.lookupInput = input;
    this.index = -1;
    clearTimeout(this.timer);
    const raw = input.value;
    this.timer = setTimeout(async () => {
      this.lookupAbort = new AbortController();
      const url = new URL(this.dataset.lookupUrl,location.origin); url.searchParams.set("q",raw.slice(1));
      try {
        const response = await fetch(url,{signal: this.lookupAbort.signal,headers: {Accept: "application/json"}});
        if ([401,403,404].includes(response.status)) return this.clearProtected();
        if (!response.ok) throw new Error();
        const result = await response.json();
        if (this.lookupInput !== input || input.value !== raw || !input.isConnected) return;
        if (String(result.source_version) !== this.dataset.setupVersion) return this.status("The account list changed. Refresh the journal before choosing an account.");
        this.results = result.results;
        const host = input.closest("[data-account-lookup]").querySelector("[data-account-results]");
        host.id ||= `journal-lookup-${crypto.randomUUID()}`;
        input.setAttribute("aria-controls",host.id); input.setAttribute("aria-expanded","true");
        host.replaceChildren(); host.hidden = false;
        const rect = input.getBoundingClientRect(); host.style.position="fixed"; host.style.margin="0"; host.style.left=`${Math.min(rect.left,window.innerWidth-292)}px`; host.style.top=`${rect.bottom+4}px`; host.style.bottom="auto"; host.style.right="auto"; host.showPopover?.();
        this.results.forEach((row,i) => {
          const option = document.createElement("button"); option.type = "button"; option.setAttribute("role","option"); option.setAttribute("aria-selected","false"); option.id = `${host.id}-${i}`; option.dataset.resultIndex = i;
          option.className = "block w-full border-b border-stone-100 px-3 py-2 text-left text-sm hover:bg-teal-50"; option.textContent = `${row.number} · ${row.name}`; host.append(option);
        });
        if (!this.results.length) { const p = document.createElement("p"); p.className = "p-3 text-sm"; p.textContent = "No matching posting accounts."; host.append(p); }
      } catch (error) { if (error.name !== "AbortError") this.status("Account lookup is unavailable. Your row is unchanged."); }
    },150);
  }
  choose(index) {
    const row = this.results[index], input = this.lookupInput;
    if (!row || !input) return;
    input.value = `${row.number} · ${row.name}`; input.dataset.chosenLabel = input.value; input.dataset.accountBasis=row.vat_basis || ""; input.dataset.accountVat=row.vat_entry_id || "";
    input.closest("[data-account-lookup]").querySelector("[data-account-id]").value = row.id;
    const form = input.form; this.closeLookup(); this.dirty = form; this.accountBasis(form); this.preview(form);
  }
  closeLookup() {
    clearTimeout(this.timer); this.lookupAbort?.abort();
    if (this.lookupInput) { this.lookupInput.setAttribute("aria-expanded","false"); this.lookupInput.removeAttribute("aria-activedescendant"); const host=this.lookupInput.closest("[data-account-lookup]").querySelector("[data-account-results]"); host.hidePopover?.(); host.hidden = true; }
    this.lookupInput = null; this.results = []; this.index = -1;
  }
  click(event) {
    const option = event.target.closest("[data-result-index]"); if (option) { event.preventDefault(); return this.choose(Number(option.dataset.resultIndex)); }
    const form = event.target.closest("[data-work-row]"); if (!form) return;
    if (event.target.closest("[data-credit-default]")) {
      if (this.dirty && this.dirty !== form) return this.status("Save or cancel your current row first.");
      form.querySelector("[data-credit-override]").value="false"; form.querySelector("[data-credit-default]").hidden=true;
      this.dirty=form; return this.preview(form);
    }
    if (event.target.closest("[data-basis-default]")) { if (this.dirty && this.dirty !== form) return this.status("Save or cancel your current row first."); form.querySelector("[data-basis-override]").value="false"; this.accountBasis(form); this.dirty=form; return this.preview(form); }
    if (event.target.closest("[data-work-cancel]")) return this.cancel(form);
    if (event.target.closest("[data-work-edit]")) {
      if (this.dirty && this.dirty !== form) return this.status("Save or cancel your current row first.");
      this.querySelectorAll("[data-work-row]").forEach(row => this.editing(row,false)); this.editing(form,true); form.querySelector("input[name=reference]").focus();
    }
  }
  editing(form,on) {
    form.dataset.editing = String(on);
    form.querySelectorAll("input[type=text]").forEach(input => input.readOnly = !on);
    form.querySelector("[data-work-included]").disabled = !on;
    if (on) this.accountBasis(form); else this.paintBasis(form);
    form.querySelector("[data-credit-default]").hidden=!on || form.querySelector("[data-credit-override]").value !== "true";
    if (form.querySelector("[data-work-edit]")) form.querySelector("[data-work-edit]").hidden = on;
    if (form.querySelector("[data-work-save]")) form.querySelector("[data-work-save]").hidden = !on;
    if (form.querySelector("[data-work-cancel]")) form.querySelector("[data-work-cancel]").hidden = !on;
  }
  cancel(form) { form.reset(); form.originalInputs.forEach(({input,value,checked,dataset})=>{input.value=value; input.checked=checked; Object.assign(input.dataset,dataset);}); this.paintBasis(form); form.querySelectorAll("[data-account-search]").forEach(input => input.dataset.chosenLabel = input.value); this.closeLookup(); this.previewAbort?.abort(); clearTimeout(this.vatTimer); form.querySelector("[data-work-vat]").textContent = form.querySelector("[data-work-vat]").dataset.original; this.vatHint(form.querySelector("[data-work-vat]"), form.querySelector("[data-work-vat]").dataset.originalTitle); this.dirty = null; this.editing(form,false); this.status(""); }
  key(event) {
    if (event.defaultPrevented || event.isComposing || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    const row = event.target.closest("[data-work-row]");
    if (row && !event.target.closest("[role=menu],[role=listbox]") && ["Home","End","PageUp","PageDown"].includes(event.key)) {
      event.preventDefault(); event.stopPropagation();
      const rows=[...this.querySelectorAll("[data-work-row]")];
      const index=rows.indexOf(row);
      const next=event.key === "Home" ? 0 : event.key === "End" ? rows.length-1 : Math.max(0,Math.min(rows.length-1,index+(event.key === "PageDown" ? 1 : -1)));
      this.closeLookup();
      const target=rows[next];
      const name=event.target.getAttribute("name");
      const field=name && [...target.querySelectorAll("input:not([type=hidden])")].find(input=>input.name === name && !input.disabled);
      const control=event.target.matches("[data-menu-trigger]") ? target.querySelector("[data-menu-trigger]:not(:disabled)") : field;
      (control || target.querySelector("input[name=reference]")).focus({preventScroll:true});
      target.scrollIntoView({block:"nearest",inline:"nearest"});
      return;
    }
    if (this.lookupInput === event.target && ["Enter","Escape"].includes(event.key)) {
      event.preventDefault(); event.stopPropagation();
      if (event.key === "Escape") return this.closeLookup();
      return this.choose(Math.max(0,this.index));
    }
    if (event.key === "Escape" && event.target.form) { event.preventDefault(); this.cancel(event.target.form); }
  }
  preview(form) {
    const sequence = this.previewSequence = (this.previewSequence || 0) + 1;
    clearTimeout(this.vatTimer); this.previewAbort?.abort();
    const credit = form.querySelector("[data-work-credit]");
    if (form.querySelector("[data-credit-override]").value !== "true") credit.value="";
    const out = form.querySelector("[data-work-vat]"); out.textContent = "…"; this.vatHint(out,"VAT pending account and amount choices");
    if (!form.elements.amount.value) return;
    if ([...form.querySelectorAll("[data-account-search]")].some(input=>input.value && !input.closest("[data-account-lookup]").querySelector("[data-account-id]").value)) return;
    this.vatTimer = setTimeout(async () => {
      this.previewAbort = new AbortController(); out.textContent = "…"; this.vatHint(out,"Calculating VAT…");
      const body = new FormData(form); body.delete("_method");
      try {
        const response = await fetch(this.dataset.previewUrl,{method: "POST",body,signal: this.previewAbort.signal,headers: {Accept: "application/json","X-CSRF-Token":document.querySelector("meta[name=csrf-token]").content}});
        if ([401,403,404].includes(response.status)) return this.clearProtected();
        if (!response.ok) throw new Error();
        const data = await response.json();
        if (sequence !== this.previewSequence || !form.isConnected) return;
        if (form.querySelector("[data-credit-override]").value !== "true") credit.value=data.row?.credit_total_minor == null ? "" : this.money(data.row.credit_total_minor);
        const values = data.validation.lines.filter(l=>l.vat).map(l=>l.vat.error ? l.vat.error === "vat_basis_required" ? "Set account VAT inclusion or use the posting toggle" : l.vat.error.replaceAll("_"," ") : `${l.vat.code}: ${this.money(l.vat.amounts.vat)}`);
        const quotes=data.validation.lines.filter(l=>l.vat).map(l=>l.vat);
        out.textContent=quotes.some(q=>q.error) ? "—" : this.money(quotes.reduce((sum,q)=>sum+BigInt(q.amounts.vat),0n));
        this.vatHint(out,(values.length > 1 ? values.map((v,i)=>`${i===0 ? "Debit" : "Credit"} ${v}`) : values).join(" · ") || "No VAT configured");
      } catch (error) { if (error.name !== "AbortError") { out.textContent="—"; this.vatHint(out,"VAT unavailable — save will revalidate"); } }
    },200);
  }
  accountBasis(form) {
    if (form.querySelector("[data-basis-override]").value === "true") return this.paintBasis(form);
    const accounts=[...form.querySelectorAll("[data-account-lookup]")].filter(h=>h.querySelector("[data-account-id]").value).map(h=>h.querySelector("[data-account-search]"));
    const taxed=accounts.filter(a=>a.dataset.accountVat);
    const bases=taxed.map(a=>a.dataset.accountBasis || "");
    const basis=taxed.length ? (bases.every(b=>b && b===bases[0]) ? bases[0] : "") : (accounts.find(a=>a.dataset.accountBasis)?.dataset.accountBasis || "");
    form.querySelector("[data-work-basis]").value=basis;
    this.paintBasis(form);
  }
  paintBasis(form) {
    const basis=form.querySelector("[data-work-basis]").value, override=form.querySelector("[data-basis-override]").value === "true", toggle=form.querySelector("[data-work-included]");
    toggle.checked=basis === "gross"; toggle.indeterminate=!basis;
    toggle.title=`${override ? "Posting override" : "Account default"}: ${basis === "gross" ? "VAT included in debit amount" : basis === "net" ? "VAT added to debit amount" : "VAT inclusion unspecified"}. Toggle to override this posting; Use account default restores the account setting.`;
    form.querySelector("[data-basis-default]").hidden=form.dataset.editing !== "true" || !override;
  }
  vatHint(out,text) { out.title=text || ""; out.setAttribute("aria-label",text || ""); }
  money(value) { const n = BigInt(value), abs = n<0n ? -n : n; return `${n<0n ? "−" : ""}${abs/100n}${this.dataset.decimalSeparator}${String(abs%100n).padStart(2,"0")}`; }
  clearProtected() { const area = this.closest("#vera-book-content"), p = document.createElement("p"); p.textContent = "Journal access is no longer available. Sign in or refresh your access."; area.replaceChildren(p); }
}
customElements.define("journal-work-editor",JournalWorkEditor);
