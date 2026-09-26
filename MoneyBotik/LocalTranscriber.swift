@preconcurrency import AVFoundation
import Foundation
import whisper

// AVAudioConverter consumes this buffer synchronously, once per conversion.
private final class AudioFeed: @unchecked Sendable {
    let buffer:AVAudioPCMBuffer
    var supplied=false
    init(_ buffer:AVAudioPCMBuffer){self.buffer=buffer}
}
actor LocalTranscriber {
    private var context: OpaquePointer?
    private let modelURL:URL?
    init(modelURL:URL?=nil){self.modelURL=modelURL}
    deinit { if let context { whisper_free(context) } }
    func transcribe(_ url:URL) throws -> String {
        let file=try AVAudioFile(forReading:url)
        let input=file.processingFormat
        let duration=Double(file.length)/input.sampleRate
        guard duration>0 && duration<=125 else{throw InputError("Запись должна длиться от одной секунды до двух минут.")}
        guard let source=AVAudioPCMBuffer(pcmFormat:input,frameCapacity:AVAudioFrameCount(file.length)),let target=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false),let converter=AVAudioConverter(from:input,to:target),let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:AVAudioFrameCount(duration*16000)+1024) else{throw InputError("Не удалось прочитать аудио. Используйте M4A, WAV или MP3.")}
        try file.read(into:source)
        let feed=AudioFeed(source);var conversionError:NSError?
        converter.convert(to:output,error:&conversionError){_,status in if feed.supplied{status.pointee = .endOfStream;return nil};feed.supplied=true;status.pointee = .haveData;return feed.buffer}
        if let conversionError{throw conversionError}
        guard let channel=output.floatChannelData?[0],output.frameLength>0 else{throw InputError("Аудиофайл не содержит звука.")}
        let samples=Array(UnsafeBufferPointer(start:channel,count:Int(output.frameLength)))
        let energy=samples.reduce(Float(0)){$0+$1*$1}/Float(samples.count)
        guard energy>0.000001 else{throw InputError("Запись слишком тихая. Попробуйте говорить ближе к микрофону.")}
        if context==nil {
            guard let model=modelURL ?? Bundle.main.url(forResource:"ggml-base",withExtension:"bin") else{throw InputError("В сборке отсутствует локальная голосовая модель.")}
            var params=whisper_context_default_params();params.use_gpu=false
            context=whisper_init_from_file_with_params(model.path,params)
        }
        guard let context else{throw InputError("Не удалось открыть голосовую модель. Перезапустите приложение.")}
        var params=whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads=Int32(min(4,ProcessInfo.processInfo.activeProcessorCount));params.translate=false;params.no_context=true;params.single_segment=false
        params.print_realtime=false;params.print_progress=false;params.print_timestamps=false;params.print_special=false
        let result="ru".withCString{language in params.language=language;return samples.withUnsafeBufferPointer{buffer in whisper_full(context,params,buffer.baseAddress,Int32(buffer.count))}}
        guard result==0 else{throw InputError("Не удалось распознать речь. Попробуйте более короткую запись.")}
        let segments=whisper_full_n_segments(context)
        let text=(0..<segments).compactMap{index -> String? in guard let pointer=whisper_full_get_segment_text(context,index) else{return nil};return String(cString:pointer)}.joined().trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else{throw InputError("Речь не обнаружена. Попробуйте ещё раз или напишите текст.")}
        return text
    }
}
