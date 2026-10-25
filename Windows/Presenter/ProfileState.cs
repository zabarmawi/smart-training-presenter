using System.Diagnostics;
using System.Text.Json.Nodes;
namespace SmartTrainingPresenter;
static class ProfilePaths {
 public static string NormalRoot=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SmartTrainingPresenter","UserData");
 public static string LegacyRoot=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SmartTrainingPresenter","Windows-Build14");
 public static string Prepare(){var root=NormalRoot;Directory.CreateDirectory(root);var active=Path.Combine(root,"ActiveLibrary.json");
  // A stable profile always wins. Never replace it with the delivery snapshot or legacy state.
  if(!File.Exists(active)&&!Directory.Exists(Path.Combine(root,"Library"))&&!File.Exists(Path.Combine(root,"Recovery.stpresenter"))){
   var oldActive=Path.Combine(LegacyRoot,"ActiveLibrary.json");string? legacy=null;
   if(File.Exists(oldActive)){var old=J.Load(oldActive);var path=J.Str(old,"root");if(File.Exists(Path.Combine(path,"Library/index.json")))legacy=path;}
   else if(File.Exists(Path.Combine(LegacyRoot,"Library/index.json")))legacy=LegacyRoot;
   if(legacy!=null){J.Atomic(active,new JsonObject{["root"]=legacy});J.Atomic(Path.Combine(root,"Migration.json"),new JsonObject{["source"]=LegacyRoot,["activeLibrary"]=legacy,["mode"]="reference existing library; no project decisions copied or overwritten"});}
  }return root;
 }
}
public sealed class LibraryTotals {
 public int Bags,Items,Approvals,Evidence;
 public static LibraryTotals Read(string root,JsonNode index){var t=new LibraryTotals();foreach(var bag in index["bags"]!.AsArray()){var p=J.Load(J.Safe(root,"Library/Projects/"+J.Str(bag!,"id")+".stpresenter"));t.Bags++;t.Items+=p["activities"]!.AsArray().Count;t.Approvals+=p["activities"]!.AsArray().Count(a=>J.Bool(a!,"approved"));t.Evidence+=p["activities"]!.AsArray().Sum(a=>a!["evidence"]!.AsArray().Count);}return t;}
 public string Text=>$"{Bags} حقيبة · {Approvals} اعتمادًا من {Items} · {Evidence} إحالة";
 public JsonObject Json()=>new(){["bags"]=Bags,["time_items"]=Items,["approvals"]=Approvals,["evidence"]=Evidence};
}
