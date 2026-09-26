import Foundation
@main struct FinanceChecks {
    @MainActor static func main() throws {
        var checks=0
        func check(_ ok:Bool,_ name:String){if !ok {fatalError("FAIL: \(name)")};checks+=1}
        func parse(_ s:String)throws->Expense {try ExpenseParser.parse(s).expense()}
        for (text,kind,category,cents) in [
            ("зарплата 90000",TransactionKind.income,ExpenseCategory.salary,Int64(9_000_000)),
            ("получил аванс 25000",.income,.salary,2_500_000),
            ("подработка 5к",.income,.freelance,500_000),
            ("гонорар 2,5 тыс",.income,.freelance,250_000),
            ("продал велосипед 10000",.income,.business,1_000_000),
            ("дивиденды 1300",.income,.investments,130_000),
            ("подарили 3000",.income,.gifts,300_000),
            ("арендатор 25000",.income,.rent,2_500_000),
            ("кешбэк 450",.income,.cashback,45_000),
            ("кофе 250 с карты",.expense,.food,25_000),
            ("такси наличными 480",.expense,.transport,48_000),
            ("вернули за кофе 250",.refund,.food,25_000),
            ("перевёл с карты в накопления 5000",.transfer,.transfer,500_000),
            ("с карты в накопления 5000",.transfer,.transfer,500_000),
            ("вчера зарплата девяносто тысяч рублей",.income,.salary,9_000_000)
        ] {let e=try parse(text);check(e.kind==kind && e.category==category && e.cents==cents,text)}
        check(try parse("такси 480 наличными").sourceAccount=="cash","cash account")
        let transfer=try parse("перевёл с карты в накопления 5000")
        check(transfer.sourceAccount=="card" && transfer.targetAccountID=="savings","transfer accounts")
        check(try ExpenseParser.multiple("зарплата 90000, кофе 250, такси 480").count==3,"mixed batch")
        check(try ExpenseParser.multiple("кофе 250 и такси 480").count==2,"conjunction")
        check(try ExpenseParser.multiple("кофе 250 такси 480").count==2,"no punctuation")
        check(try ExpenseParser.multiple("кофе 250,50; такси 480,25").map{try $0.expense().cents}==[25050,48025],"decimal batch")
        check(try ExpenseParser.multiple("кофе 250. такси 480").count==2,"sentences")
        for text in ["кофе 12.345","зарплата -200","кофе 0","кредит 50000","перевёл Васе 500","вернул долг 1000","перевёл с карты на карту 500"] {
            do{_=try parse(text);fatalError("Should reject \(text)")}catch{checks+=1}
        }
        check(try ExpenseParser.multiple("булочка 100 шампунь 400").map{try $0.expense().cents}==[10000,40000],"arbitrary named items")
        check(try ExpenseParser.multiple("250 кофе 480 такси").map{try $0.expense().cents}==[25000,48000],"amount before title")
        check(try parse("перевёл в накопления с карты 5000").targetAccountID=="savings","reversed transfer wording")
        let dated=try ExpenseParser.multiple("вчера кофе 200, такси 300")
        check(Calendar.current.isDate(dated[0].date,inSameDayAs:dated[1].date),"shared date")
        do{_=try ExpenseParser.multiple("кофе 2 штуки 300");fatalError("Quantity treated as money")}catch{checks+=1}
        let entries=try [parse("зарплата 10000"),parse("кофе 1500"),parse("вернули за кофе 500"),transfer]
        let f=FinanceSummary(entries:entries)
        check(f.income==1_000_000 && f.expenses==100_000 && f.profit==900_000,"PL transfer neutrality and refund")
        check(f.consumptionRate==10 && f.savingsRate==90,"efficiency rates")
        check(f.balance(for:Account.defaults[0])==400_000,"card balance")
        check(f.balance(for:Account.defaults[2])==500_000,"savings balance")
        check(FinanceSummary(entries:[]).consumptionRate==nil,"no zero division")
        check(FinanceSummary(entries:[try parse("кофе 1500")]).profit == -150_000,"deficit")
        check(try Money.signedOrZero("-100.50") == -10050 && Money.editable(-10050)=="-100.50","negative opening balance")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("MoneyBotik-finance-\(UUID())")
        defer{try? FileManager.default.removeItem(at:root)}
        let store=ExpenseStore(directory:root)
        var card=Account.defaults[0];card.openingCents=100_000;try store.saveAccount(card)
        try store.saveBatch(ExpenseParser.multiple("зарплата 10000, кофе 1500, вернули за кофе 500, перевёл с карты в накопления 5000"))
        let reopened=ExpenseStore(directory:root)
        check(reopened.active.count==4 && reopened.accounts[0].openingCents==100_000,"persist finance and accounts")
        check(reopened.balances.balance(for:card)==500_000,"opening plus flows")
        let count=reopened.active.count
        var invalid=ExpenseDraft();invalid.title="bad";invalid.amount="0"
        do{try reopened.saveBatch([try ExpenseParser.parse("кофе 20"),invalid]);fatalError("partial save")}catch{}
        check(reopened.active.count==count,"atomic batch")
        let t=reopened.active.first{$0.kind == .transfer}!
        try reopened.delete(t);check(reopened.balances.balance(for:card)==1_000_000,"delete transfer reverses both sides")
        try reopened.restore(t);check(reopened.balances.balance(for:card)==500_000,"restore transfer")
        var edit=ExpenseDraft(expense:t);edit.amount="1000";try reopened.save(edit)
        check(reopened.balances.balance(for:card)==900_000,"edit transfer")
        let backup=try reopened.exportJSON()
        check(try reopened.importBackup(backup)==0,"idempotent backup import")
        let other=ExpenseStore(directory:root.appendingPathComponent("other"));_=try other.importBackup(backup)
        check(other.active.count==4 && other.accounts[0].openingCents==100_000 && other.balances.balance(for:card)==900_000,"import finance preserves opening balances")
        let json=try JSONSerialization.jsonObject(with:Data(contentsOf:backup)) as! [String:Any]
        check(json["accounts"] != nil,"backup accounts included")
        let legacy=Expense(title:"старый кофе",cents:25000,category:.food,date:Date())
        var archive=Archive(expenses:[legacy],messages:[]);archive.version=1
        let legacyRoot=root.appendingPathComponent("legacy");try FileManager.default.createDirectory(at:legacyRoot,withIntermediateDirectories:true)
        try JSONEncoder().encode(archive).write(to:legacyRoot.appendingPathComponent("expenses.json"))
        let migrated=ExpenseStore(directory:legacyRoot)
        check(migrated.active.first?.kind == .expense && migrated.accounts.count==3,"v1 migration")
        let reportURL=try reopened.exportReport(reopened.active,period:"Тестовый период")
        let reportText=try String(contentsOf:reportURL,encoding:.utf8)
        check(reportText.contains("Результат") && reportText.contains("9000.00"),"PL CSV exact net result")
        var changedCard=card;changedCard.openingCents=200_000;try other.saveAccount(changedCard)
        do{_=try other.importBackup(backup);fatalError("Conflicting balance accepted")}catch{checks+=1}
        var missingAccount=ExpenseDraft();missingAccount.title="missing";missingAccount.amount="1";missingAccount.accountID="unknown"
        do{try other.save(missingAccount);fatalError("Unknown account accepted")}catch{checks+=1}
        check(try parse("зарплата один миллион рублей").cents==100_000_000,"spoken million")
        check(try parse("зарплата 2 млн").cents==200_000_000,"million abbreviation")
        check(try parse("потратил на бизнес 3000").kind == .expense,"expense wording overrides income keyword")
        for n in 1...100 {
            let value=Int64(n*137)
            let incoming=Expense(title:"Income",cents:value*3,category:.salary,date:Date(),kindValue:.income,accountID:"card")
            let outgoing=Expense(title:"Expense",cents:value,category:.other,date:Date(),kindValue:.expense,accountID:"card")
            let moved=Expense(title:"Transfer",cents:value,category:.transfer,date:Date(),kindValue:.transfer,accountID:"card",targetAccountID:"savings")
            let ledger=FinanceSummary(entries:[incoming,outgoing,moved])
            check(Account.defaults.reduce(Int64(0)){$0+ledger.balance(for:$1)} == ledger.profit,"ledger conservation \(n)")
        }
        print("PASS: \(checks) finance checks")
    }
}
