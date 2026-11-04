const dialogOrigins = new Map();
class SharedDialog extends HTMLElement {
  connectedCallback() {
    this.abort=new AbortController();
    this.dialog=this.querySelector('dialog');
    this.origin=dialogOrigins.get(this.dialog.id) || document.activeElement;
    dialogOrigins.set(this.dialog.id,this.origin);
    this.querySelector('[data-dialog-close]').addEventListener('click',()=>this.close(),{signal:this.abort.signal});
    this.dialog.addEventListener('cancel',event=>{event.preventDefault();this.close();},{signal:this.abort.signal});
    this.dialog.showModal();
    (this.dialog.querySelector('input[type=file]') || this.dialog.querySelector('input[type=submit],button'))?.focus({preventScroll:true});
  }
  disconnectedCallback() {this.abort.abort();requestAnimationFrame(()=>{if(!document.getElementById(this.dialog.id)?.open)dialogOrigins.delete(this.dialog.id);});}
  close() {
    this.dialog.close();this.remove();dialogOrigins.delete(this.dialog.id);
    const target=(this.origin?.id && document.getElementById(this.origin.id)) || (this.origin?.isConnected && this.origin);
    target?.focus({preventScroll:true});
  }
}
customElements.define('shared-dialog',SharedDialog);
