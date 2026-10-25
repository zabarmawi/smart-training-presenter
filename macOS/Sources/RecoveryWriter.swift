import Foundation

// Single writer; frequent UI edits coalesce, and shutdown can flush synchronously.
@MainActor final class RecoveryWriter {
    private let queue=DispatchQueue(label:"com.training.presenter.recovery",qos:.utility)
    private var pending:DispatchWorkItem?
    func schedule(_ project:Project,to url:URL,now:Double,onError:@escaping(String)->Void) {
        pending?.cancel()
        let item=DispatchWorkItem {
            do {try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try DocumentReader.save(project,to:url,now:now)}
            catch {let message=error.localizedDescription;DispatchQueue.main.async {onError(message)}}
        }
        pending=item;queue.asyncAfter(deadline:.now()+0.35,execute:item)
    }
    func flush(_ project:Project,to url:URL,now:Double) throws {
        pending?.cancel();pending=nil
        try queue.sync {try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try DocumentReader.save(project,to:url,now:now)}
    }
}
