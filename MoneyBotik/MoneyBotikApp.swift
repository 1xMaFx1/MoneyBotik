import SwiftUI

@main struct MoneyBotikApp:App {
    @StateObject private var store=ExpenseStore()
    var body:some Scene{WindowGroup{RootView().environmentObject(store).tint(Color.moneyGreen)}}
}
extension Color {
    static let moneyGreen=Color(red:0.09,green:0.43,blue:0.33)
    static let pageBackground=Color(uiColor:.systemGroupedBackground)
    static let cardBackground=Color(uiColor:.secondarySystemGroupedBackground)
}
extension ExpenseCategory {
    var color:Color{switch self{case .groceries:return .moneyGreen;case .food:return Color(red:0.48,green:0.68,blue:0.50);case .transport:return .orange;case .home:return .teal;case .health:return .purple;case .shopping:return .brown;case .fun:return .pink;case .other:return .gray;case .salary:return .blue;case .freelance:return .teal;case .business:return .indigo;case .investments:return .purple;case .gifts:return .pink;case .rent:return .orange;case .cashback:return .mint;case .otherIncome:return .cyan;case .transfer:return .gray}}
}
struct RootView:View{
    @EnvironmentObject var store:ExpenseStore
    @State private var selectedTab:Int = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--qa-chat") {return 1}
        if ProcessInfo.processInfo.arguments.contains("--qa-history") {return 2}
        #endif
        return 0
    }()
    @ViewBuilder private var overview:some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--qa-accounts") {NavigationStack{AccountsView()}}
        else if ProcessInfo.processInfo.arguments.contains("--qa-batch") {BatchReview(drafts:(try? ExpenseParser.multiple("зарплата 90000, кофе 250, такси 480")) ?? [])}
        else {DashboardView()}
        #else
        DashboardView()
        #endif
    }
    var body:some View{
        TabView(selection:$selectedTab){overview.tag(0).tabItem{Label("Обзор",systemImage:"chart.pie")};ChatView().tag(1).tabItem{Label("Чат",systemImage:"bubble.left.and.bubble.right")};HistoryView().tag(2).tabItem{Label("История",systemImage:"list.bullet.rectangle")};SettingsView().tag(3).tabItem{Label("Ещё",systemImage:"ellipsis.circle")}}
        .alert("Не удалось прочитать данные",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("Понятно",role:.cancel){}}message:{Text(store.error ?? "")}
    }
}
struct ExpenseEditor:View{
    @EnvironmentObject var store:ExpenseStore
    @Environment(\.dismiss) var dismiss
    @State var draft:ExpenseDraft
    var onSave:(()->Void)?=nil
    @State private var error:String?
    @State private var saving=false
    var body:some View{NavigationStack{Form{
        Section("Операция"){Picker("Вид",selection:$draft.kind){ForEach(TransactionKind.allCases){Text($0.rawValue).tag($0)}}.onChange(of:draft.kind){_,kind in draft.category=ExpenseCategory.options(for:kind).first ?? .other};TextField("Описание",text:$draft.title,axis:.vertical).lineLimit(1...4).accessibilityIdentifier("expenseTitle");TextField("Сумма в рублях",text:$draft.amount).keyboardType(.decimalPad).accessibilityIdentifier("expenseAmount")}
        Section{Picker("Категория",selection:$draft.category){ForEach(ExpenseCategory.options(for:draft.kind)){Text($0.rawValue).tag($0)}};DatePicker("Дата",selection:$draft.date,displayedComponents:.date)}
        Section("Счета"){Picker(draft.kind == .transfer ? "Откуда":"Счёт",selection:$draft.accountID){ForEach(store.accounts){Text($0.name).tag($0.id)}};if draft.kind == .transfer {Picker("Куда",selection:$draft.targetAccountID){ForEach(store.accounts){Text($0.name).tag($0.id)}}}}
        if let note=draft.note {Section{Text(note).foregroundStyle(.orange)}}
        Section{Text("Проверьте сумму и категорию перед сохранением.").foregroundStyle(.secondary)}
        if let error{Section{Text(error).foregroundStyle(.red)}}
    }.navigationTitle(draft.expenseID==nil ? "Новая операция":"Изменить операцию").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Отмена"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Сохранить"){saving=true;do{try store.save(draft);dismiss();onSave?()}catch{self.error=error.localizedDescription;saving=false}}.disabled(saving).fontWeight(.semibold).accessibilityIdentifier("saveExpense")}}}}
}
struct ExpenseRow:View{
    @EnvironmentObject var store:ExpenseStore
    let expense:Expense
    var body:some View{HStack(alignment:.top,spacing:12){Image(systemName:expense.category.symbol).foregroundStyle(expense.category.color).frame(width:36,height:36).background(expense.category.color.opacity(0.12),in:RoundedRectangle(cornerRadius:10));VStack(alignment:.leading,spacing:5){Text(expense.title).font(.body.weight(.medium)).fixedSize(horizontal:false,vertical:true);Text("\(expense.category.rawValue) · \(expense.date.formatted(date:.abbreviated,time:.omitted))").font(.caption).foregroundStyle(.secondary);Text("\(expense.kind.rawValue) · \(Money.format(expense.cents))").font(.subheadline.weight(.semibold)).monospacedDigit();Text(store.accountName(expense.sourceAccount) + (expense.targetAccountID.map{" → " + store.accountName($0)} ?? "")).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}.padding(.vertical,5)}
}
struct EmptyExpenses:View{var body:some View{ContentUnavailableView("Пока нет операций",systemImage:"basket",description:Text("Напишите в чате «кофе 250» или добавьте операцию вручную."))}}
