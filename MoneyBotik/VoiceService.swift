import AVFoundation
import Combine
import Foundation
import whisper

@MainActor final class VoiceService:NSObject,ObservableObject,AVAudioRecorderDelegate {
    @Published var recording=false
    @Published var working=false
    @Published var seconds=0
    @Published var transcript=""
    @Published var error:String?
    private var recorder:AVAudioRecorder?
    private var timer:Timer?
    private let transcriber=LocalTranscriber()
    func start() async {
        guard !recording && !working else{return}
        let granted=await withCheckedContinuation{continuation in AVAudioApplication.requestRecordPermission{continuation.resume(returning:$0)}}
        guard granted else{error="Разрешите микрофон: Настройки → MoneyBotik → Микрофон.";return}
        do {
            let session=AVAudioSession.sharedInstance();try session.setCategory(.record,mode:.measurement);try session.setActive(true)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("MoneyBotik-voice-\(UUID().uuidString).wav")
            let r=try AVAudioRecorder(url:url,settings:[AVFormatIDKey:Int(kAudioFormatLinearPCM),AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false]);r.delegate=self
            guard r.record() else{throw InputError("Не удалось включить микрофон.")}
            recorder=r;seconds=0;recording=true;transcript=""
            timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task{@MainActor in guard let self else{return};self.seconds+=1;if self.seconds>=120{await self.stop()}}}
        } catch {self.error=error.localizedDescription;try? AVAudioSession.sharedInstance().setActive(false)}
    }
    func stop() async {
        guard let recorder else{return};timer?.invalidate();self.recorder=nil;recording=false;recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        defer{try? FileManager.default.removeItem(at:recorder.url)}
        await recognize(recorder.url)
    }
    func recognize(_ url:URL) async {
        guard !working else{return};working=true;defer{working=false}
        let opened=url.startAccessingSecurityScopedResource();defer{if opened{url.stopAccessingSecurityScopedResource()}}
        do{let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=20_000_000 else{throw InputError("Максимальный размер аудиофайла — 20 МБ.")};transcript=try await transcriber.transcribe(url)}catch{self.error=error.localizedDescription}
    }
    func cancel(){timer?.invalidate();if let recorder{recorder.stop();try? FileManager.default.removeItem(at:recorder.url)};recorder=nil;recording=false;try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
}
