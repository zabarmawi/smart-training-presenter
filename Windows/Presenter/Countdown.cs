using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
namespace SmartTrainingPresenter;

// Direct translation of Build 12 Countdown.swift. Only Clock is platform-specific.
public static class Clock {
    [DllImport("kernel32.dll")] static extern ulong GetTickCount64();
    // Windows uptime includes time spent asleep; independent of the civil clock.
    public static double Now => GetTickCount64()/1000.0;
}
public sealed class Countdown {
    public double Original, Adjusted, Extensions, Elapsed, Previous;
    public bool Running; public double? Anchor;
    public HashSet<int> Fired = [];
    public Countdown(double seconds) { Original=Adjusted=Previous=seconds; }
    public double Used(double now) => Elapsed+(Running?Math.Max(0,now-(Anchor??now)):0);
    public double Remaining(double now)=>Adjusted+Extensions-Used(now);
    public void Toggle(double now) { if(Running) {Elapsed=Used(now);Anchor=null;Running=false;} else {Anchor=now;Running=true;} }
    public void Pause(double now) {if(Running)Toggle(now);}
    public void Reset(){Elapsed=0;Extensions=0;Running=false;Anchor=null;Fired.Clear();Previous=Adjusted;}
    public void Extend(double seconds,double now){if(seconds>0&&double.IsFinite(seconds)){Extensions+=seconds;Previous=Remaining(now);}}
    public void ChangeDuration(double seconds,double now){if(seconds>0&&double.IsFinite(seconds)){Adjusted=seconds;Previous=Remaining(now);}}
    public int[] Poll(double now){var r=Remaining(now);var events=new List<int>();if(Running)foreach(var t in new[]{300,60,0})if(!Fired.Contains(t)&&Previous>t&&r<=t){Fired.Add(t);events.Add(t);}Previous=r;return events.ToArray();}
    public Countdown Checkpoint(double now){var c=(Countdown)MemberwiseClone();c.Fired=new(Fired);c.Elapsed=Used(now);c.Running=false;c.Anchor=null;c.Previous=c.Remaining(now);return c;}
    public static string Text(double seconds){if(!double.IsFinite(seconds))return "--:--";var n=(int)Math.Min(35999999,Math.Ceiling(Math.Abs(seconds)));return(seconds<0?"+":"")+(n>=3600?$"{n/3600:00}:{n/60%60:00}:{n%60:00}":$"{n/60:00}:{n%60:00}");}
    public static Countdown Read(JsonNode n,bool resume=false)=>new(J.Num(n,"original")){Adjusted=J.Num(n,"adjusted"),Extensions=J.Num(n,"extensions"),Elapsed=J.Num(n,"elapsed"),Previous=J.Num(n,"previous"),Running=resume&&J.Bool(n,"running"),Anchor=resume?n["anchor"]?.GetValue<double>():null,Fired=n["fired"]?.AsArray().Select(x=>x!.GetValue<int>()).ToHashSet()??[]};
    public JsonObject Write(JsonNode? existing=null){var n=existing?.DeepClone().AsObject()??new();n["original"]=Original;n["adjusted"]=Adjusted;n["extensions"]=Extensions;n["elapsed"]=Elapsed;n["previous"]=Previous;n["running"]=Running;n["anchor"]=Anchor;n["fired"]=new JsonArray(Fired.Order().Select(x=>JsonValue.Create(x)).ToArray());return n;}
    public static void Vectors(string input,string output){var result=new JsonArray();foreach(var s in J.Load(input).AsArray()){var c=new Countdown(J.Num(s!,"duration"));var frames=new JsonArray();foreach(var op in s!["operations"]!.AsArray()){double now=J.Num(op!,"at"),seconds=J.Num(op!,"seconds");int[] events=[];switch(J.Str(op!,"op")){case "toggle":c.Toggle(now);break;case "pause":c.Pause(now);break;case "reset":c.Reset();break;case "extend":c.Extend(seconds,now);break;case "changeDuration":c.ChangeDuration(seconds,now);break;case "poll":events=c.Poll(now);break;case "checkpoint":c=c.Checkpoint(now);break;}frames.Add(new JsonObject{["used"]=c.Used(now),["remaining"]=c.Remaining(now),["running"]=c.Running,["extensions"]=c.Extensions,["adjusted"]=c.Adjusted,["events"]=new JsonArray(events.Select(x=>JsonValue.Create(x)).ToArray()),["fired"]=new JsonArray(c.Fired.Order().Select(x=>JsonValue.Create(x)).ToArray()),["formatted"]=Text(c.Remaining(now))});}result.Add(new JsonObject{["name"]=J.Str(s,"name"),["frames"]=frames});}J.Atomic(output,result);}
}
