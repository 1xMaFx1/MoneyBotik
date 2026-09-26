import Foundation
@main struct CoreChecks {
    static func main() throws {
        var checks=0
        func check(_ condition:Bool,_ name:String){guard condition else{fatalError("FAIL: \(name)")};checks+=1}
        for (text,cents) in [("кофе 250",Int64(25000)),("продукты 1 450,50",145050),("купил кофе за двести пятьдесят рублей",25000),("такси две тысячи триста рублей",230000)]{check(try ExpenseParser.parse(text).expense().cents==cents,text)}
        for text in ["кофе -1","кофе 0","кофе 20 евро","250","кофе 12.345","кофе 250 такси 400"]{do{_=try ExpenseParser.parse(text);fatalError("Must reject: \(text)")}catch{checks+=1}}
        for amount in ["NaN","Infinity","1.005","100000001"]{do{_=try Money.parse(amount);fatalError("Must reject amount")}catch{checks+=1}}
        let fixed=Date(timeIntervalSince1970:1_800_000_000)
        let yesterday=try ExpenseParser.parse("вчера такси 500",now:fixed)
        check(Calendar.current.isDate(yesterday.date,inSameDayAs:Calendar.current.date(byAdding:.day,value:-1,to:fixed)!),"yesterday")
        check(try ExpenseParser.multiple("кофе 250\nтакси 480").count==2,"multiple purchases")
        var draft=ExpenseDraft();draft.title=String(repeating:"я",count:161);draft.amount="100"
        do{_=try draft.expense();fatalError("Long title accepted")}catch{checks+=1}
        let expense=try ExpenseParser.parse("кофе 250").expense()
        let data=try JSONEncoder().encode(Archive(expenses:[expense],messages:[]));let restored=try JSONDecoder().decode(Archive.self,from:data)
        check(restored.expenses==[expense],"archive round trip")
        check(ExpenseSummary(expenses:[expense,expense]).total==50000,"exact totals")
        check(ExpenseSummary(expenses:[]).average==0,"empty average")
        check(ExpenseSummary(expenses:[expense]).categories.first?.category == .food,"category")
        print("PASS: \(checks) core checks")
    }
}
