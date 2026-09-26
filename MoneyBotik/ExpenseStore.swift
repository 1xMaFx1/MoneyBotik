import Foundation
import Combine

@MainActor final class ExpenseStore: ObservableObject {
    @Published private(set) var expenses:[Expense]=[]
    @Published private(set) var messages:[ChatMessage]=[]
    @Published private(set) var accounts:[Account]=Account.defaults
    @Published var error:String?
    private var loadFailed=false
    private let file:URL
    init(directory:URL?=nil){
        let folder=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MoneyBotik",isDirectory:true)
        file=folder.appendingPathComponent("expenses.json")
        do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:file.path){let archive=try JSONDecoder().decode(Archive.self,from:Data(contentsOf:file));try Self.validate(archive);expenses=archive.expenses;messages=archive.messages;accounts=archive.accounts ?? Account.defaults}
        }catch{loadFailed=true;self.error="Не удалось прочитать данные. Файл сохранён без изменений. \(error.localizedDescription)"}
    }
    var active:[Expense]{expenses.filter{$0.deletedAt==nil}.sorted{$0.date>$1.date}}
    private static func validate(_ archive:Archive)throws{
        guard (1...2).contains(archive.version), archive.expenses.count<=100_000, archive.messages.count<=10_000 else{throw InputError("Неподдерживаемый или слишком большой архив.")}
        let accounts=archive.accounts ?? Account.defaults
        guard accounts.count>0 && accounts.count<=100, Set(accounts.map(\.id)).count==accounts.count,
              accounts.allSatisfy({!$0.id.isEmpty && !$0.name.trimmingCharacters(in:.whitespaces).isEmpty && $0.name.count<=60 && (-10_000_000_000...10_000_000_000).contains($0.openingCents) && $0.goalCents>=0 && $0.goalCents<=10_000_000_000}) else {throw InputError("Некорректные счета в архиве.")}
        let accountIDs=Set(accounts.map(\.id))
        for e in archive.expenses {
            guard accountIDs.contains(e.sourceAccount), ExpenseCategory.options(for:e.kind).contains(e.category),
                e.kind != .transfer || (e.targetAccountID != e.sourceAccount && accountIDs.contains(e.targetAccountID ?? "")) else {throw InputError("Проверьте счета и вид операции в архиве.")}
        }
        var ids=Set<UUID>();for e in archive.expenses{guard ids.insert(e.id).inserted,!e.title.isEmpty,e.title.count<=160,e.cents>0,e.cents<=10_000_000_000,e.date.timeIntervalSince1970.isFinite else{throw InputError("В архиве есть некорректная покупка.")}}
    }
    private func commit(_ items:[Expense],_ chat:[ChatMessage], accounts updatedAccounts:[Account]?=nil)throws{
        guard !loadFailed else{throw InputError("Не удалось прочитать существующие данные. Запись остановлена, чтобы сохранить исходный файл. Восстановите резервную копию после проверки файла.")}
        let archive=Archive(expenses:items,messages:Array(chat.suffix(300)),accounts:updatedAccounts ?? accounts)
        try Self.validate(archive)
        let bytes=try JSONEncoder().encode(archive)
        if FileManager.default.fileExists(atPath:file.path){let previous=try Data(contentsOf:file);try previous.write(to:file.deletingLastPathComponent().appendingPathComponent("previous.json"),options:.atomic)}
        try bytes.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        expenses=items;messages=archive.messages;accounts=archive.accounts ?? Account.defaults
    }
    func save(_ draft:ExpenseDraft)throws{
        let value=try draft.expense();var items=expenses
        if let index=items.firstIndex(where:{$0.id==value.id}){items[index]=value}else{items.append(value)}
        var chat=messages;chat.append(ChatMessage(text:"Сохранено: \(value.title) · \(Money.format(value.cents)) · \(value.category.rawValue).",fromUser:false))
        try commit(items,chat)
    }
    func accountName(_ id:String)->String { accounts.first{$0.id==id}?.name ?? id }
    var balances:FinanceSummary { FinanceSummary(entries:active.filter{$0.date<=Date()}) }
    func saveAccount(_ account:Account)throws {
        var updated=accounts
        if let index=updated.firstIndex(where:{$0.id==account.id}) {updated[index]=account} else {updated.append(account)}
        guard Set(updated.map{$0.name.lowercased().trimmingCharacters(in:.whitespaces)}).count==updated.count else {throw InputError("Счёт с таким названием уже существует.")}
        try commit(expenses,messages,accounts:updated)
    }
    func saveBatch(_ drafts:[ExpenseDraft])throws {
        let values=try drafts.map{try $0.expense()}
        guard !values.isEmpty && values.count<=20 else {throw InputError("Проверьте количество операций.")}
        var chat=messages
        chat.append(ChatMessage(text:"Сохранено операций: \(values.count).",fromUser:false))
        try commit(expenses+values,chat)
    }
    func addMessage(_ text:String,fromUser:Bool)throws{var chat=messages;chat.append(ChatMessage(text:String(text.prefix(3000)),fromUser:fromUser));try commit(expenses,chat)}
    func delete(_ expense:Expense)throws{var items=expenses;if let index=items.firstIndex(where:{$0.id==expense.id}){items[index].deletedAt=Date();try commit(items,messages)}}
    func restore(_ expense:Expense)throws{var items=expenses;if let index=items.firstIndex(where:{$0.id==expense.id}){items[index].deletedAt=nil;try commit(items,messages)}}
    func exportJSON()throws->URL{let url=FileManager.default.temporaryDirectory.appendingPathComponent("MoneyBotik-backup.json");try JSONEncoder().encode(Archive(expenses:expenses,messages:messages,accounts:accounts)).write(to:url,options:.atomic);return url}
    func exportCSV()throws->URL{
        func escape(_ value:String)->String{let text=value.first.map{"=+-@".contains($0)}==true ? "'"+value:value;return "\""+text.replacingOccurrences(of:"\"",with:"\"\"")+"\""}
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd"
        let lines=["Дата;Операция;Сумма, руб.;Категория;Вид;Счёт;Счёт назначения"]+active.map{[f.string(from:$0.date),$0.title,Money.editable($0.cents),$0.category.rawValue,$0.kind.rawValue,accountName($0.sourceAccount),$0.targetAccountID.map(accountName) ?? ""].map(escape).joined(separator:";")}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("MoneyBotik-expenses.csv");try ("\u{feff}"+lines.joined(separator:"\n")).write(to:url,atomically:true,encoding:.utf8);return url
    }
    func exportReport(_ entries:[Expense], period:String)throws->URL {
        let summary=FinanceSummary(entries:entries)
        func cell(_ text:String)->String {"\""+text.replacingOccurrences(of:"\"",with:"\"\"")+"\""}
        var rows:[[String]]=[["P&L · личный бюджет",period],["Показатель","Рубли"],["Доходы",Money.editable(summary.income)],["Расходы до возвратов",Money.editable(summary.grossExpenses)],["Возвраты",Money.editable(summary.refunds)],["Расходы после возвратов",Money.editable(summary.expenses)],["Результат",Money.editable(summary.profit)]]
        if let rate=summary.consumptionRate {rows.append(["Расходы / доходы, %",String(format:"%.2f",rate)])}
        for kind in [TransactionKind.income,.expense,.refund] {
            rows.append([kind.rawValue+" по категориям","Рубли"])
            for category in ExpenseCategory.options(for:kind) {
                let total=entries.filter{$0.kind==kind && $0.category==category}.reduce(Int64(0)){$0+$1.cents}
                if total != 0 {rows.append([category.rawValue,Money.editable(total)])}
            }
        }
        rows.append(["Переводы между своими счетами исключены из результата.",""])
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("MoneyBotik-PL.csv")
        try ("\u{feff}"+rows.map{$0.map(cell).joined(separator:";")}.joined(separator:"\n")).write(to:url,atomically:true,encoding:.utf8)
        return url
    }
    func importBackup(_ url:URL)throws->Int{
        let opened=url.startAccessingSecurityScopedResource();defer{if opened{url.stopAccessingSecurityScopedResource()}}
        guard let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=20_000_000 else{throw InputError("Архив слишком большой: максимум 20 МБ.")}
        let archive=try JSONDecoder().decode(Archive.self,from:Data(contentsOf:url));try Self.validate(archive)
        if loadFailed {
            loadFailed=false
            do{try commit(archive.expenses,archive.messages,accounts:archive.accounts ?? Account.defaults);error=nil;return archive.expenses.count}catch{loadFailed=true;throw error}
        }
        let known=Set(expenses.map(\.id));let additions=archive.expenses.filter{!known.contains($0.id)}
        let importedAccounts=archive.accounts ?? Account.defaults
        let knownAccounts=Set(accounts.map(\.id))
        let pristine=expenses.isEmpty && accounts==Account.defaults
        if !pristine {
            for incoming in importedAccounts {
                if let existing=accounts.first(where:{$0.id==incoming.id}), existing != incoming {
                    throw InputError("Настройки счёта «\(existing.name)» отличаются от копии. Импорт остановлен, чтобы не исказить остатки. Для переноса используйте пустое приложение.")
                }
            }
        }
        let merged=pristine ? importedAccounts : accounts+importedAccounts.filter{!knownAccounts.contains($0.id)}
        try commit(expenses+additions,messages,accounts:merged);return additions.count
    }
}
