import SwiftUI

// Task 7 wires the Contracts tab into MainTabView. The real `ContractsView`
// is built on a parallel branch (Task 4) that hasn't merged yet, so this
// stub provides just enough surface area for MainTabView to compile and the
// UI smoke test to exercise the tab. Delete this file when Task 4 merges.
struct ContractsView: View {
    var body: some View {
        Text("Contracts")
            .navigationTitle("Contracts")
    }
}
