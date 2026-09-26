import SwiftUI
import UniformTypeIdentifiers

struct SharedFile:Identifiable{let id=UUID();let url:URL}
struct ShareSheet:UIViewControllerRepresentable{let url:URL;func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)};func updateUIViewController(_ controller:UIActivityViewController,context:Context){}}
struct SettingsView:View{
    @EnvironmentObject var store:ExpenseStore
    @State private var shared:SharedFile?
    @State private var importing=false
    @State private var importURL:URL?
    @State private var notice:String?
    var body:some View{NavigationStack{List{
        Section{Label("Всё на вашем iPhone",systemImage:"checkmark.shield").foregroundStyle(Color.moneyGreen);Text("Операции и записи голоса не отправляются на сервер. Интернет не нужен, в том числе для распознавания.").font(.subheadline).foregroundStyle(.secondary)}
        Section("Финансы"){NavigationLink("Счета и цели накоплений"){AccountsView()}}
        Section("Данные"){Button{perform{shared=SharedFile(url:try store.exportCSV())}}label:{Label("Экспорт операций CSV",systemImage:"square.and.arrow.up")};Button{perform{shared=SharedFile(url:try store.exportJSON())}}label:{Label("Сохранить резервную копию",systemImage:"externaldrive")};Button{importing=true}label:{Label("Импорт резервной копии",systemImage:"square.and.arrow.down")};NavigationLink{TrashView()}label:{Label("Недавно удалённые",systemImage:"trash")}}
        Section("Как пользоваться"){Text("Чат: «кофе 250», «вчера такси 480» или голосом. Доходы и расходы можно отправлять вместе: «зарплата 90000, кофе 250». Переводы: «с карты в накопления 5000». Проверяйте сумму перед сохранением.");Text("Нажмите на сектор диаграммы, чтобы отфильтровать категорию. На столбчатой диаграмме выберите день или месяц для подробностей.");Text("Запись голоса — до двух минут. Для файлов используйте WAV, M4A или MP3 размером до 20 МБ. На iPhone XR распознавание может занять больше времени.");Text("Данные на Mac и iPhone независимы. Автоматической синхронизации нет. Перед удалением приложения сохраните резервную копию.")}.font(.subheadline)
        Section("О приложении"){LabeledContent("MoneyBotik",value:"2.0 · личная версия");Text("Локальное распознавание: whisper.cpp 1.8.3, Whisper base multilingual. Лицензия MIT.").font(.caption).foregroundStyle(.secondary);NavigationLink("Лицензии"){LicensesView()}}
    }.navigationTitle("Ещё").sheet(item:$shared){ShareSheet(url:$0.url)}
    .fileImporter(isPresented:$importing,allowedContentTypes:[.json]){result in switch result{case .success(let url):importURL=url;case .failure(let e):notice=e.localizedDescription}}
    .confirmationDialog("Добавить операции из резервной копии?",isPresented:Binding(get:{importURL != nil},set:{if !$0{importURL=nil}}),titleVisibility:.visible){Button("Добавить операции"){if let url=importURL{perform{let count=try store.importBackup(url);notice="Добавлено операций: \(count). Существующие записи сохранены."}};importURL=nil};Button("Отмена",role:.cancel){importURL=nil}}message:{Text("Новые записи будут объединены с вашей историей. Повторные записи с тем же идентификатором не добавляются.")}
    .alert("MoneyBotik",isPresented:Binding(get:{notice != nil},set:{if !$0{notice=nil}})){Button("Понятно",role:.cancel){}}message:{Text(notice ?? "")}
    }}
    private func perform(_ action:()throws->Void){do{try action()}catch{notice=error.localizedDescription}}
}
struct TrashView:View{
    @EnvironmentObject var store:ExpenseStore
    @State private var error:String?
    var body:some View{List{ForEach(store.expenses.filter{$0.deletedAt != nil}){e in VStack(alignment:.leading){ExpenseRow(expense:e);Button("Восстановить"){do{try store.restore(e)}catch{self.error=error.localizedDescription}}}}}.navigationTitle("Удалённые").overlay{if store.expenses.allSatisfy({$0.deletedAt==nil}){ContentUnavailableView("Корзина пуста",systemImage:"trash")}}.alert("Ошибка",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("Понятно",role:.cancel){}}message:{Text(error ?? "")}}
}
struct LicensesView:View{var body:some View{ScrollView{Text(["whisper-LICENSE","model-LICENSE"].compactMap{Bundle.main.url(forResource:$0,withExtension:"txt")}.compactMap{try? String(contentsOf:$0,encoding:.utf8)}.joined(separator:"\n\n")).font(.caption).textSelection(.enabled).padding()}.navigationTitle("Лицензии")}}
