import Foundation
@main struct GenerateTimerVectors {
 static func main() throws {
 let args=CommandLine.arguments;let scenarios=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[1]))) as! [[String:Any]]
 var output:[[String:Any]]=[]
 for s in scenarios {
  var c=Countdown(s["duration"] as! Double),frames:[[String:Any]]=[]
  for op in s["operations"] as! [[String:Any]] {
   let now=op["at"] as! Double,kind=op["op"] as! String;var events:[Int]=[]
   switch kind {case "toggle":c.toggle(now);case "pause":c.pause(now);case "reset":c.reset();case "extend":c.extend(op["seconds"] as! Double,now:now);case "changeDuration":c.changeDuration(op["seconds"] as! Double,now:now);case "poll":events=c.poll(now);case "checkpoint":c=c.checkpoint(now);default:break}
   frames.append(["used":c.used(now),"remaining":c.remaining(now),"running":c.running,"extensions":c.extensions,"adjusted":c.adjusted,"events":events,"fired":c.fired.sorted(),"formatted":timeText(c.remaining(now))])
  }
  output.append(["name":s["name"]!,"frames":frames])
 }
 try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[2]))
 }
}
