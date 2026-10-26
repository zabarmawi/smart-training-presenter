namespace SmartTrainingPresenter;

// WinForms UI-thread message filter, scoped to this trainer's three windows.
// No system keyboard hook and no input from Teams or another application.
sealed class PresentationKeys(Trainer trainer):IMessageFilter {
 internal static int Delta(Keys key)=>key switch {
  Keys.PageDown or Keys.Right or Keys.Down or Keys.Space=>1,
  Keys.PageUp or Keys.Left or Keys.Up or Keys.Back=>-1,
  _=>0
 };
 public bool PreFilterMessage(ref Message m){
  if(m.Msg!=0x100 || Control.ModifierKeys!=Keys.None)return false; // WM_KEYDOWN
  var key=(Keys)(int)m.WParam;var delta=Delta(key);if(delta==0)return false;
  var target=Control.FromChildHandle(m.HWnd);var form=target?.FindForm();
  if(form==null || Form.ActiveForm!=form || !trainer.PresentationWindow(form) || trainer.Project==null)return false;
  // Editing, selection and modal dialogs retain their native navigation keys.
  for(Control? c=target;c!=null && c!=form;c=c.Parent){
   if(c is TextBoxBase or UpDownBase)return false;
   bool paging=key is Keys.PageDown or Keys.PageUp;
   if(c is ComboBox combo && (combo.DropDownStyle!=ComboBoxStyle.DropDownList || combo.DroppedDown || !paging))return false;
   if(!paging && (c is ListControl or DataGridView or TrackBar))return false;
   if(c is ButtonBase && key==Keys.Space)return false;
  }
  if(trainer.OwnedForms.Any(f=>f.Visible&&f.Modal))return false;
  if((m.LParam.ToInt64() & (1L<<30))==0)trainer.Guard(()=>trainer.Navigate(delta));
  return true; // Consume repeats/bounds too: a key must never navigate twice.
 }
}
public sealed partial class Trainer {
 PresentationKeys? presentationKeys;
 internal bool PresentationWindow(Form form)=>form==this || form==Audience || form==panel;
 void InstallPresentationKeys(){presentationKeys=new PresentationKeys(this);Application.AddMessageFilter(presentationKeys);FormClosed+=(_,_)=>{Application.RemoveMessageFilter(presentationKeys);presentationKeys=null;};}
}

