class VeraToast extends HTMLElement {
  connectedCallback() {
    const stack=document.getElementById('vera-feedback');
    if (stack && this.parentElement!==stack) {stack.append(this);return;}
    this.abort?.abort();this.abort=new AbortController();
    this.querySelector('[data-toast-close]')?.addEventListener('click',()=>{
      const focused=this.contains(document.activeElement);this.remove();
      if (focused) {
        const next=document.querySelector('#vera-feedback [data-toast-close]') || document.querySelector('main h1');
        if (next) {if(next.matches('h1'))next.tabIndex=-1;next.focus({preventScroll:true});}
      }
    },{signal:this.abort.signal});
  }
  disconnectedCallback() {this.abort?.abort();}
}
customElements.define('vera-toast',VeraToast);
document.addEventListener('vera:notify',event=>{
  const {id,message,kind}=event.detail;
  if(id)document.getElementById(id)?.remove();
  if(!message)return;
  const stack=document.getElementById('vera-feedback');if(!stack)return;
  const toast=document.createElement('vera-toast');toast.className='vera-toast';toast.dataset.kind=kind || 'notice';if(id)toast.id=id;
  const close=document.createElement('button');close.type='button';close.className='vera-toast-close';close.dataset.toastClose='';close.setAttribute('aria-label','Dismiss notification');close.textContent='×';
  const text=document.createElement('p');text.className='text-sm leading-relaxed';text.setAttribute('role',kind==='alert'?'alert':'status');text.textContent=message;
  toast.append(close,text);stack.append(toast);
});
