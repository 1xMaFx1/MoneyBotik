import Foundation
@main struct StoreChecks {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("MoneyBotik-tests-\(UUID())")
        defer{try? FileManager.default.removeItem(at:root)}
        let store=ExpenseStore(directory:root)
        try store.save(ExpenseParser.parse("кофе 250"))
        guard store.active.count==1 else{fatalError("Save failed")}
        let reopened=ExpenseStore(directory:root)
        guard reopened.active.first?.cents==25000 else{fatalError("Persistence failed")}
        let item=reopened.active[0]
        var edit=ExpenseDraft(expense:item);edit.amount="300.50";try reopened.save(edit)
        guard reopened.active.count==1 && reopened.active[0].cents==30050 else{fatalError("Edit failed")}
        try reopened.delete(reopened.active[0]);guard reopened.active.isEmpty else{fatalError("Delete failed")}
        try reopened.restore(item);guard reopened.active.count==1 else{fatalError("Restore failed")}
        let backup=try reopened.exportJSON();defer{try? FileManager.default.removeItem(at:backup)}
        let count=try reopened.importBackup(backup);guard count==0 else{fatalError("Duplicate import")}
        let csv=try reopened.exportCSV();defer{try? FileManager.default.removeItem(at:csv)}
        guard try String(contentsOf:csv,encoding:.utf8).contains("300.50") else{fatalError("CSV failed")}
        try Data("broken".utf8).write(to:root.appendingPathComponent("expenses.json"))
        let damaged=ExpenseStore(directory:root)
        guard damaged.error != nil else{fatalError("Corruption not detected")}
        do{try damaged.save(ExpenseParser.parse("такси 100"));fatalError("Corrupt file overwritten")}catch{}
        let restored=try damaged.importBackup(backup)
        guard restored==1 && damaged.active[0].cents==30050 else{fatalError("Backup recovery failed")}
        print("PASS: save, reopen, edit, soft delete, restore, backup, duplicate prevention, CSV, corruption protection and recovery")
    }
}
