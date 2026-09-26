import Foundation
@main struct VoiceFinanceChecks {
    static func main() async throws {
        let args=CommandLine.arguments
        guard args.count==3 else{fatalError("Usage: VoiceFinanceChecks MODEL AUDIO")}
        let engine=LocalTranscriber(modelURL:URL(fileURLWithPath:args[1]))
        let text=try await engine.transcribe(URL(fileURLWithPath:args[2]))
        print("Recognized: \(text)")
        let entries=try ExpenseParser.multiple(text).map{try $0.expense()}
        guard entries.contains(where:{$0.kind == .income && $0.cents==9_000_000}), entries.contains(where:{$0.kind == .expense && $0.cents==25000}) else{fatalError("Voice mixed finance mismatch")}
        print("PASS: local voice → mixed income and expense parser")
    }
}
