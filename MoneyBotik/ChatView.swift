import SwiftUI
import UniformTypeIdentifiers

struct ChatView:View{
    @EnvironmentObject var store:ExpenseStore
    @StateObject private var voice=VoiceService()
    @Environment(\.scenePhase) private var phase
    @State private var text=""
    @State private var batch:DraftBatch?
    @State private var importAudio=false
    @State private var error:String?
    @FocusState private var inputFocused:Bool
    var body:some View{NavigationStack{VStack(spacing:0){
        ScrollViewReader{proxy in ScrollView{LazyVStack(alignment:.leading,spacing:14){
            VStack(alignment:.leading,spacing:10){Label("Расскажите о деньгах",systemImage:"sparkles").font(.title3.bold());Text("Например: «зарплата 90000, кофе 250, такси 480». Доходы, расходы и переводы распознаются на iPhone. Проверьте результат перед сохранением.").foregroundStyle(.secondary);Button("Вчера продукты 1450"){text="Вчера продукты 1450"}}.padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.cardBackground,in:RoundedRectangle(cornerRadius:18))
            ForEach(store.messages){message in HStack{if message.fromUser{Spacer(minLength:30)};Text(message.text).padding(14).foregroundStyle(message.fromUser ? Color.white:Color.primary).background(message.fromUser ? Color.moneyGreen:Color.cardBackground,in:RoundedRectangle(cornerRadius:16));if !message.fromUser{Spacer(minLength:30)}}.id(message.id)}
            Color.clear.frame(height:1).id("bottom")
        }.padding()}.onChange(of:store.messages.count){_,_ in withAnimation{proxy.scrollTo("bottom",anchor:.bottom)}}}
        VStack(alignment:.leading,spacing:12){
            if voice.working{HStack{ProgressView();Text("Распознаю на iPhone…").font(.subheadline)}.accessibilityIdentifier("voiceProgress")}
            if voice.recording{Label("Идёт запись · \(voice.seconds / 60):\(String(format:"%02d",voice.seconds % 60))",systemImage:"waveform").foregroundStyle(.red).font(.subheadline)}
            TextField("Доходы, расходы или переводы…",text:$text,axis:.vertical).lineLimit(2...5).focused($inputFocused).padding(12).background(Color.pageBackground,in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("chatInput")
            ViewThatFits(in:.horizontal){controls;VStack(alignment:.leading,spacing:12){voiceControls;sendButton}}
            Text("Без интернета · несколько операций в сообщении").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding().background(Color.cardBackground).dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }.background(Color.pageBackground).navigationTitle("Денежный чат").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("Готово"){inputFocused=false}}}
    .sheet(item:$batch){BatchReview(drafts:$0.drafts)}
    .fileImporter(isPresented:$importAudio,allowedContentTypes:[.audio]){result in switch result{case .success(let url):Task{await voice.recognize(url)};case .failure(let e):error=e.localizedDescription}}
    .onChange(of:voice.transcript){_,value in if !value.isEmpty{text=value}}
    .onChange(of:phase){_,value in if value != .active && voice.recording{Task{await voice.stop()}}}
    .onDisappear{if voice.recording{voice.cancel()}}
    .alert("Сообщение",isPresented:Binding(get:{error != nil || voice.error != nil},set:{if !$0{error=nil;voice.error=nil}})){Button("Понятно",role:.cancel){}}message:{Text(error ?? voice.error ?? "")}
    }}
    private var controls:some View{HStack{voiceControls;Spacer();sendButton}}
    private var voiceControls:some View{HStack(spacing:16){Button{Task{if voice.recording{await voice.stop()}else{await voice.start()}}}label:{Label(voice.recording ? "Стоп":"Голос",systemImage:voice.recording ? "stop.circle.fill":"mic.fill")}.disabled(voice.working).accessibilityIdentifier("voiceButton");Button{importAudio=true}label:{Image(systemName:"paperclip")}.accessibilityLabel("Прикрепить аудио").disabled(voice.recording || voice.working)}}
    private var sendButton:some View{Button{send()}label:{HStack{Text("Отправить").fixedSize(horizontal:false,vertical:true);Image(systemName:"arrow.up")}.fontWeight(.semibold)}.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || voice.recording || voice.working).accessibilityIdentifier("sendMessage")}
    private func send(){do{let value=text;try store.addMessage(value,fromUser:true);let parsed=try ExpenseParser.multiple(value,accounts:store.accounts);batch=DraftBatch(drafts:parsed);try store.addMessage("Проверьте детали перед сохранением. Операций: \(parsed.count).",fromUser:false);text="";inputFocused=false}catch{self.error=error.localizedDescription;try? store.addMessage(error.localizedDescription,fromUser:false)}}
}

struct DraftBatch:Identifiable {let id=UUID();var drafts:[ExpenseDraft]}
struct BatchReview:View {
    @EnvironmentObject var store:ExpenseStore
    @Environment(\.dismiss) var dismiss
    @State var drafts:[ExpenseDraft]
    @State private var error:String?
    @State private var saving=false
    var body:some View {NavigationStack {Form {
        Section {Text("Проверьте все операции. Кнопка ниже сохранит их вместе. Отмена не изменит счета.").foregroundStyle(.secondary)}
        ForEach($drafts) { $draft in
            Section {
                TextField("Описание",text:$draft.title,axis:.vertical)
                Picker("Вид",selection:$draft.kind){ForEach(TransactionKind.allCases){Text($0.rawValue).tag($0)}}.onChange(of:draft.kind){_,kind in draft.category=ExpenseCategory.options(for:kind).first ?? .other}
                TextField("Сумма, ₽",text:$draft.amount).keyboardType(.decimalPad)
                Picker("Категория",selection:$draft.category){ForEach(ExpenseCategory.options(for:draft.kind)){Text($0.rawValue).tag($0)}}
                Picker(draft.kind == .transfer ? "Откуда":"Счёт",selection:$draft.accountID){ForEach(store.accounts){Text($0.name).tag($0.id)}}
                if draft.kind == .transfer {Picker("Куда",selection:$draft.targetAccountID){ForEach(store.accounts){Text($0.name).tag($0.id)}}}
                DatePicker("Дата",selection:$draft.date,displayedComponents:.date)
                if let note=draft.note {Text(note).font(.caption).foregroundStyle(.orange)}
            }
        }
        if let error {Text(error).foregroundStyle(.red)}
        Button("Сохранить все: \(drafts.count)"){guard !saving else{return};saving=true;do{try store.saveBatch(drafts);dismiss()}catch{self.error=error.localizedDescription;saving=false}}.disabled(saving).accessibilityIdentifier("saveBatch")
    }.navigationTitle("Проверка операций").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction){Button("Отмена"){dismiss()}}}}}
}
