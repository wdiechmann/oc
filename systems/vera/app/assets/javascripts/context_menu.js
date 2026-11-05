class ContextMenu extends HTMLElement {
  connectedCallback() {
    this.abort = new AbortController();
    const options={signal:this.abort.signal};
    this.trigger=this.querySelector('[data-menu-trigger]');
    this.menu=this.querySelector('[data-context-menu]');
    this.trigger.addEventListener('click',()=>this.open(),options);
    this.menu.addEventListener('toggle',event=>{
      this.trigger.setAttribute('aria-expanded',String(event.newState==='open'));
    },options);
    this.menu.addEventListener('click',event=>{
      if(event.target.closest('[role=menuitem]')) this.close(true);
    },options);
    this.addEventListener('keydown',event=>this.key(event),options);
    window.addEventListener('resize',()=>this.close(false),options);
    document.addEventListener('scroll',event=>{if(!this.menu.contains(event.target))this.close(false);},{...options,capture:true});
  }
  disconnectedCallback() { this.abort.abort(); }
  items() { return [...this.menu.querySelectorAll('[role=menuitem]')].filter(item=>!item.disabled && !item.hidden && item.getClientRects().length); }
  open(last=false) {
    if(this.menu.matches(':popover-open')) return this.close(true);
    this.menu.showPopover();
    const rect=this.trigger.getBoundingClientRect(), width=this.menu.offsetWidth, height=this.menu.offsetHeight;
    this.menu.style.left=`${Math.max(8,Math.min(rect.right-width,innerWidth-width-8))}px`;
    this.menu.style.top=`${Math.max(8,rect.bottom+height+8>innerHeight ? rect.top-height-4 : rect.bottom+4)}px`;
    this.trigger.setAttribute('aria-expanded','true');
    const items=this.items(); (last ? items.at(-1) : items[0])?.focus({preventScroll:true});
  }
  close(restore=true) {
    if(!this.menu.matches(':popover-open'))return;
    this.menu.hidePopover();this.trigger.setAttribute('aria-expanded','false');
    if(restore)this.trigger.focus({preventScroll:true});
  }
  key(event) {
    if(event.isComposing)return;
    if(event.target===this.trigger && ['ArrowDown','ArrowUp'].includes(event.key)) {
      event.preventDefault();event.stopPropagation();return this.open(event.key==='ArrowUp');
    }
    if(!this.menu.matches(':popover-open'))return;
    if(event.key==='Escape') {event.preventDefault();event.stopPropagation();this.close(true);this.dispatchEvent(new CustomEvent("context-menu:escape",{bubbles:true}));return;}
    if(event.key==='Tab') {this.close(true);return;}
    if(['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
      event.preventDefault();event.stopPropagation();const items=this.items(),index=items.indexOf(document.activeElement);
      const next=event.key==='Home' ? 0 : event.key==='End' ? items.length-1 : (index+(event.key==='ArrowDown' ? 1 : -1)+items.length)%items.length;
      items[next]?.focus({preventScroll:true});
    }
  }
}
customElements.define('context-menu',ContextMenu);
