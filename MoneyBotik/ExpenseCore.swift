import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Расход", income = "Доход", transfer = "Перевод", refund = "Возврат"
    var id: String { rawValue }
}
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case groceries = "Продукты", food = "Кафе и еда", transport = "Транспорт", home = "Дом", health = "Здоровье", shopping = "Покупки", fun = "Развлечения", other = "Другое"
    case salary = "Зарплата", freelance = "Подработка", business = "Бизнес", investments = "Инвестиционный доход", gifts = "Подарки", rent = "Сдача в аренду", cashback = "Кешбэк", otherIncome = "Другой доход", transfer = "Между счетами"
    var id: String { rawValue }
    var isIncome: Bool { [.salary,.freelance,.business,.investments,.gifts,.rent,.cashback,.otherIncome].contains(self) }
    static func options(for kind: TransactionKind) -> [Self] {
        if kind == .transfer { return [.transfer] }
        return allCases.filter { $0 != .transfer && $0.isIncome == (kind == .income) }
    }
    var symbol: String { switch self { case .groceries: return "basket"; case .food: return "cup.and.saucer"; case .transport: return "car"; case .home: return "house"; case .health: return "cross.case"; case .shopping: return "bag"; case .fun: return "sparkles"; case .transfer: return "arrow.left.arrow.right"; default: return isIncome ? "arrow.down.circle" : "square.grid.2x2" } }
}
struct Account: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var openingCents: Int64 = 0
    var isSavings = false
    var goalCents: Int64 = 0
    static let defaults = [Account(id:"card",name:"Карта"), Account(id:"cash",name:"Наличные"), Account(id:"savings",name:"Накопления",isSavings:true)]
}
struct Expense: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var cents: Int64
    var category: ExpenseCategory
    var date: Date
    var deletedAt: Date? = nil
    // Optional persisted fields preserve archives from version 1.
    var kindValue: TransactionKind? = nil
    var accountID: String? = nil
    var targetAccountID: String? = nil
    var kind: TransactionKind { kindValue ?? .expense }
    var sourceAccount: String { accountID ?? "card" }
}
struct ChatMessage: Codable, Identifiable { var id = UUID(); var text: String; var fromUser: Bool; var date = Date() }
struct Archive: Codable { var version = 2; var expenses: [Expense]; var messages: [ChatMessage]; var accounts: [Account]? = nil }
struct ExpenseDraft: Identifiable {
    var id = UUID(); var expenseID: UUID?; var title = ""; var amount = ""; var category = ExpenseCategory.other; var date = Date(); var kind = TransactionKind.expense; var accountID = "card"; var targetAccountID = "savings"; var note: String?
    init(expense: Expense? = nil) { if let e = expense { expenseID=e.id; title=e.title; amount=Money.editable(e.cents); category=e.category; date=e.date; kind=e.kind; accountID=e.sourceAccount; targetAccountID=e.targetAccountID ?? "savings" } }
    func expense() throws -> Expense {
        let clean=title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty && clean.count <= 160 else { throw InputError("Название должно содержать от 1 до 160 символов.") }
        guard ExpenseCategory.options(for:kind).contains(category) else { throw InputError("Выберите категорию для этого вида операции.") }
        guard kind != .transfer || accountID != targetAccountID else { throw InputError("Для перевода выберите два разных счёта.") }
        return Expense(id: expenseID ?? UUID(), title: clean, cents: try Money.parse(amount), category: category, date: date, kindValue:kind, accountID:accountID, targetAccountID:kind == .transfer ? targetAccountID:nil)
    }
}
struct InputError: LocalizedError { let message: String; init(_ value:String){message=value}; var errorDescription:String?{message} }
enum Money {
    static func signedOrZero(_ text:String)throws->Int64 {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if ["", "0", "0.00", "0,00"].contains(value) {return 0}
        if value.hasPrefix("-") {return -(try parse(String(value.dropFirst())))}
        return try parse(value)
    }
    static func parse(_ input:String) throws -> Int64 {
        let text=input.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"\u{00a0}",with:"").replacingOccurrences(of:",",with:".")
        guard text.range(of:"^\\d+(?:\\.\\d{1,2})?$",options:.regularExpression) != nil,
              let value=Decimal(string:text,locale:Locale(identifier:"en_US_POSIX")),value>0,value<=100_000_000 else { throw InputError("Введите сумму от 0,01 до 100 000 000 ₽, максимум две цифры после запятой.") }
        return NSDecimalNumber(decimal:value*100).int64Value
    }
    static func format(_ cents:Int64)->String {
        let f=NumberFormatter();f.locale=Locale(identifier:"ru_RU");f.numberStyle = .currency;f.currencyCode="RUB";f.maximumFractionDigits=2
        return f.string(from:NSDecimalNumber(decimal:Decimal(cents)/100)) ?? "0 ₽"
    }
    static func editable(_ cents:Int64)->String { "\(cents < 0 ? "-" : "")\(abs(cents)/100).\(String(format:"%02d",abs(cents)%100))" }
}
enum ExpenseParser {
    static let words:[String:Int64] = ["один":1,"одна":1,"два":2,"две":2,"три":3,"четыре":4,"пять":5,"шесть":6,"семь":7,"восемь":8,"девять":9,"десять":10,"одиннадцать":11,"двенадцать":12,"тринадцать":13,"четырнадцать":14,"пятнадцать":15,"шестнадцать":16,"семнадцать":17,"восемнадцать":18,"девятнадцать":19,"двадцать":20,"тридцать":30,"сорок":40,"пятьдесят":50,"шестьдесят":60,"семьдесят":70,"восемьдесят":80,"девяносто":90,"сто":100,"двести":200,"триста":300,"четыреста":400,"пятьсот":500,"шестьсот":600,"семьсот":700,"восемьсот":800,"девятьсот":900]
    static let keywords:[ExpenseCategory:[String]] = [.groceries:["продукт","молок","хлеб","магазин","пятероч","пятёроч","магнит","сыр","фрукт"],.food:["кофе","кафе","ресторан","обед","ужин","пицц","бургер","доставк","булоч","завтрак"],.transport:["такси","метро","автобус","бензин","парков","проезд","топлив"],.home:["квартир","аренд","коммунал","мебель"],.health:["аптек","лекарств","врач","стоматолог"],.shopping:["одежд","обувь","футболк","джинс","техник","шампун","косметик"],.fun:["кино","игр","подписк","концерт"]]
    static func parse(_ input:String, now:Date=Date(), accounts:[Account]=Account.defaults) throws -> ExpenseDraft {
        var text=input.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty && text.count<=3000 else {throw InputError("Напишите покупку и сумму: кофе 250.")}
        guard text.range(of:"[$€]|доллар|евро|usd|eur",options:.regularExpression)==nil else{throw InputError("Пока учёт ведётся в рублях. Укажите стоимость в рублях.")}
        let original = text
        let type = classify(text)
        let accountMatch = detectAccounts(text, accounts:accounts, transfer:type.0 == .transfer)
        if type.0 == .transfer && accountMatch.1.isEmpty {throw InputError("Укажите счёт назначения перевода, например: с карты в накопления 5000. Перевод другому человеку запишите как расход.")}
        text = accountMatch.2
        let scaled=try NSRegularExpression(pattern:"(?<![\\w.,])([0-9]+(?:[.,][0-9]{1,2})?)\\s*(тыс(?:яч[аи]?)?\\.?|млн\\.?|миллион[а-я]*|к)(?=\\s|$)")
        for match in scaled.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            if let r=Range(match.range,in:text),let amountRange=Range(match.range(at:1),in:text) {
                let amount=try Money.parse(String(text[amountRange]))
                let suffix=Range(match.range(at:2),in:text).map{String(text[$0])} ?? ""
                let factor:Int64=suffix.hasPrefix("м") ? 1_000_000:1000
                guard amount<=10_000_000_000/factor else{throw InputError("Сумма слишком большая.")}
                text.replaceSubrange(r,with:Money.editable(amount*factor))
            }
        }
        var date=now
        for (word,days) in [("позавчера",-2),("вчера",-1),("сегодня",0)] where text.contains(word) {date=Calendar.current.date(byAdding:.day,value:days,to:now)!;text=text.replacingOccurrences(of:word,with:"");break}
        let dateRE=try NSRegularExpression(pattern:"\\b\\d{4}-\\d{2}-\\d{2}\\b")
        let dates=dateRE.matches(in:text,range:NSRange(text.startIndex...,in:text))
        guard dates.count<=1 else{throw InputError("Укажите одну дату покупки.")}
        if let match=dates.first, let range=Range(match.range,in:text) {
            let value=String(text[range]);let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
            guard let found=formatter.date(from:value),formatter.string(from:found)==value else{throw InputError("Проверьте дату покупки.")}
            date=found;text.removeSubrange(range)
        }
        let alternatives=(Array(words.keys)+["тысяча","тысячи","тысяч","миллион","миллиона","миллионов"]).joined(separator:"|")
        let wordRE=try NSRegularExpression(pattern:"\\b(?:\(alternatives))(?:\\s+(?:\(alternatives)))*\\b")
        for match in wordRE.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            guard let range=Range(match.range,in:text) else{continue};var total:Int64=0;var group:Int64=0
            for word in text[range].split(whereSeparator:{$0.isWhitespace}).map(String.init){if word.hasPrefix("миллион"){total += max(group,1)*1_000_000;group=0}else if word.hasPrefix("тысяч"){total += max(group,1)*1000;group=0}else{group += words[word] ?? 0}}
            text.replaceSubrange(range,with:String(total+group))
        }
        text=text.replacingOccurrences(of:"(?<=\\d)[ \\u00a0](?=\\d{3}(?:\\D|$))",with:"",options:.regularExpression)
        let re=try NSRegularExpression(pattern:"(?<!\\w)-?\\d+(?:[.,]\\d{1,2})?(?!\\w)")
        let matches=re.matches(in:text,range:NSRange(text.startIndex...,in:text))
        guard matches.count==1, let match=matches.first, let range=Range(match.range,in:text) else{throw InputError("Отправьте одну покупку и одну сумму. Несколько покупок — с новой строки.")}
        let cents=try Money.parse(String(text[range]));text.removeSubrange(range)
        text=text.replacingOccurrences(of:"\\b(?:рублей|рубля|рубль|руб|р|купил|купила|потратил|потратила|за|на)\\b\\.?|₽",with:"",options:.regularExpression)
        text=text.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:CharacterSet(charactersIn:" +.,;!:=—–-\n"))
        let category=ExpenseCategory.allCases.first{cat in (keywords[cat] ?? []).contains{ text.contains($0) }} ?? .other
        var draft=ExpenseDraft();draft.title=text;draft.amount=Money.editable(cents);draft.date=date;draft.category = type.0 == .income ? type.1 : (type.0 == .transfer ? .transfer : category)
        if type.0 == .transfer {draft.title="Перевод между счетами"}
        draft.kind=type.0;draft.accountID=accountMatch.0;draft.targetAccountID=accountMatch.1
        
        if draft.category == .other || draft.category == .otherIncome { draft.note="Категорию не удалось определить точно. Выберите её перед сохранением." }
        if original.contains("долг") || original.contains("кредит") { throw InputError("Долг или кредит нельзя автоматически считать доходом. Уточните операцию и внесите её вручную с нужным видом учёта.") }
        _=try draft.expense();return draft
    }
    static func classify(_ text:String) -> (TransactionKind,ExpenseCategory) {
        if text.contains("доход") && text.contains("аренд") {return (.income,.rent)}
        if text.contains("получил перевод") || text.contains("поступил перевод") {return (.income,.otherIncome)}
        if text.range(of:"перев[её]л|перевести|перевод|отложил|(?:с карты|из наличных).*?(?:на|в) (?:накоплен|копилк|наличн)|в накопления|в копилку",options:.regularExpression) != nil { return (.transfer,.transfer) }
        if text.contains("возврат") || text.contains("вернули") { return (.refund,.other) }
        if text.range(of:"купил|купила|потрат|заплат|оплат|расход",options:.regularExpression) != nil {return (.expense,.other)}
        let rules:[(ExpenseCategory,[String])] = [(.salary,["зарплат","зп","аванс","премия"]),(.freelance,["подработ","фриланс","гонорар"]),(.business,["выручк","продал","продала","продаж","бизнес"]),(.investments,["дивиденд","процент по вкладу","проценты по вкладу","купон"]),(.gifts,["подарили","подарок получил"]),(.rent,["сдачи","сдал квартир","сдача","арендатор"]),(.cashback,["кешбэк","кэшбэк","кешбек"])]
        for (category,words) in rules where words.contains(where:{text.contains($0)}) { return (.income,category) }
        if text.range(of:"доход|получил|заработал|поступил|начислил",options:.regularExpression) != nil { return (.income,.otherIncome) }
        return (.expense,.other)
    }
    static func detectAccounts(_ text:String, accounts:[Account], transfer:Bool) -> (String,String,String) {
        var matches:[(Int,String,NSRange)] = []
        var aliases = accounts.map { ($0.id, NSRegularExpression.escapedPattern(for:$0.name.lowercased())) }
        if accounts.contains(where:{$0.id == "card"}) { aliases.append(("card","карт[аыуеой]+")) }
        if accounts.contains(where:{$0.id == "cash"}) { aliases.append(("cash","наличн[а-я]+|наличк[а-я]+")) }
        if accounts.contains(where:{$0.id == "savings"}) { aliases.append(("savings","накоплен[а-я]+|копилк[а-я]+")) }
        for (id,pattern) in aliases {
            if let re=try? NSRegularExpression(pattern:"(?<![а-яa-z])(?:"+pattern+")(?![а-яa-z])") {
                for match in re.matches(in:text,range:NSRange(text.startIndex...,in:text)) { matches.append((match.range.location,id,match.range)) }
            }
        }
        matches.sort{$0.0<$1.0}
        var seen=Set<String>();let unique=matches.filter{seen.insert($0.1).inserted}
        var clean=text
        var ranges:[NSRange]=[]
        for range in matches.map({$0.2}).sorted(by:{$0.length>$1.length}) where !ranges.contains(where:{NSIntersectionRange($0,range).length>0}) {ranges.append(range)}
        for range in ranges.sorted(by:{$0.location>$1.location}) {if let r=Range(range,in:clean){clean.removeSubrange(r)}}
        if transfer {
            let ns=text as NSString
            let source=unique.first { match in ns.substring(to:match.0).range(of:"(?:^|\\s)(?:с|со|из)\\s+$",options:.regularExpression) != nil }
            let destination=unique.first { match in ns.substring(to:match.0).range(of:"(?:^|\\s)(?:в|во|на)\\s+$",options:.regularExpression) != nil }
            if let source,let destination {return(source.1,destination.1,clean)}
            if unique.count>=2 { return(unique[0].1,unique[1].1,clean) }
            if let source {return(source.1,text.contains("отложил") ? "savings":"",clean)}
            return ("card",destination?.1 ?? unique.first?.1 ?? (text.contains("отложил") ? "savings":""),clean)
        }
        return(unique.first?.1 ?? "card","savings",clean)
    }
    static func multiple(_ input:String, accounts:[Account]=Account.defaults) throws->[ExpenseDraft] {
        guard input.count <= 12000 else { throw InputError("Сообщение слишком длинное. Разделите его на несколько частей.") }
        let text=input.replacingOccurrences(of:"(?<=[0-9а-я])\\.\\s+(?=[А-Яа-я])",with:"\n",options:.regularExpression)
            .replacingOccurrences(of:";|\\n|,(?!\\d)|\\s+и\\s+(?=[а-яА-Я])",with:"\n",options:.regularExpression)
        let lines=text.split(separator:"\n").map(String.init).filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}
        var clauses:[String]=[]
        let amountRE=try NSRegularExpression(pattern:"(?<![\\w.,-])\\d+(?:[ \\u00a0]\\d{3})*(?:[.,]\\d{1,2})?(?:\\s*(?:тыс(?:яч[аи]?)?\\.?|млн\\.?|миллион[а-я]*|к)(?=\\s|$))?(?![\\w.,-])")
        for line in lines {
            if (try? parse(line,accounts:accounts)) != nil {clauses.append(line);continue}
            let matches=amountRE.matches(in:line,range:NSRange(line.startIndex...,in:line))
            guard matches.count>1 else {clauses.append(line);continue}
            guard line.range(of:"\\b(?:штук[аи]?|шт|по|кг|литр[а-я]*)\\b",options:[.regularExpression,.caseInsensitive])==nil else {throw InputError("Укажите итоговую сумму без количества, например: кофе 600. Так мы не перепутаем количество и стоимость.")}
            let ns=line as NSString
            let prefix=ns.substring(to:matches[0].range.location).trimmingCharacters(in:.whitespacesAndNewlines)
            let amountFirst=prefix.isEmpty
            var previous=0
            for (index,match) in matches.enumerated() {
                let end = amountFirst ? (index+1<matches.count ? matches[index+1].range.location : ns.length) : NSMaxRange(match.range)
                let start = amountFirst ? match.range.location : previous
                var clause=ns.substring(with:NSRange(location:start,length:end-start))
                clause=clause.replacingOccurrences(of:"^\\s*(?:рублей|рубля|рубль|руб\\.?|₽)\\s*",with:"",options:.regularExpression)
                if !amountFirst && index==matches.count-1 {
                    clause += ns.substring(from:end)
                }
                clauses.append(clause);previous=end
            }
        }
        guard !clauses.isEmpty && clauses.count<=20 else{throw InputError("Отправьте от одной до 20 операций в одном сообщении.")}
        let lower=input.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        let sharedDate=["позавчера","вчера","сегодня"].first{lower.hasPrefix($0+" ")}
        return try clauses.map { clause in
            var value=clause
            if let sharedDate, !["сегодня","вчера","позавчера"].contains(where:{value.lowercased().contains($0)}), value.range(of:"\\d{4}-\\d{2}-\\d{2}",options:.regularExpression)==nil {value=sharedDate+" "+value}
            return try parse(value,accounts:accounts)
        }
    }
}
struct ExpenseSummary {
    let expenses:[Expense]
    var total:Int64{expenses.reduce(0){$0+$1.cents}}
    var average:Int64{expenses.isEmpty ? 0 : total/Int64(expenses.count)}
    var categories:[CategoryTotal]{ExpenseCategory.allCases.compactMap{cat in let sum=expenses.filter{$0.category==cat}.reduce(Int64(0)){$0+$1.cents};return sum>0 ? CategoryTotal(category:cat,cents:sum):nil}.sorted{$0.cents>$1.cents}}
}
struct CategoryTotal:Identifiable{var category:ExpenseCategory;var cents:Int64;var id:String{category.rawValue}}

struct FinanceSummary {
    let entries:[Expense]
    var income:Int64 { entries.filter{$0.kind == .income}.reduce(0){$0+$1.cents} }
    var grossExpenses:Int64 { entries.filter{$0.kind == .expense}.reduce(0){$0+$1.cents} }
    var refunds:Int64 { entries.filter{$0.kind == .refund}.reduce(0){$0+$1.cents} }
    var expenses:Int64 { grossExpenses-refunds }
    var profit:Int64 { income-expenses }
    var consumptionRate:Double? { income>0 ? Double(expenses)/Double(income)*100:nil }
    var savingsRate:Double? { income>0 ? Double(profit)/Double(income)*100:nil }
    func balance(for account:Account)->Int64 {
        entries.reduce(account.openingCents){value,e in
            var value=value
            if e.sourceAccount==account.id { value += (e.kind == .income || e.kind == .refund) ? e.cents : -e.cents }
            if e.kind == .transfer && e.targetAccountID==account.id { value += e.cents }
            return value
        }
    }
}
