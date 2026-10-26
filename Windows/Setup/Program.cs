using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using System.Windows.Forms;
[assembly: AssemblyVersion("0.6.1.16")]
[assembly: AssemblyFileVersion("0.6.1.16")]
namespace Setup {
static class Program {
 [STAThread] static int Main(string[] args) {
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
  try {
   if(args.Length==2 && args[0]=="--install") {Install(args[1]);return 0;}
   var form=new Form{Text="Smart Training Presenter — Windows x64 Setup",Width=750,Height=350,RightToLeft=RightToLeft.Yes,RightToLeftLayout=true,StartPosition=FormStartPosition.CenterScreen};
   var layout=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new Padding(24)};
   layout.Controls.Add(new Label{Text="تثبيت محلي للمستخدم — Smart Training Presenter\nيتطلب .NET Desktop Runtime 10 x64 وعارض Windows PDF المضمّن.\nالمكتبة الخاصة لا تُضمّن في المثبّت؛ تُستورد من داخل التطبيق.",AutoSize=true});
   var path=new TextBox{Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","SmartTrainingPresenter-Build16"),Width=650};layout.Controls.Add(path);
   var choose=new Button{Text="اختيار المجلد",AutoSize=true};choose.Click+=(s,e)=>{using(var d=new FolderBrowserDialog())if(d.ShowDialog(form)==DialogResult.OK)path.Text=d.SelectedPath;};layout.Controls.Add(choose);
   var install=new Button{Text="تثبيت",AutoSize=true};var status=new Label{AutoSize=true,MaximumSize=new System.Drawing.Size(650,0)};
   install.Click+=(s,e)=>{try{Install(path.Text);status.Text="اكتمل التثبيت والتحقق من بصمات الملفات. افتح SmartTrainingPresenter.exe من المجلد المحدد.";}catch(Exception ex){status.Text=ex.Message;}};
   layout.Controls.Add(install);layout.Controls.Add(status);form.Controls.Add(layout);Application.Run(form);return 0;
  }catch(Exception e){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"setup-error.txt"),e.ToString());return 1;}
 }
 static string Digest(string path){using(var f=File.OpenRead(path))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
 static void Install(string destination) {
  var runtime=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"dotnet","shared","Microsoft.WindowsDesktop.App");
  if(!Directory.Exists(runtime)||Directory.GetDirectories(runtime,"10.*").Length==0)throw new IOException("يتطلب التطبيق .NET Desktop Runtime 10 x64. ثبّته من dotnet.microsoft.com ثم أعد التثبيت؛ لم تُغيّر بياناتك.");
  var target=Path.GetFullPath(destination);
  if(File.Exists(target)||(Directory.Exists(target)&&Directory.GetFileSystemEntries(target).Length!=0))throw new IOException("اختر مجلدًا جديدًا أو فارغًا؛ لا تُستبدل بيانات أو نسخة موجودة.");
  var staging=Path.Combine(Path.GetTempPath(),"STP-install-"+Guid.NewGuid());Directory.CreateDirectory(staging);
  try {
   using(var resource=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")) {
    if(resource==null)throw new IOException("حزمة التثبيت غير موجودة");
    using(var archive=new ZipArchive(resource,ZipArchiveMode.Read))foreach(var entry in archive.Entries) {
     var name=entry.FullName;
     if(name.Contains("\\")||name.Contains(":")||Array.IndexOf(name.Split('/'),"..")>=0||Path.IsPathRooted(name))throw new InvalidDataException("مسار تثبيت غير آمن");
     var path=Path.GetFullPath(Path.Combine(staging,name));
     if(!path.StartsWith(staging+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("مسار غير آمن");
     if(name.EndsWith("/")){Directory.CreateDirectory(path);continue;}
     Directory.CreateDirectory(Path.GetDirectoryName(path));entry.ExtractToFile(path,false);
    }
   }
   var serializer=new JavaScriptSerializer();var hashes=serializer.Deserialize<Dictionary<string,string>>(File.ReadAllText(Path.Combine(staging,"APP-SHA256.json")));
   foreach(var item in hashes)if(Digest(Path.Combine(staging,item.Key))!=item.Value)throw new IOException("بصمة تثبيت غير مطابقة: "+item.Key);
   Directory.CreateDirectory(target);
   foreach(var item in hashes){var source=Path.Combine(staging,item.Key);var output=Path.Combine(target,item.Key);Directory.CreateDirectory(Path.GetDirectoryName(output));File.Copy(source,output,false);if(Digest(output)!=item.Value)throw new IOException("بصمة الملف المثبت غير مطابقة");}
   File.Copy(Path.Combine(staging,"APP-SHA256.json"),Path.Combine(target,"APP-SHA256.json"),false);Directory.Delete(staging,true);
   var shortcuts=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),"Programs","Smart Training Presenter");Directory.CreateDirectory(shortcuts);dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));dynamic shortcut=shell.CreateShortcut(Path.Combine(shortcuts,"Smart Training Presenter B16.lnk"));shortcut.TargetPath=Path.Combine(target,"SmartTrainingPresenter.exe");shortcut.Arguments="";shortcut.WorkingDirectory=target;shortcut.Description="Smart Training Presenter — Build 16";shortcut.Save();System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shortcut);System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
   File.WriteAllText(Path.Combine(target,"installation-receipt.json"),serializer.Serialize(new{version="0.6.1.16",architecture="x64",installedAt=DateTimeOffset.UtcNow.ToString("o"),files=hashes.Count,hashesVerified=true,scope="folder installation; user profile kept separate",runtime="Microsoft.WindowsDesktop.App 10.0.x x64",pdf="Windows.Data.Pdf adapter bundled; Windows built-in runtime"}));
  }catch{if(Directory.Exists(staging))Directory.Delete(staging,true);throw;}
 }
}
}

