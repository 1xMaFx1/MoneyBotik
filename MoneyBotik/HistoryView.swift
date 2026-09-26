import SwiftUI

struct HistoryView:View{
    @EnvironmentObject var store:ExpenseStore
    @State private var search=""
    @State private var kind:TransactionKind?
    @State private var category:ExpenseCategory?
    @State private var draft:ExpenseDraft?
    @State private var deleted:Expense?
    @State private var error:String?
    private var rows:[Expense]{store.active.filter{(kind==nil || $0.kind==kind) && (category==nil || $0.category==category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.rawValue.localizedCaseInsensitiveContains(search))}}
    var body:some View{NavigationStack{List{
        Section{Picker("Вид",selection:$kind){Text("Все операции").tag(TransactionKind?.none);ForEach(TransactionKind.allCases){Text($0.rawValue).tag(Optional($0))}};Picker("Категория",selection:$category){Text("Все категории").tag(ExpenseCategory?.none);ForEach(ExpenseCategory.allCases){Text($0.rawValue).tag(Optional($0))}};LabeledContent("Доходы",value:Money.format(FinanceSummary(entries:rows).income));LabeledContent("Расходы − возвраты",value:Money.format(FinanceSummary(entries:rows).expenses));Text("Операций: \(rows.count)").foregroundStyle(.secondary)}
        if rows.isEmpty{EmptyExpenses().listRowBackground(Color.clear)}
        ForEach(rows){e in Button{draft=ExpenseDraft(expense:e)}label:{ExpenseRow(expense:e).foregroundStyle(.primary)}.swipeActions{Button(role:.destructive){do{try store.delete(e);deleted=e}catch{self.error=error.localizedDescription}}label:{Label("Удалить",systemImage:"trash")}}}
        }
        .searchable(text:$search,prompt:"Найти операцию").navigationTitle("История").toolbar{ToolbarItem(placement:.topBarTrailing){Button{draft=ExpenseDraft()}label:{Image(systemName:"plus")}.accessibilityLabel("Добавить операцию")}}
        .safeAreaInset(edge:.bottom){if let deleted{HStack{Text("Операция удалена");Spacer();Button("Отменить"){do{try store.restore(deleted);self.deleted=nil}catch{self.error=error.localizedDescription}}}.font(.subheadline).padding().background(.regularMaterial)}}
        .sheet(item:$draft){ExpenseEditor(draft:$0)}.alert("Не удалось выполнить действие",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("Понятно",role:.cancel){}}message:{Text(error ?? "")}
    }}
}
