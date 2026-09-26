import SwiftUI
import Charts

enum ExpensePeriod:String,CaseIterable{case today="Сегодня",week="7 дней",month="Месяц",all="Всё время",custom="Свой период"}
struct DayTotal:Identifiable{var day:Date;var cents:Int64;var id:Date{day}}
struct DashboardView:View{
    @EnvironmentObject var store:ExpenseStore
    @State private var sharedReport:SharedFile?
    @State private var exportError:String?
    @State private var accountID:String?
    @State private var kind=TransactionKind.expense
    @State private var period=ExpensePeriod.month
    @State private var start=Calendar.current.startOfDay(for:Date())
    @State private var end=Date()
    @State private var category:ExpenseCategory?
    @State private var selectedAngle:Double?
    @State private var selectedDay:Date?
    @State private var monthly=false
    @State private var editor:ExpenseDraft?
    private var interval:(Date,Date){
        let cal=Calendar.current;let now=Date();let today=cal.startOfDay(for:now)
        let upper=cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:period == .custom ? end:now))!
        switch period{case .today:return(today,upper);case .week:return(cal.date(byAdding:.day,value:-6,to:today)!,upper);case .month:return(cal.date(from:cal.dateComponents([.year,.month],from:today))!,upper);case .all:return(store.active.map(\.date).min().map{cal.startOfDay(for:$0)} ?? today,max(upper,store.active.map(\.date).max().map{cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:$0))!} ?? upper));case .custom:return(min(cal.startOfDay(for:start),cal.startOfDay(for:end)),max(upper,cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:start))!))}
    }
    private var allPeriodRows:[Expense]{let bounds=interval;return store.active.filter{$0.date>=bounds.0 && $0.date<bounds.1 && $0.date<=Date() && (accountID==nil || $0.sourceAccount==accountID)}}
    private var periodRows:[Expense]{allPeriodRows.filter{$0.kind==kind}}
    private var rows:[Expense]{periodRows.filter{category==nil || $0.category==category}}
    private var summary:ExpenseSummary{ExpenseSummary(expenses:rows)}
    private var categoryTotals:[CategoryTotal]{ExpenseSummary(expenses:periodRows).categories}
    private var dayTotals:[DayTotal]{let cal=Calendar.current;let grouped=Dictionary(grouping:rows){e in monthly ? cal.date(from:cal.dateComponents([.year,.month],from:e.date))!:cal.startOfDay(for:e.date)};return grouped.map{DayTotal(day:$0.key,cents:$0.value.reduce(0){$0+$1.cents})}.sorted{$0.day<$1.day}}
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){
        Text("Ваши деньги под контролем").font(.subheadline).foregroundStyle(.secondary)
        ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(ExpensePeriod.allCases,id:\.self){p in Button(p.rawValue){period=p;selectedDay=nil}.font(.subheadline).padding(.horizontal,14).padding(.vertical,9).background(period==p ? Color.moneyGreen:Color.cardBackground,in:Capsule()).foregroundStyle(period==p ? Color.white:Color.primary)}}}
        if period == .custom{VStack{DatePicker("С",selection:$start,displayedComponents:.date);DatePicker("По",selection:$end,displayedComponents:.date)}.padding().background(Color.cardBackground,in:RoundedRectangle(cornerRadius:16))}
        Picker("Счёт для отчёта",selection:$accountID){Text("Все счета").tag(String?.none);ForEach(store.accounts){Text($0.name).tag(Optional($0.id))}}
        FinanceReport(entries:allPeriodRows)
        Button {do{let range=interval;sharedReport=SharedFile(url:try store.exportReport(allPeriodRows,period:"\(range.0.formatted(date:.abbreviated,time:.omitted)) — \(Calendar.current.date(byAdding:.day,value:-1,to:range.1)!.formatted(date:.abbreviated,time:.omitted)) · \(accountID.map(store.accountName) ?? "Все счета")"))}catch{exportError=error.localizedDescription}} label:{Label("Поделиться отчётом P&L",systemImage:"square.and.arrow.up")}
        NavigationLink {AccountsView()} label:{Label("Счета и накопления",systemImage:"building.columns").font(.headline)}
        Picker("Диаграммы",selection:$kind){Text("Расходы").tag(TransactionKind.expense);Text("Доходы").tag(TransactionKind.income)}.pickerStyle(.segmented).onChange(of:kind){_,_ in category=nil;selectedAngle=nil;selectedDay=nil}
        VStack(alignment:.leading,spacing:10){Text(kind == .income ? "Всего получено":"Расходы до возвратов").font(.subheadline).foregroundStyle(.white.opacity(0.8));Text(Money.format(summary.total)).font(.system(.largeTitle,design:.rounded,weight:.bold)).minimumScaleFactor(0.55).lineLimit(1).monospacedDigit();Text(category?.rawValue ?? "Все категории").font(.caption).foregroundStyle(.white.opacity(0.8))}.foregroundStyle(.white).frame(maxWidth:.infinity,alignment:.leading).padding(22).background(Color.moneyGreen,in:RoundedRectangle(cornerRadius:22))
        LazyVGrid(columns:[GridItem(.adaptive(minimum:145),alignment:.leading)],spacing:12){metric("Операции",value:String(rows.count));metric("Средняя сумма",value:Money.format(summary.average));metric("В среднем за день",value:Money.format(summary.total/Int64(max(1,Calendar.current.dateComponents([.day],from:interval.0,to:interval.1).day ?? 1))))}
        categoryCard
        trendCard
        if let top=summary.categories.first{Text("Больше всего — \(top.category.rawValue.lowercased()): \(Money.format(top.cents)).").font(.subheadline).foregroundStyle(.secondary)}
        HStack{Text("Операции за период").font(.title3.bold());Spacer();if category != nil{Button("Сбросить"){category=nil;selectedAngle=nil}.font(.caption)}}
        if rows.isEmpty{EmptyExpenses()}else{ForEach(rows.prefix(30)){e in Button{editor=ExpenseDraft(expense:e)}label:{ExpenseRow(expense:e).foregroundStyle(.primary)}.buttonStyle(.plain);Divider()};if rows.count>30{Text("Все операции — во вкладке «История».").font(.caption).foregroundStyle(.secondary)}}
    }.padding()}.background(Color.pageBackground).navigationTitle("MoneyBotik").toolbar{ToolbarItem(placement:.topBarTrailing){Button{editor=ExpenseDraft()}label:{Image(systemName:"plus")}.accessibilityLabel("Добавить покупку")}}.sheet(item:$editor){ExpenseEditor(draft:$0)}.sheet(item:$sharedReport){ShareSheet(url:$0.url)}.alert("Экспорт",isPresented:Binding(get:{exportError != nil},set:{if !$0{exportError=nil}})){Button("Понятно",role:.cancel){}}message:{Text(exportError ?? "")}}}
    private func metric(_ label:String,value:String)->some View{VStack(alignment:.leading,spacing:8){Text(label).font(.caption).foregroundStyle(.secondary);Text(value).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()}.frame(maxWidth:.infinity,minHeight:60,alignment:.leading).padding().background(Color.cardBackground,in:RoundedRectangle(cornerRadius:16))}
    private var categoryCard:some View{VStack(alignment:.leading,spacing:16){Text(kind == .income ? "Источники доходов":"На что уходят деньги").font(.title3.bold());Text("Нажмите на сектор или категорию").font(.caption).foregroundStyle(.secondary)
        if categoryTotals.isEmpty{Text("Диаграмма появится после первой покупки.").foregroundStyle(.secondary).padding(.vertical,30)}else{
            Chart(categoryTotals){item in SectorMark(angle:.value("Расходы",Double(item.cents)),innerRadius:.ratio(0.65),angularInset:2).foregroundStyle(item.category.color).opacity(category==nil || category==item.category ? 1:0.3).accessibilityLabel(item.category.rawValue).accessibilityValue(Money.format(item.cents))}.frame(height:210).chartLegend(.hidden).chartAngleSelection(value:$selectedAngle).onChange(of:selectedAngle){_,value in guard let value else{return};var sum:Double=0;for item in categoryTotals{sum+=Double(item.cents);if value<sum{category=item.category;break}}}
            ForEach(categoryTotals){item in Button{category=category==item.category ? nil:item.category;selectedDay=nil}label:{HStack(alignment:.firstTextBaseline){Circle().fill(item.category.color).frame(width:9,height:9);Text(item.category.rawValue).multilineTextAlignment(.leading);Spacer(minLength:8);Text(Money.format(item.cents)).fontWeight(.semibold).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)}.font(.subheadline).foregroundStyle(.primary).padding(9).background(category==item.category ? item.category.color.opacity(0.12):Color.clear,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)}
        }
    }.padding().background(Color.cardBackground,in:RoundedRectangle(cornerRadius:20))}
    private var trendCard:some View{VStack(alignment:.leading,spacing:16){Text(kind == .income ? "Динамика доходов":"Динамика расходов").font(.title3.bold());Picker("Группировка",selection:$monthly){Text("По дням").tag(false);Text("По месяцам").tag(true)}.pickerStyle(.segmented)
        if dayTotals.isEmpty{Text("Нет операций за этот период.").foregroundStyle(.secondary).padding(.vertical,30)}else{
            Chart(dayTotals){item in BarMark(x:.value("Дата",item.day,unit:monthly ? .month:.day),y:.value("Рубли",Double(item.cents)/100)).foregroundStyle(Color.moneyGreen).cornerRadius(4).accessibilityLabel(item.day.formatted(date:.abbreviated,time:.omitted)).accessibilityValue(Money.format(item.cents))}.frame(height:200).chartScrollableAxes(.horizontal).chartXVisibleDomain(length:monthly ? 180*86400:7*86400).chartXSelection(value:$selectedDay).chartYAxisLabel("₽").chartXAxis{AxisMarks(values:.stride(by:monthly ? .month:.day)){_ in AxisValueLabel(format:monthly ? .dateTime.month(.abbreviated):.dateTime.day().month(.abbreviated))}}
            if let selectedDay{let matches=rows.filter{Calendar.current.isDate($0.date,equalTo:selectedDay,toGranularity:monthly ? .month:.day)};Text("\(selectedDay.formatted(date:.abbreviated,time:.omitted)) · \(Money.format(matches.reduce(0){$0+$1.cents})) · операций: \(matches.count)").font(.subheadline);ForEach(matches.prefix(5)){ExpenseRow(expense:$0)}}else{Text("Коснитесь диаграммы, чтобы увидеть сумму. Проведите в сторону для других дат.").font(.caption).foregroundStyle(.secondary)}
        }
    }.padding().background(Color.cardBackground,in:RoundedRectangle(cornerRadius:20))}
}

struct FinanceReport:View {
    let entries:[Expense]
    @State private var selectedMetric:String?
    @State private var selectedMonth:Date?
    private let grouped:[Date:FinanceSummary]
    init(entries:[Expense]) {
        self.entries=entries
        self.grouped=Dictionary(grouping:entries){Calendar.current.date(from:Calendar.current.dateComponents([.year,.month],from:$0.date))!}.mapValues{FinanceSummary(entries:$0)}
    }
    private var months:[Date] {grouped.keys.sorted()}
    private func monthly(_ month:Date)->FinanceSummary {let key=Calendar.current.date(from:Calendar.current.dateComponents([.year,.month],from:month))!;return grouped[key] ?? FinanceSummary(entries:[])}
    private var report:FinanceSummary {FinanceSummary(entries:entries)}
    private var buckets:[(String,Int64)] {[("Доходы",report.income),("Расходы",report.expenses),("Результат",report.profit)]}
    var body:some View {VStack(alignment:.leading,spacing:16){
        Text("Доходы и расходы · P&L").font(.title2.bold())
        Text("Личный отчёт по фактическим поступлениям и платежам за выбранный период. Переводы между своими счетами исключены.").font(.caption).foregroundStyle(.secondary)
        ForEach(buckets,id:\.0){row in VStack(alignment:.leading,spacing:4){Text(row.0).font(.subheadline).foregroundStyle(.secondary);Text(Money.format(row.1)).font(.title2.bold()).monospacedDigit().fixedSize(horizontal:false,vertical:true)}}
        if report.refunds>0 {Text("Расходы уменьшены на возвраты: \(Money.format(report.refunds))").font(.caption)}
        Chart(buckets,id:\.0){row in BarMark(x:.value("Вид",row.0),y:.value("Рубли",Double(row.1)/100)).foregroundStyle(row.0 == "Расходы" ? Color.orange:Color.moneyGreen).accessibilityLabel(row.0).accessibilityValue(Money.format(row.1))}.frame(height:180).chartYAxisLabel("₽").chartXSelection(value:$selectedMetric)
        if let selectedMetric,let value=buckets.first(where:{$0.0==selectedMetric}) {Text("\(value.0): \(Money.format(value.1))").font(.headline)}
        Text("Динамика результата по месяцам").font(.headline)
        Chart(months,id:\.self){month in
            BarMark(x:.value("Месяц",month,unit:.month),y:.value("Результат, ₽",Double(monthly(month).profit)/100)).foregroundStyle(monthly(month).profit>=0 ? Color.moneyGreen:Color.orange)
        }.frame(height:160).chartXSelection(value:$selectedMonth).chartYAxisLabel("₽").chartXAxis{AxisMarks(values:.stride(by:.month)){_ in AxisValueLabel(format:.dateTime.month(.abbreviated))}}
        if let selectedMonth {let month=monthly(selectedMonth);Text("\(selectedMonth.formatted(.dateTime.month(.wide).year())): доходы \(Money.format(month.income)), расходы \(Money.format(month.expenses)), результат \(Money.format(month.profit)).").font(.subheadline)}
        Text("Эффективность потребления").font(.headline)
        if let consumption=report.consumptionRate,let saving=report.savingsRate {
            Text("На потребление: \(consumption.formatted(.number.precision(.fractionLength(1))))% доходов").fixedSize(horizontal:false,vertical:true)
            Text("Свободный остаток: \(saving.formatted(.number.precision(.fractionLength(1))))% доходов").fixedSize(horizontal:false,vertical:true)
            ProgressView(value:min(max(consumption/100,0),1)).tint(consumption>100 ? .orange:.moneyGreen)
            Text(consumption>100 ? "Расходы превышают доходы периода. Разница покрывается остатками на счетах или обязательствами." : "Свободный остаток — доходы минус расходы. Это не сумма, фактически переведённая в накопления.").font(.caption).foregroundStyle(.secondary)
        } else {Text("Добавьте доходы, чтобы рассчитать долю потребления и свободного остатка.").font(.subheadline).foregroundStyle(.secondary)}
        Text("Возвраты учитываются в день поступления. Проценты не оценивают полезность отдельных покупок.").font(.caption).foregroundStyle(.secondary)
    }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.cardBackground,in:RoundedRectangle(cornerRadius:20))}
}

struct AccountsView:View {
    @EnvironmentObject var store:ExpenseStore
    @State private var edited:Account?
    private var total:Int64 {store.accounts.reduce(0){$0+store.balances.balance(for:$1)}}
    private var savings:Int64 {store.accounts.filter(\.isSavings).reduce(0){$0+store.balances.balance(for:$1)}}
    var body:some View {List {
        Section("На текущую дату") {LabeledContent("Все счета",value:Money.format(total));LabeledContent("Накопления",value:Money.format(savings));Text("Остаток = начальная сумма + поступления − списания. Будущие операции пока не входят в остаток.").font(.caption).foregroundStyle(.secondary)}
        ForEach(store.accounts){account in
            Section {Button{edited=account}label:{VStack(alignment:.leading,spacing:10){Label(account.name,systemImage:account.isSavings ? "target":"creditcard").font(.headline);Text(Money.format(store.balances.balance(for:account))).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)
                if account.isSavings && account.goalCents>0 {ProgressView(value:min(max(Double(store.balances.balance(for:account))/Double(account.goalCents),0),1));Text("Цель: \(Money.format(account.goalCents)) · осталось \(Money.format(max(0,account.goalCents-store.balances.balance(for:account))))").font(.caption).fixedSize(horizontal:false,vertical:true)}
            }.foregroundStyle(.primary).padding(.vertical,6)}}
        }
        Section{Text("Для накоплений внесите перевод, например: «перевёл с карты в накопления 5000». Начальный остаток задаётся один раз — до первой учитываемой операции. Его изменение пересчитывает текущий баланс.").font(.subheadline)}
    }.navigationTitle("Счета и цели").toolbar{Button{edited=Account(name:"")}label:{Image(systemName:"plus")}.accessibilityLabel("Добавить счёт")}.sheet(item:$edited){AccountEditor(account:$0)}}
}
struct AccountEditor:View {
    @EnvironmentObject var store:ExpenseStore
    @Environment(\.dismiss) var dismiss
    @State var account:Account
    @State private var opening=""
    @State private var goal=""
    @State private var error:String?
    var body:some View {NavigationStack {Form {
        TextField("Название счёта",text:$account.name)
        TextField("Начальный остаток, ₽",text:$opening).keyboardType(.numbersAndPunctuation)
        Toggle("Это накопления",isOn:$account.isSavings)
        if account.isSavings {TextField("Цель, ₽ (0 — без цели)",text:$goal).keyboardType(.decimalPad)}
        Text("Остаток до начала учёта. Доходы, расходы и переводы далее изменят его автоматически. Можно указать отрицательное значение.").font(.caption).foregroundStyle(.secondary)
        if let error {Text(error).foregroundStyle(.red)}
    }.navigationTitle("Настройка счёта").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement:.cancellationAction){Button("Отмена"){dismiss()}}
        ToolbarItem(placement:.confirmationAction){Button("Сохранить"){do {
            account.name=account.name.trimmingCharacters(in:.whitespacesAndNewlines)
            account.openingCents=try Money.signedOrZero(opening)
            account.goalCents=try Money.signedOrZero(goal)
            guard account.goalCents>=0 else{throw InputError("Цель не может быть отрицательной.")}
            try store.saveAccount(account);dismiss()
        } catch{self.error=error.localizedDescription}}}
    }.onAppear {opening=Money.editable(account.openingCents);goal=Money.editable(account.goalCents)}}}
}
