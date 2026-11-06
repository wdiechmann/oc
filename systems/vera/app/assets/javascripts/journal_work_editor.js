class JournalWorkEditor extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    const opts = { signal: this.abort.signal };
    if (this.dataset.pending === "true") this.refreshTimer = setTimeout(()=>{ if (this.isConnected && !this.dirty) window.Turbo.visit(window.location.href,{action:"replace"}); },1500);
    document.addEventListener("turbo:before-stream-render",event=>this.preserveAttachmentDraft(event),opts);
    this.addEventListener("journal-vat:updated", event => this.applyVatUpdate(event), opts);
    this.addEventListener("input", event => this.input(event), opts);
    this.addEventListener("change", event => this.input(event), opts);
    this.addEventListener("click", event => this.click(event), opts);
    this.addEventListener("focusout",event=>{
      if (event.target.matches("[data-work-amount],[data-work-credit]")) {
        const value=event.target.value.trim().replace(/^[−-]\s*/, "");
        if (value!==event.target.value) {event.target.value=value;this.preview(event.target.closest("[data-work-row]"));}
        return;
      }
      if (!event.target.matches("[data-account-search]")) return;
      this.closeLookup();
      if (event.target.skipAccountResolve) {event.target.skipAccountResolve=false;return;}
      this.resolveAccount(event.target);
    },opts);
    this.addEventListener("context-menu:escape",event=>event.target.closest("[data-work-row]")?.querySelector("input[name=reference]")?.focus(),opts);
    this.addEventListener("keydown", event => this.key(event), opts);
    this.addEventListener("pointerdown", event => { if (event.target.closest("[role=option]")) event.preventDefault(); }, opts);
    this.addEventListener("submit", event => {
      const form = event.target;
      if (form.accountSubmissionPending) {event.preventDefault();return;}
      const unresolved=[...form.querySelectorAll("[data-account-search]")].filter(input=>input.value.trim() && !input.closest("[data-account-lookup]").querySelector("[data-account-id]").value);
      if (unresolved.length && !form.accountResolutionChecked) {
        event.preventDefault();form.accountSubmissionPending=true;const submitter=event.submitter;
        const version=form.accountSubmissionVersion=(form.accountSubmissionVersion || 0)+1;
        Promise.all(unresolved.map(input=>this.resolveAccount(input))).then(()=>{
          if (form.accountSubmissionVersion !== version) return;
          form.accountSubmissionPending=false;
          if (!form.isConnected) return;
          form.accountResolutionChecked=true;
          try {form.requestSubmit(submitter);} finally {form.accountResolutionChecked=false;}
        });
        return;
      }
      if (this.dirty && this.dirty !== form) { event.preventDefault(); return this.status("Save or cancel your current row first."); }
      for (const host of form.querySelectorAll("[data-account-lookup]")) {
        if (host.querySelector("[data-account-search]").value && !host.querySelector("[data-account-id]").value) { event.preventDefault(); return this.status("Choose an account from the lookup results."); }
      }
    },opts);
    document.addEventListener("submit",event=>{ if (this.isConnected && this.dirty && event.target.matches("[data-journal-details],#work-row-new")) { event.preventDefault(); this.status("Save or cancel your row before changing journal details or creating another line."); } },opts);
    document.addEventListener("turbo:before-visit", event => { if (this.isConnected && this.dirty) { event.preventDefault(); this.status("Save or cancel your current row before leaving the journal."); } },opts);
    this.querySelectorAll("[data-account-lookup]").forEach(host => { if (host.querySelector("[data-account-id]").value) host.querySelector("[data-account-search]").dataset.chosenLabel = host.querySelector("[data-account-search]").value; });
    this.querySelectorAll("[data-work-row]").forEach(form=>{ form.originalInputs = [...form.querySelectorAll("input")].map(input=>({input,value:input.value,checked:input.checked,dataset:{...input.dataset}})); if (form.dataset.editing === "true") this.accountBasis(form); else this.paintBasis(form); });
    this.querySelectorAll("[data-work-vat]").forEach(out => { out.dataset.original = out.textContent; out.dataset.originalTitle=out.title; });
    if (!document.querySelector("dialog[open]") && !this.querySelector("[data-work-row][data-draft=true]")) this.querySelector("[data-work-row] input[name=reference]")?.focus();
    this.querySelectorAll("[data-work-row][data-draft=true]").forEach(form=>{ this.dirty=form; this.preview(form); });
  }
  disconnectedCallback() { this.querySelectorAll("[data-account-search]").forEach(input=>input.accountResolution?.abort.abort()); clearTimeout(this.refreshTimer); this.abort.abort(); this.vatOperationAbort?.abort(); this.lookupAbort?.abort(); this.previewAbort?.abort(); clearTimeout(this.timer); clearTimeout(this.vatTimer); }
  status(text) { this.querySelector("[data-work-status]").textContent = text; }
  input(event) {
    const form = event.target.closest("[data-work-row]");
    if (!form) return;
    this.dirty = form;
    if (event.target.matches("[data-account-search]")) event.target.accountResolution?.abort.abort();
    if (event.target.matches("[data-account-search]") && event.target.value !== event.target.dataset.chosenLabel) {
      const host = event.target.closest("[data-account-lookup]");
      host.querySelector("[data-account-id]").value = ""; event.target.dataset.accountBasis=""; event.target.dataset.accountVat="";
      this.search(event.target);
    }
    if (event.target.matches("[data-work-included]")) {
      form.querySelector("[data-basis-override]").value="true";
      form.querySelector("[data-work-vat-enabled]").value=String(event.target.checked);
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
    if ([...input.value.trim()].length < 2) return;
    this.lookupInput = input;
    this.index = -1;
    clearTimeout(this.timer);
    const raw = input.value;
    this.timer = setTimeout(async () => {
      this.lookupAbort = new AbortController();
      const url = new URL(this.dataset.lookupUrl,location.origin); url.searchParams.set("q",raw.trim());
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
          const option = document.createElement("button"); option.type = "button"; option.tabIndex=-1; option.setAttribute("role","option"); option.setAttribute("aria-selected","false"); option.id = `${host.id}-${i}`; option.dataset.resultIndex = i;
          option.className = "block w-full border-b border-stone-100 px-3 py-2 text-left text-sm hover:bg-teal-50"; option.textContent = `${row.number} · ${row.name}`; host.append(option);
        });
        if (this.pendingLookupDirection) {this.navigateLookup(this.pendingLookupDirection);this.pendingLookupDirection=null;}
        if (!this.results.length) { const p = document.createElement("p"); p.className = "p-3 text-sm"; p.textContent = "No matching posting accounts."; host.append(p); }
      } catch (error) { if (error.name !== "AbortError") this.status("Account lookup is unavailable. Your row is unchanged."); }
    },150);
  }
  navigateLookup(direction) {
    if (!this.results.length) {this.pendingLookupDirection=direction;return;}
    const count=this.results.length;
    this.index=direction === "ArrowDown" ? (this.index===count-1 ? -1 : this.index+1) : (this.index===-1 ? count-1 : this.index-1);
    const options=this.lookupInput.closest("[data-account-lookup]").querySelectorAll("[role=option]");
    options.forEach((option,index)=>{option.setAttribute("aria-selected",String(index===this.index));option.classList.toggle("bg-teal-100",index===this.index);});
    if (this.index<0) this.lookupInput.removeAttribute("aria-activedescendant");
    else {this.lookupInput.setAttribute("aria-activedescendant",options[this.index].id);options[this.index].scrollIntoView({block:"nearest"});}
  }
  choose(index) {
    const row = this.results[index], input = this.lookupInput;
    if (!row || !input) return;
    this.applyAccount(input,row); this.closeLookup();
  }
  applyAccount(input,row) {
    input.value = `${row.number} · ${row.name}`; input.dataset.chosenLabel = input.value; input.dataset.accountBasis=row.vat_basis || ""; input.dataset.accountVat=row.vat_entry_id || "";
    input.closest("[data-account-lookup]").querySelector("[data-account-id]").value = row.id;
    const form=input.form;this.dirty=form;this.accountBasis(form);this.preview(form);
  }
  resolveAccount(input) {
    const raw=input.value, query=raw.trim();
    if (!input.isConnected || input.readOnly || !query || input.closest("[data-account-lookup]").querySelector("[data-account-id]").value) return Promise.resolve();
    if (input.accountResolution?.raw === raw && !input.accountResolution.abort.signal.aborted) return input.accountResolution.promise;
    input.accountResolution?.abort.abort();
    const abort=new AbortController();
    const promise=(async()=>{
      try {
        const url=new URL(this.dataset.lookupUrl,location.origin);url.searchParams.set("q",query);
        const response=await fetch(url,{signal:abort.signal,headers:{Accept:"application/json"}});
        if ([401,403,404].includes(response.status)) return this.clearProtected();
        if (!response.ok) throw new Error();
        const data=await response.json();
        if (abort.signal.aborted || !input.isConnected || input.value !== raw) return;
        if (String(data.source_version) !== this.dataset.setupVersion) return this.status("The account list changed. Refresh before choosing an account.");
        const exact=data.results.filter(account=>String(account.number).toLowerCase() === query.toLowerCase());
        if (exact.length === 1) this.applyAccount(input,exact[0]);
        else this.status("Choose an account from the lookup results; the typed account number was not an exact match.");
      } catch(error) {if (error.name !== "AbortError") this.status("Account lookup is unavailable. Your row is unchanged.");}
      finally {if (input.accountResolution?.abort === abort) input.accountResolution=null;}
    })();
    input.accountResolution={raw,abort,promise};return promise;
  }

  closeLookup() {
    clearTimeout(this.timer); this.lookupAbort?.abort();
    if (this.lookupInput) { this.lookupInput.setAttribute("aria-expanded","false"); this.lookupInput.removeAttribute("aria-activedescendant"); const host=this.lookupInput.closest("[data-account-lookup]").querySelector("[data-account-results]"); host.hidePopover?.(); host.hidden = true; }
    this.lookupInput = null; this.results = []; this.index = -1; this.pendingLookupDirection=null;
  }
  click(event) {
    if (event.target.closest("[data-work-attachment]")) {
      this.closeLookup();
    }
    const option = event.target.closest("[data-result-index]"); if (option) { event.preventDefault(); return this.choose(Number(option.dataset.resultIndex)); }
    const form = event.target.closest("[data-work-row]"); if (!form) return;
    if (event.target.closest("[data-work-vat-operation]")) {event.preventDefault();if(this.dirty && this.dirty!==form)return this.status("Save or cancel your current row first.");return this.vatOperation(form);}
    if (event.target.closest("[data-credit-default]")) {
      if (this.dirty && this.dirty !== form) return this.status("Save or cancel your current row first.");
      form.querySelector("[data-credit-override]").value="false"; form.querySelector("[data-credit-default]").hidden=true;
      this.dirty=form; return this.preview(form);
    }
    if (event.target.closest("[data-basis-default]")) { if (this.dirty && this.dirty !== form) return this.status("Save or cancel your current row first."); form.querySelector("[data-basis-override]").value="false"; this.accountBasis(form); this.dirty=form; return this.preview(form); }
    if (event.target.closest("[data-work-save]")) form.querySelector("[data-row-intent]").value="";
    if (event.target.closest("[data-work-cancel]")) return this.cancel(form);
    if (event.target.closest("[data-work-edit]")) {
      if (this.dirty && this.dirty !== form) return this.status("Save or cancel your current row first.");
      this.querySelectorAll("[data-work-row]").forEach(row => this.editing(row,false)); this.editing(form,true); form.querySelector("input[name=reference]").focus(); this.preview(form);
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
  preserveAttachmentDraft(event) {
    if (!this.isConnected || !this.dirty || !event.target.hasAttribute("data-preserve-journal-draft") || event.target.getAttribute("target") !== "vera-book-content") return;
    const render=event.detail.render;
    event.detail.render=async stream=>{
      if (!this.isConnected || !this.dirty) return render(stream);
      const incoming=stream.templateContent.querySelector("journal-work-editor");
      if (!incoming || incoming.dataset.pending === "true" || ![...incoming.querySelectorAll("[data-work-row]")].some(row=>row.id===this.dirty.id)) {
        this.status("Attachment accepted. Your edits are retained; saving will check the latest journal version.");return;
      }
      const names=new Set(["reference","amount","credit_amount","debit_account_id","credit_account_id","debit_label","credit_label","amount_basis","basis_override","credit_override","vat_enabled","vat_entry_id","vat_source_side","void"]);
      const fields=[...this.dirty.querySelectorAll("input")].filter(input=>names.has(input.name)).map(input=>({name:input.name,value:input.value,checked:input.checked,dataset:{...input.dataset}}));
      const originals=this.dirty.originalInputs.filter(({input})=>names.has(input.name) && !input.matches("[data-account-search]")).map(({input,value})=>({name:input.name,value}));
      const fences=[...this.dirty.querySelectorAll("input")].filter(input=>["expected_version","expected_draft_version"].includes(input.name) || input.name.startsWith("contexts[")).map(input=>({name:input.name,value:input.value}));
      const id=this.dirty.id;
      await render(stream);
      const form=document.getElementById(id),editor=form?.closest("journal-work-editor");
      if (!editor) return;
      const inputs=[...form.querySelectorAll("input")],find=name=>inputs.find(input=>input.name===name);
      const changed=originals.some(field=>find(field.name)?.value !== field.value) || fences.filter(field=>field.name.startsWith("contexts[")).some(field=>find(field.name)?.value !== field.value);
      fields.forEach(field=>{const input=find(field.name);if(input){input.value=field.value;input.checked=field.checked;Object.assign(input.dataset,field.dataset);}});
      if(changed) fences.forEach(field=>{const input=find(field.name);if(input)input.value=field.value;});
      editor.querySelectorAll("[data-work-row]").forEach(row=>editor.editing(row,false));
      editor.editing(form,true);editor.dirty=form;
      if(changed) editor.status("The saved row or accounting context changed while attaching. Your edits are retained; compare with the saved row before saving.");
      else editor.preview(form);
    };
  }
  cancel(form) { form.accountSubmissionVersion=(form.accountSubmissionVersion || 0)+1; form.accountSubmissionPending=false; form.querySelectorAll("[data-account-search]").forEach(input=>input.accountResolution?.abort.abort()); form.reset(); form.originalInputs.forEach(({input,value,checked,dataset})=>{input.value=value; input.checked=checked; Object.assign(input.dataset,dataset);}); this.paintBasis(form); form.querySelectorAll("[data-account-search]").forEach(input => input.dataset.chosenLabel = input.value); this.closeLookup(); this.previewAbort?.abort(); clearTimeout(this.vatTimer); form.querySelector("[data-work-vat]").textContent = form.querySelector("[data-work-vat]").dataset.original; this.vatHint(form.querySelector("[data-work-vat]"), form.querySelector("[data-work-vat]").dataset.originalTitle); this.dirty = null; this.editing(form,false); this.status(""); }
  key(event) {
    if (event.defaultPrevented || event.isComposing || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    const row = event.target.closest("[data-work-row]");
    if (event.key === " " && event.target.matches("[data-work-attachment]")) {
      event.preventDefault();event.stopPropagation();if (!event.repeat)event.target.click();return;
    }
    if (event.key === "Escape" && row) {
      event.preventDefault();event.stopPropagation();
      if (event.target.matches("[data-account-search]")) {event.target.accountResolution?.abort.abort();event.target.skipAccountResolve=true;}
      this.closeLookup();row.querySelector("input[name=reference]").focus();return;
    }
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
    if (event.target.matches("[data-account-search]") && ["ArrowDown","ArrowUp"].includes(event.key) && !event.target.readOnly && [...event.target.value.trim()].length >= 2) {
      event.preventDefault();event.stopPropagation();
      if (this.lookupInput !== event.target) this.search(event.target);
      this.navigateLookup(event.key);
      return;
    }
    if (this.lookupInput === event.target && event.key === "Enter") {
      event.preventDefault(); event.stopPropagation();
      return this.choose(Math.max(0,this.index));
    }
    if (event.key === "Enter" && row && event.target.matches("input[type=text],[data-work-included]")) {
      event.preventDefault();
      if (this.dirty && this.dirty !== row) return this.status("Save or cancel your current row first.");
      if (row.dataset.editing !== "true") return;
      row.querySelector("[data-row-intent]").value=this.querySelectorAll("[data-work-row]").length < 100 ? "next_row" : "";
      row.requestSubmit(row.querySelector("[data-work-save]"));
      return;
    }

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
        const values = data.validation.lines.filter(l=>l.vat).map(l=>l.vat.error ? l.vat.error === "vat_basis_required" ? "Set account VAT inclusion or use the posting toggle" : l.vat.error.replaceAll("_"," ") : `${l.vat.code}: ${this.money(l.vat.amounts.vat)} total VAT; ${this.money(l.vat.amounts.deductible_vat)} deductible; ${this.money(l.vat.amounts.non_deductible_vat)} non-deductible${l.vat.posting_direction ? " · "+(l.vat.posting_direction === "output" ? "Outgoing VAT" : "Incoming VAT") : ""}`);
        const quotes=data.validation.lines.filter(l=>l.vat).map(l=>l.vat);
        out.textContent=quotes.some(q=>q.error) ? "—" : this.money(quotes.reduce((sum,q)=>sum+BigInt(q.posting_vat_minor ?? q.amounts.vat),0n));
        this.vatHint(out,(values.length > 1 ? values.map((v,i)=>`${i===0 ? "Debit" : "Credit"} ${v}`) : values).join(" · ") || "No VAT configured");
      } catch (error) { if (error.name !== "AbortError") { out.textContent="—"; this.vatHint(out,"VAT unavailable — save will revalidate"); } }
    },200);
  }
  applyVatUpdate(event) {
    const form=document.getElementById(`work-row-${event.detail.rowId}`);
    if (!form || !this.contains(form) || (this.dirty && this.dirty!==form)) return;
    const patch=event.detail.patch;
    form.querySelector("[data-work-vat-entry]").value=patch.entry || "";
    form.querySelector("[data-work-vat-source]").value=patch.source || "";
    form.querySelector("[data-work-vat-enabled]").value=String(patch.enabled);
    form.querySelector("[data-basis-override]").value="true";
    this.editing(form,true);this.dirty=form;
    form.querySelector("[data-work-credit]").value=patch.credit || "";
    const out=form.querySelector("[data-work-vat]");out.textContent=patch.vat;this.vatHint(out,patch.hint);
    this.previewAbort?.abort();clearTimeout(this.vatTimer);this.previewSequence=(this.previewSequence || 0)+1;
    this.status("VAT selection updated. Save the row or press Enter to record it.");
  }
  async vatOperation(form) {
    this.vatOperationAbort?.abort();this.vatOperationAbort=new AbortController();
    const body=new FormData(form);body.delete("_method");
    try {
      const response=await fetch(this.dataset.vatOperationUrl,{method:"POST",body,signal:this.vatOperationAbort.signal,headers:{Accept:"text/vnd.turbo-stream.html","X-CSRF-Token":document.querySelector("meta[name=csrf-token]").content}});
      if (!form.isConnected) return;
      if ([401,403,404].includes(response.status)) return this.clearProtected();
      if (response.headers.get("content-type")?.includes("text/vnd.turbo-stream.html")) window.Turbo.renderStreamMessage(await response.text());
      else this.status("VAT operation unavailable. Check the accounts and amount, then try again.");
    } catch (error) {if(error.name!=="AbortError")this.status("VAT operation unavailable. Your row has not been saved.");}
  }
  accountBasis(form) {
    if (form.querySelector("[data-basis-override]").value === "true") return this.paintBasis(form);
    const accounts=[...form.querySelectorAll("[data-account-lookup]")].filter(h=>h.querySelector("[data-account-id]").value).map(h=>h.querySelector("[data-account-search]"));
    form.querySelector("[data-work-vat-enabled]").value=String(!!form.querySelector("[data-work-vat-entry]").value || accounts.some(a=>a.dataset.accountVat));
    this.paintBasis(form);
  }
  paintBasis(form) {
    const enabled=form.querySelector("[data-work-vat-enabled]").value === "true", override=form.querySelector("[data-basis-override]").value === "true", toggle=form.querySelector("[data-work-included]");
    toggle.checked=enabled; toggle.indeterminate=false;
    toggle.title=`${override ? "Posting override" : "Account default"}: ${enabled ? "Apply VAT" : "No VAT"}. The result account amount stays net. Use VAT operation in More for the exact calculation.`;
    form.querySelector("[data-basis-default]").hidden=form.dataset.editing !== "true" || !override;
  }
  vatHint(out,text) { out.title=text || ""; out.setAttribute("aria-label",text || ""); }
  money(value) { const n = BigInt(value), abs = n<0n ? -n : n; return `${n<0n ? "−" : ""}${abs/100n}${this.dataset.decimalSeparator}${String(abs%100n).padStart(2,"0")}`; }
  clearProtected() { const area = this.closest("#vera-book-content"), p = document.createElement("p"); p.textContent = "Journal access is no longer available. Sign in or refresh your access."; area.replaceChildren(p); }
}
customElements.define("journal-work-editor",JournalWorkEditor);

class JournalVatUpdate extends HTMLElement {
  connectedCallback() {this.dispatchEvent(new CustomEvent("journal-vat:updated",{bubbles:true,detail:{rowId:this.dataset.rowId,patch:JSON.parse(this.dataset.patch)}}));}
}
customElements.define("journal-vat-update",JournalVatUpdate);
