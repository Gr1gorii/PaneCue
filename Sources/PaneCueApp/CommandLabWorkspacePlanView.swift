import PaneCueCore
import SwiftUI

struct CommandLabPlanCanvas: View {
    @Binding var plan: WorkspacePlan
    let resolution: ArrangementTargetResolutionSet?
    let onCommit: (WorkspacePlan) -> Void

    @State private var gestureStartPlan: WorkspacePlan?
    @State private var gestureWindowID: UUID?

    private let colors: [Color] = [
        .indigo,
        .cyan,
        .orange,
        .pink,
        .green,
        .purple,
        .mint,
        .blue
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.18))

                detailedGrid

                ForEach(
                    Array(plan.windows.enumerated()),
                    id: \.element.id
                ) { index, window in
                    windowView(
                        window,
                        index: index,
                        canvasSize: geometry.size
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.13))
            }
        }
    }

    private var detailedGrid: some View {
        Canvas { context, size in
            for column in 1..<ScenarioGridResolution.columns {
                var path = Path()
                let x = size.width * CGFloat(column)
                    / CGFloat(ScenarioGridResolution.columns)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(
                        Color.white.opacity(
                            column.isMultiple(
                                of: ScenarioGridResolution
                                    .majorLineInterval
                            ) ? 0.1 : 0.045
                        )
                    ),
                    lineWidth: 1
                )
            }
            for row in 1..<ScenarioGridResolution.rows {
                var path = Path()
                let y = size.height * CGFloat(row)
                    / CGFloat(ScenarioGridResolution.rows)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(
                        Color.white.opacity(
                            row.isMultiple(
                                of: ScenarioGridResolution
                                    .majorLineInterval
                            ) ? 0.1 : 0.045
                        )
                    ),
                    lineWidth: 1
                )
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func windowView(
        _ window: ScenarioWindowSlot,
        index: Int,
        canvasSize: CGSize
    ) -> some View {
        let rect = window.gridRect
        let width = max(canvasSize.width * rect.width, 32)
        let height = max(canvasSize.height * rect.height, 28)
        let isSelected = plan.selectedWindowID == window.id
        let targetState = resolution?[window.id]?.state
        let needsSelection = isAmbiguous(targetState)
        let userSelection = selectedTarget(targetState)

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    colors[index % colors.count].opacity(
                        isSelected ? 0.68 : 0.42
                    )
                )
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    needsSelection
                        ? Color.orange
                        : (
                            userSelection == nil
                                ? (
                                    isSelected
                                        ? Color.white.opacity(0.9)
                                        : Color.white.opacity(0.2)
                                )
                                : Color.green
                        ),
                    lineWidth: needsSelection || userSelection != nil
                        ? 2
                        : (isSelected ? 2 : 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .frame(width: 21, height: 21)
                        .background(.white.opacity(0.18), in: Circle())
                    Text(window.target.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                if height > 62 {
                    Text(
                        "\(Int((rect.width * 100).rounded())) × \(Int((rect.height * 100).rounded()))%"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                }
                if needsSelection, height > 88 {
                    Label(
                        "Needs selection",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                } else if let userSelection, height > 88 {
                    Label(
                        userSelection.localizedApplicationName,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )

            if isSelected {
                ForEach(
                    ScenarioGridResizeHandle.allCases,
                    id: \.self
                ) { handle in
                    resizeHandle(
                        handle,
                        windowID: window.id,
                        windowSize: CGSize(
                            width: width,
                            height: height
                        ),
                        canvasSize: canvasSize
                    )
                }
            }
        }
        .frame(width: width, height: height)
        .position(
            x: canvasSize.width
                * (rect.x + rect.width / 2),
            y: canvasSize.height
                * (rect.y + rect.height / 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            plan.selectedWindowID = window.id
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    beginGesture(for: window.id)
                    guard let start = gestureStartPlan,
                          let startWindow = start.windows.first(
                              where: { $0.id == window.id }
                          ),
                          let planIndex = plan.windows.firstIndex(
                              where: { $0.id == window.id }
                          ) else {
                        return
                    }
                    plan.selectedWindowID = window.id
                    plan.windows[planIndex].gridRect =
                        ScenarioGridInteraction.movedRect(
                            from: startWindow.gridRect,
                            translation: value.translation,
                            canvasSize: canvasSize
                        )
                }
                .onEnded { _ in
                    finishMove(for: window.id)
                }
        )
        .zIndex(isSelected ? 10 : Double(index))
    }

    private func resizeHandle(
        _ handle: ScenarioGridResizeHandle,
        windowID: UUID,
        windowSize: CGSize,
        canvasSize: CGSize
    ) -> some View {
        let point = handlePoint(handle, in: windowSize)
        return Circle()
            .fill(Color.white)
            .overlay {
                Circle().stroke(Color.indigo, lineWidth: 1.5)
            }
            .frame(width: 12, height: 12)
            .contentShape(Rectangle().size(width: 22, height: 22))
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        beginGesture(for: windowID)
                        guard let start = gestureStartPlan,
                              let startWindow = start.windows.first(
                                  where: { $0.id == windowID }
                              ),
                              let index = plan.windows.firstIndex(
                                  where: { $0.id == windowID }
                              ) else {
                            return
                        }
                        plan.windows[index].gridRect =
                            ScenarioGridInteraction.resizedRect(
                                from: startWindow.gridRect,
                                handle: handle,
                                translation: value.translation,
                                canvasSize: canvasSize
                            )
                    }
                    .onEnded { _ in
                        finishResize(
                            for: windowID,
                            handle: handle
                        )
                    }
            )
    }

    private func beginGesture(for windowID: UUID) {
        guard gestureStartPlan == nil
                || gestureWindowID != windowID else {
            return
        }
        gestureStartPlan = plan
        gestureWindowID = windowID
    }

    private func finishMove(for windowID: UUID) {
        guard let previous = gestureStartPlan,
              let index = plan.windows.firstIndex(where: {
                  $0.id == windowID
              }) else {
            clearGesture()
            return
        }
        plan.windows[index].gridRect =
            ScenarioGridInteraction.snappedMovedRect(
                plan.windows[index].gridRect
            )
        plan.revision += 1
        clearGesture()
        if previous != plan {
            onCommit(previous)
        }
    }

    private func finishResize(
        for windowID: UUID,
        handle: ScenarioGridResizeHandle
    ) {
        guard let previous = gestureStartPlan,
              let index = plan.windows.firstIndex(where: {
                  $0.id == windowID
              }) else {
            clearGesture()
            return
        }
        plan.windows[index].gridRect =
            ScenarioGridInteraction.snappedResizedRect(
                plan.windows[index].gridRect,
                handle: handle
            )
        plan.revision += 1
        clearGesture()
        if previous != plan {
            onCommit(previous)
        }
    }

    private func clearGesture() {
        gestureStartPlan = nil
        gestureWindowID = nil
    }

    private func isAmbiguous(
        _ state: ArrangementTargetResolutionState?
    ) -> Bool {
        guard let state else {
            return false
        }
        if case .ambiguous = state {
            return true
        }
        return false
    }

    private func selectedTarget(
        _ state: ArrangementTargetResolutionState?
    ) -> ResolvedArrangementTarget? {
        guard case let .resolved(target) = state,
              target.matchReason == .selectedByUser else {
            return nil
        }
        return target
    }

    private func handlePoint(
        _ handle: ScenarioGridResizeHandle,
        in size: CGSize
    ) -> CGPoint {
        switch handle {
        case .topLeading:
            return CGPoint(x: 6, y: 6)
        case .top:
            return CGPoint(x: size.width / 2, y: 6)
        case .topTrailing:
            return CGPoint(x: size.width - 6, y: 6)
        case .trailing:
            return CGPoint(
                x: size.width - 6,
                y: size.height / 2
            )
        case .bottomTrailing:
            return CGPoint(
                x: size.width - 6,
                y: size.height - 6
            )
        case .bottom:
            return CGPoint(
                x: size.width / 2,
                y: size.height - 6
            )
        case .bottomLeading:
            return CGPoint(x: 6, y: size.height - 6)
        case .leading:
            return CGPoint(x: 6, y: size.height / 2)
        }
    }
}

struct CommandLabPlanInspector: View {
    @Binding var plan: WorkspacePlan
    let applications: [InstalledApplication]
    let canUndo: Bool
    let onBeginChange: (WorkspacePlan) -> Void
    let onUndo: () -> Void
    let onSaveCorrection: () -> Void
    let onSaveScenario: (String) throws -> Void
    let onMarkNoAction: () -> Void

    @State private var addTargetKey = "role:browser"
    @State private var scenarioName = ""
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Draft inspector")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(plan.windows.count) of 8 windows")
                        .font(.headline)
                }
                Spacer()
                Button {
                    onUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Undo last draft change")
                .disabled(!canUndo)
            }

            windowList

            Divider()

            if selectedIndex != nil {
                selectedControls
            }

            Divider()

            addWindowControls
            saveControls

            HStack(spacing: 8) {
                Button {
                    onSaveCorrection()
                } label: {
                    Label("Teach", systemImage: "brain.head.profile")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onMarkNoAction()
                } label: {
                    Image(systemName: "hand.raised")
                }
                .buttonStyle(.bordered)
                .help("This command should do nothing")
            }
        }
        .padding(16)
        .frame(minHeight: 430, alignment: .top)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var windowList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(
                    Array(plan.windows.enumerated()),
                    id: \.element.id
                ) { index, window in
                    Button {
                        plan.selectedWindowID = window.id
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .frame(width: 21, height: 21)
                                .background(
                                    Color.indigo.opacity(0.16),
                                    in: Circle()
                                )
                            Text(window.target.displayName)
                                .lineLimit(1)
                            Spacer()
                            if plan.selectedWindowID == window.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.indigo)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: 126)
    }

    private var selectedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Selected", selection: selectedTargetKey) {
                ForEach(targetOptions) { option in
                    Text(option.title).tag(option.key)
                }
            }
            .id(plan.selectedWindowID)

            HStack(spacing: 7) {
                actionButton("arrow.down.right.and.arrow.up.left") {
                    followUp("поменяй окна местами")
                }
                .help("Swap with another window")
                actionButton("minus.magnifyingglass") {
                    followUp("сделай его чуть меньше")
                }
                .help("Make smaller")
                actionButton("plus.magnifyingglass") {
                    followUp("сделай его чуть больше")
                }
                .help("Make larger")
                actionButton("trash") {
                    removeSelected()
                }
                .help("Remove from draft")
                .disabled(plan.windows.count <= 1)
            }

            HStack(spacing: 7) {
                zoneButton("arrow.left", phrase: "поставь его слева")
                zoneButton("arrow.right", phrase: "поставь его справа")
                zoneButton("arrow.up", phrase: "поставь его сверху")
                zoneButton("arrow.down", phrase: "поставь его снизу")
            }
        }
    }

    private var addWindowControls: some View {
        HStack(spacing: 8) {
            Picker("Add", selection: $addTargetKey) {
                ForEach(targetOptions) { option in
                    Text(option.title).tag(option.key)
                }
            }
            .labelsHidden()

            Button {
                addWindow()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.windows.count >= 8)
            .help("Add window")
        }
    }

    private var saveControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("Scenario name", text: $scenarioName)
                Button("Save") {
                    do {
                        try onSaveScenario(scenarioName)
                        saveError = nil
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .disabled(
                    scenarioName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || plan.windows.count < 2
                )
            }
            if let saveError {
                Text(saveError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func actionButton(
        _ image: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func zoneButton(
        _ image: String,
        phrase: String
    ) -> some View {
        Button {
            followUp(phrase)
        } label: {
            Image(systemName: image)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var selectedIndex: Int? {
        plan.selectedWindowIndex
    }

    private var selectedTargetKey: Binding<String> {
        Binding(
            get: {
                guard let selectedIndex else {
                    return targetOptions.first?.key ?? "role:other"
                }
                return key(for: plan.windows[selectedIndex].target)
            },
            set: { newValue in
                guard let selectedIndex,
                      let option = targetOptions.first(where: {
                          $0.key == newValue
                      }) else {
                    return
                }
                let previous = plan
                plan.windows[selectedIndex].target = option.target
                plan.revision += 1
                onBeginChange(previous)
            }
        )
    }

    private var targetOptions: [CommandLabPlanTargetOption] {
        let roles = ApplicationRole.allCases.map { role in
            CommandLabPlanTargetOption(
                key: "role:\(role.rawValue)",
                title: role.displayName,
                target: ScenarioWindowTarget(role: role)
            )
        }
        let apps = applications.map { application in
            CommandLabPlanTargetOption(
                key: "app:\(application.bundleIdentifier)",
                title: application.displayName,
                target: ScenarioWindowTarget(
                    application: application.scenarioApplication
                )
            )
        }
        let availableKeys = Set(
            roles.map(\.key) + apps.map(\.key)
        )
        let draftOnlyApps: [CommandLabPlanTargetOption] =
            plan.windows.compactMap {
                window -> CommandLabPlanTargetOption? in
            guard window.target.kind == .application,
                  let application = window.target.application else {
                return nil
            }
            let key = "app:\(application.bundleIdentifier)"
            guard !availableKeys.contains(key) else {
                return nil
            }
            return CommandLabPlanTargetOption(
                key: key,
                title: application.displayName,
                target: ScenarioWindowTarget(
                    application: application
                )
            )
        }
        .reduce(into: [CommandLabPlanTargetOption]()) {
            result, option in
            if !result.contains(where: { $0.key == option.key }) {
                result.append(option)
            }
        }
        return roles + draftOnlyApps + apps
    }

    private func followUp(_ phrase: String) {
        let previous = plan
        guard case let .updated(updated, _) =
            WorkspacePlanCommandInterpreter.interpret(
                phrase,
                currentPlan: plan
            ) else {
            return
        }
        plan = updated
        onBeginChange(previous)
    }

    private func addWindow() {
        guard plan.windows.count < 8,
              let option = targetOptions.first(where: {
                  $0.key == addTargetKey
              }) else {
            return
        }
        let previous = plan
        let slot = ScenarioWindowSlot(
            target: option.target,
            gridRect: ScenarioGridRect(
                x: 0.65,
                y: 0,
                width: 0.35,
                height: 1
            )
        )
        plan.windows.append(slot)
        let rects = WorkspacePlan.balancedRects(
            count: plan.windows.count
        )
        for index in plan.windows.indices {
            plan.windows[index].gridRect = rects[index]
        }
        plan.selectedWindowID = slot.id
        plan.revision += 1
        onBeginChange(previous)
    }

    private func removeSelected() {
        guard plan.windows.count > 1,
              let selectedIndex else {
            return
        }
        let previous = plan
        plan.windows.remove(at: selectedIndex)
        let rects = WorkspacePlan.balancedRects(
            count: plan.windows.count
        )
        for index in plan.windows.indices {
            plan.windows[index].gridRect = rects[index]
        }
        plan.selectedWindowID = plan.windows.last?.id
        plan.revision += 1
        onBeginChange(previous)
    }

    private func key(for target: ScenarioWindowTarget) -> String {
        switch target.kind {
        case .application:
            return "app:\(target.application?.bundleIdentifier ?? "")"
        case .role:
            return "role:\(target.role?.rawValue ?? "other")"
        }
    }
}

private struct CommandLabPlanTargetOption: Identifiable {
    let key: String
    let title: String
    let target: ScenarioWindowTarget

    var id: String {
        key
    }
}
