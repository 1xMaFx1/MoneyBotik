import Foundation
@main struct VoiceCheck {
    static func main() async throws {
        let arguments=CommandLine.arguments
        guard arguments.count==3 else{fatalError("Usage: VoiceCheck MODEL AUDIO")}
        let engine=LocalTranscriber(modelURL:URL(fileURLWithPath:arguments[1]))
        let text=try await engine.transcribe(URL(fileURLWithPath:arguments[2]))
        print("Recognized: \(text)")
        let expense=try ExpenseParser.parse(text).expense()
        guard expense.cents==25000 else{fatalError("Unexpected amount \(expense.cents)")}
        print("PASS: mobile Whisper model recognizes Russian purchase and amount")
    }
}
