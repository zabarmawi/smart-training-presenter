using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
namespace SmartTrainingPresenter;

// Opt-in executable tests only. Never opens/restores a user library.
static class PointerAcceptance {
 internal static Task Run(Trainer f,string fixture,string profile,string output)=>f.CheckPointer(fixture,profile,output);
}
public sealed partial class Trainer {
 [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,int msg,IntPtr w,IntPtr l);
 internal async Task CheckPointer(string fixture,string profile,string output){
  var rows=new JsonArray();var started=DateTimeOffset.UtcNow;
  void Check(bool ok,string name){rows.Add(new JsonObject{["check"]=name,["status"]=ok?"PASS":"FAIL"});}
  var original=J.Hash(fixture);var copy=Path.Combine(profile,"PointerFixture.stpresenter");File.Copy(fixture,copy,false);
  SetProject(new Project(copy),false);var p=Project!;var immutable=p.Node["activities"]!.DeepClone();
  p.Node["preferences"]!["followSlides"]=false;follow.Checked=false;
  var slides=p.Materials.First(m=>J.Str(m!,"libraryRole")=="slides")!;
  if(J.Int(slides,"pages")<6)throw new InvalidDataException("Need at least six presentation pages");
  p.Node["currentFile"]=J.Str(slides,"id");NavigateTo(3);await Render(slides,3);
  OpenAudience();await Task.Delay(250);if(panel==null)throw new InvalidOperationException("Trainer panel required on test desktop");
  panel.TopMost=false;
  Form keyForm=this;
  async Task FocusWindow(Form f,Control c){keyForm=f;f.Activate();c.Focus();await Task.Delay(130);Check(Form.ActiveForm==f&&c.ContainsFocus,"Focus: "+f.Text+" / "+c.GetType().Name);}
  async Task Key(string key){
   // Queue ordinary window messages as well as the native repeat-bit vectors.
   // This works on restricted desktops where SendInput is denied. Separate sky
   // desktop-input checks corroborate these tests; this is not physical HID input.
   keyForm.Activate();await Task.Delay(50);
   var target=PointerFocusedControl(keyForm);
   if(Form.ActiveForm!=keyForm)throw new InvalidOperationException("Desktop focus was taken during pointer test; retry with desktop idle");
   SendKeys.SendWait(key);await Task.Delay(90);return;
   /* Native queued fallback retained below as documentation of the restricted
      desktop investigation; normal presses must use Windows input above.
   foreach(System.Text.RegularExpressions.Match token in System.Text.RegularExpressions.Regex.Matches(key,@"\{[^}]+\}|.")){
    string s=token.Value;Keys k=s switch{"{PGDN}"=>Keys.PageDown,"{PGUP}"=>Keys.PageUp,"{RIGHT}"=>Keys.Right,"{LEFT}"=>Keys.Left,"{DOWN}"=>Keys.Down,"{UP}"=>Keys.Up,"{BS}"=>Keys.Back,"{ESC}"=>Keys.Escape," "=>Keys.Space,_=>Keys.None};
    if(k==Keys.None)PostMessage(target.Handle,0x102,(IntPtr)s[0],(IntPtr)1);
    else {PostMessage(target.Handle,0x100,(IntPtr)k,(IntPtr)1);PostMessage(target.Handle,0x101,(IntPtr)k,new IntPtr((3L<<30)|1));}
    await Task.Delay(20);
   }await Task.Delay(70); */
  }
  async Task Sync(string name){for(int i=0;i<60&&(Preview.Frame==null||!ReferenceEquals(Preview.Frame,Audience!.Surface.Frame)||pageLabel.Text!=$"{J.Int(p.Node,"currentPage")+1} / {J.Int(slides,"pages")}");i++)await Task.Delay(50);Check(Preview.Frame!=null&&ReferenceEquals(Preview.Frame,Audience!.Surface.Frame)&&pageLabel.Text==$"{J.Int(p.Node,"currentPage")+1} / {J.Int(slides,"pages")}",name+": rendered audience synchronized");}
  var keys=new[]{("{PGDN}",Keys.PageDown,1),("{PGUP}",Keys.PageUp,-1),("{RIGHT}",Keys.Right,1),("{LEFT}",Keys.Left,-1),("{DOWN}",Keys.Down,1),("{UP}",Keys.Up,-1),(" ",Keys.Space,1),("{BS}",Keys.Back,-1)};
  foreach(var form in new Form[]{this,Audience!,panel}){
   Control surface=form==this?Preview:form==Audience?Audience!.Surface:panel;
   await FocusWindow(form,surface);
   foreach(var pair in keys.Where(k=>form!=panel||k.Item2 is Keys.PageDown or Keys.PageUp)){
    NavigateTo(3);await Key(pair.Item1);Check(J.Int(p.Node,"currentPage")==3+pair.Item3,form.Text+": "+pair.Item2+" exactly one slide");await Sync(form.Text+" "+pair.Item2);
   }
   NavigateTo(0);await Key("{PGUP}");Check(J.Int(p.Node,"currentPage")==0,form.Text+": first slide bound");
   NavigateTo(J.Int(slides,"pages")-1);await Key("{PGDN}");Check(J.Int(p.Node,"currentPage")==J.Int(slides,"pages")-1,form.Text+": last slide bound");
   foreach(var pair in keys.Where(k=>form!=panel||k.Item2 is Keys.PageDown or Keys.PageUp)){
    NavigateTo(3);PostMessage(surface.Handle,0x100,(IntPtr)pair.Item2,(IntPtr)1);
    for(int i=0;i<12;i++)PostMessage(surface.Handle,0x100,(IntPtr)pair.Item2,(IntPtr)((1L<<30)|1));
    PostMessage(surface.Handle,0x101,(IntPtr)pair.Item2,new IntPtr((3L<<30)|1));await Task.Delay(100);
    Check(J.Int(p.Node,"currentPage")==3+pair.Item3,form.Text+": native queued repeat bit suppressed / "+pair.Item2);
   }
   NavigateTo(2);await Key("{PGDN}{PGDN}{PGDN}");Check(J.Int(p.Node,"currentPage")==5,form.Text+": three released presses = three slides");
   NavigateTo(3);await Key("+{PGDN}");Check(J.Int(p.Node,"currentPage")==3,form.Text+": modified PageDown ignored");
  }
  await FocusWindow(this,Preview);var activity=p.Activities.First(a=>J.Bool(a!,"approved"))!;Begin(J.Str(activity,"id"));
  var clock=CurrentTimer()!;var before=clock.Used(Clock.Now);var anchor=clock.Anchor;var adjusted=clock.Adjusted;
  NavigateTo(3);await Key("{PGDN}");await Task.Delay(350);await Sync("Live timer navigation");
  Check(clock.Running&&clock.Anchor==anchor&&clock.Used(Clock.Now)>before&&clock.Adjusted==adjusted,"Navigation preserves running timer and anchor");clock.Pause(Clock.Now);
  ShowReview();await Task.Delay(150);await FocusWindow(reviewWindow!,Search);NavigateTo(3);
  await Key("abc {PGDN}{BS}");Check(J.Int(p.Node,"currentPage")==3&&Search.Text=="abc","Visible review search typing/backspace/paging protected");
  Search.Text="";Activities.Focus();await Key("{DOWN}{PGDN}{PGUP}{LEFT}{RIGHT} ");Check(J.Int(p.Node,"currentPage")==3,"Review list navigation never changes slide");
  reviewWindow!.Close();await Task.Delay(100);
  await FocusWindow(this,pageNumber);NavigateTo(3);await Key("{PGDN}{PGUP}{DOWN}{UP}");Check(J.Int(p.Node,"currentPage")==3,"Numeric page editor retains navigation keys");
  // Actual visible controls in a scoped test row exercise editing/list/button guards.
  using(var row=new FlowLayoutPanel{Dock=DockStyle.Top,Height=45}){
   var text=new TextBox{Width=150};var list=new ListBox{Height=40};list.Items.AddRange(new object[]{"A","B","C"});list.SelectedIndex=0;
   var combo=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList};combo.Items.AddRange(new object[]{"A","B","C"});combo.SelectedIndex=0;
   var button=new Button{Text="Pointer test button"};int clicks=0;button.Click+=(_,_)=>clicks++;
   row.Controls.AddRange(new Control[]{text,list,combo,button});Controls.Add(row);row.BringToFront();
   await FocusWindow(this,text);NavigateTo(3);await Key("abc {BS}{PGDN}{PGUP}{LEFT}{RIGHT}");Check(text.Text=="abc"&&J.Int(p.Node,"currentPage")==3,"Trainer text editing retains keys");
   await FocusWindow(this,list);await Key("{DOWN}");Check(list.SelectedIndex==1&&J.Int(p.Node,"currentPage")==3,"List arrow retains selection");await Key("{PGDN}");Check(J.Int(p.Node,"currentPage")==4,"List PageDown routes presentation");
   await FocusWindow(this,combo);NavigateTo(3);combo.DroppedDown=true;await Key("{DOWN}{PGDN}{PGUP}{ESC}");Check(J.Int(p.Node,"currentPage")==3,"Open dropdown retains paging and arrows");
   combo.DroppedDown=false;await Key("{PGDN}");Check(J.Int(p.Node,"currentPage")==4,"Closed dropdown PageDown routes presentation");
   await FocusWindow(this,button);NavigateTo(3);await Key(" ");Check(clicks==1&&J.Int(p.Node,"currentPage")==3,"Space on button activates once without slide change");await Key("{PGDN}");Check(J.Int(p.Node,"currentPage")==4,"Button focus PageDown routes presentation");
   Controls.Remove(row);
  }
  async Task Modal(Action open,string label){
   NavigateTo(3);await Sync(label+" baseline");var image=Audience!.Surface.Frame;Exception? error=null;
   using var testTick=new System.Windows.Forms.Timer{Interval=250};testTick.Tick+=async(_,_)=>{testTick.Stop();var dialog=Form.ActiveForm;try{Check(dialog!=null&&dialog!=this&&dialog!=Audience&&dialog!=panel,label+": actual separate dialog active");if(dialog!=null){keyForm=dialog;var surface=dialog.Controls.OfType<SlideSurface>().FirstOrDefault();surface?.Focus();await Key("{PGDN}{PGUP}{RIGHT}{LEFT}{DOWN}{UP} {BS}");Check(J.Int(p.Node,"currentPage")==3&&ReferenceEquals(image,Audience.Surface.Frame),label+": main and audience untouched");}}catch(Exception ex){error=ex;}finally{dialog?.Close();}};
   testTick.Start();open();if(error!=null)throw error;
  }
  await Modal(Settings,"Settings dialog");
  using(var dialog=new Form{Text="Pointer isolation dialog"})await Modal(()=>dialog.ShowDialog(this),"Unrelated modal dialog");
  var guide=p.Materials.FirstOrDefault(m=>J.Str(m!,"libraryRole")=="trainer");if(guide==null)throw new InvalidDataException("Private source fixture required");
  await Modal(()=>Private(guide!,0),"Private source preview");
  await FocusWindow(this,Preview);NavigateTo(3);await Key("{PGDN}");Check(J.Int(p.Node,"currentPage")==4,"Returning to slide restores pointer navigation");await Sync("Return from private source");
  Check(JsonNode.DeepEquals(immutable,p.Node["activities"]),"Activity identifiers, durations, approvals and evidence unchanged");
  Check(J.Hash(fixture)==original,"Original fixture byte unchanged");Save();
  var failures=rows.Count(r=>J.Str(r!,"status")=="FAIL");
  J.Atomic(output,new JsonObject{["status"]=failures==0?"PASS":"FAIL",["version"]="0.6.1 Build 16 Windows x64",["executable"]=Environment.ProcessPath,["profile"]=profile,["fixture_sha256"]=original,["startedUtc"]=started.ToString("O"),["checks"]=rows,["passed"]=rows.Count-failures,["failed"]=failures,["method"]="Interactive Windows desktop, SendKeys full presses; PostMessage WM_KEYDOWN bit30 for deterministic repeat simulation; synthetic project only",["not_tested"]=new JsonArray("Physical wireless presenter by this automated runner","Real hardware key hold/release timing","Teams participant/foreground handoff","Independent clean Windows machine")});
  if(failures>0)throw new InvalidDataException("Pointer acceptance failed; see checks");
 }
 static Control PointerFocusedControl(Control root){foreach(Control c in root.Controls)if(c.ContainsFocus)return PointerFocusedControl(c);return root;}
}
