import CarPlay
import Observation

/// The same shared playback modes as the iPhone queue, rendered in a native horizontal image row.
@MainActor
final class CarPlayPlaybackControls {
    enum Action: CaseIterable {
        case shuffle, repeatMode, endless, musicalMix
    }

    struct Snapshot: Equatable {
        let shuffled: Bool
        let repeatMode: RepeatMode
        let endless: Bool
        let localTrack: Bool
        let musicalMix: Bool

        init(container: AppContainer) {
            shuffled = container.playerState.isShuffled
            repeatMode = container.playerState.repeatMode
            endless = container.playerState.isAutoExtendEnabled
            localTrack = container.playerState.currentTrack?.isLocalFile == true
            musicalMix = container.crossfadeSettings.musicalMixEnabled
        }
    }

    private weak var template: CPListTemplate?
    private let container: AppContainer
    let row = CPListImageRowItem(text: nil, elements: [], allowsMultipleLines: false)
    private var active = false
    private(set) var snapshot: Snapshot?

    init(template: CPListTemplate, container: AppContainer) {
        self.template = template
        self.container = container
    }

    func start() {
        guard !active else { return }
        active = true
        row.listImageRowHandler = { [weak self] _, index, completion in
            guard Action.allCases.indices.contains(index) else { completion(); return }
            Task { @MainActor in
                await self?.perform(Action.allCases[index])
                completion()
            }
        }
        refreshAndObserve()
    }

    func stop() { active = false }

    func perform(_ action: Action) async {
        guard active else { return }
        switch action {
        case .shuffle:
            await container.playerService.toggleShuffle()
        case .repeatMode:
            await container.playerService.setRepeatMode(container.playerState.repeatMode.next)
        case .endless:
            guard container.playerState.currentTrack?.isLocalFile != true else { return }
            await container.playerService.setAutoExtendEnabled(!container.playerState.isAutoExtendEnabled)
        case .musicalMix:
            container.crossfadeSettings.musicalMixEnabled.toggle()
            await container.playerService.crossfadeSettingsDidChange()
        }
        // Also update synchronously for callers that await an action.
        if active { render(Snapshot(container: container)) }
    }

    private func refreshAndObserve() {
        guard active, template != nil else { return }
        let value = withObservationTracking {
            Snapshot(container: container)
        } onChange: { [weak self] in
            Task { @MainActor in self?.refreshAndObserve() }
        }
        render(value)
    }

    private func render(_ value: Snapshot) {
        snapshot = value
        let icons = ["shuffle", value.repeatMode.systemImage, "infinity", "waveform.path"]
        let selected = [value.shuffled, value.repeatMode != .off, value.endless && !value.localTrack, value.musicalMix]
        let titles = [
            [value.shuffled ? String(localized: "Shuffle On") : String(localized: "Shuffle Off")],
            [String(localized: "Repeat")],
            [String(localized: "Auto-extend with Smart Shuffle"), String(localized: "Endless")],
            [value.musicalMix ? String(localized: "Musical Mix On") : String(localized: "Musical Mix Off")]
        ]
        row.elements = Action.allCases.enumerated().map { index, _ in
            let element = CPListImageRowItemRowElement(
                image: Self.image(icons[index], active: selected[index]),
                title: titles[index].last, subtitle: nil)
            element.isEnabled = index != 2 || !value.localTrack
            if #available(iOS 26.4, *) { element.accessibilityLabel = titles[index].first }
            return element
        }
    }

    private static func image(_ symbol: String, active: Bool) -> UIImage {
        let size = CGSize(width: 100, height: 100)
        return UIGraphicsImageRenderer(size: size).image { _ in
            (active ? UIColor.systemRed : UIColor.darkGray).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 25, width: 100, height: 50), cornerRadius: 25).fill()
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 33, y: 33, width: 34, height: 34))
        }
    }
}
