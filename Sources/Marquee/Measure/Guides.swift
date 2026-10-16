/// A guide line across a frozen display, positioned in snapshot pixels.
///
/// `position` is a boundary between pixels: for a vertical guide, the x of the left edge of
/// pixel column `position`; for a horizontal guide, the y (from the top) of the top edge of
/// pixel row `position`. So a guide at 0 sits on the screen's left or top edge.
struct Guide: Equatable, Identifiable {
    enum Axis: Equatable { case vertical, horizontal }

    let id: Int
    var axis: Axis
    var position: Int
}

/// The space between two neighbouring guides on the same axis, in pixels.
struct GuideGap: Equatable {
    var start: Int
    var end: Int
    var length: Int { end - start }
}

/// The guides on one display: adding, selecting, moving, nudging, and the gaps between them.
/// Pure value logic, so it's unit tested.
struct GuideSet {
    let width: Int
    let height: Int
    private(set) var guides: [Guide] = []
    private(set) var selectedID: Int?
    private var nextID = 1

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var selected: Guide? { guides.first { $0.id == selectedID } }
    var isEmpty: Bool { guides.isEmpty }

    /// Adds a guide and selects it.
    @discardableResult
    mutating func add(_ axis: Guide.Axis, at position: Int) -> Guide {
        let guide = Guide(id: nextID, axis: axis, position: clamp(position, axis))
        nextID += 1
        guides.append(guide)
        selectedID = guide.id
        return guide
    }

    mutating func select(_ id: Int?) {
        selectedID = id.flatMap { id in guides.contains { $0.id == id } ? id : nil }
    }

    /// Selects the guide after the current one (in the order they were added), wrapping around.
    mutating func selectNext() {
        guard !guides.isEmpty else { return }
        let index = guides.firstIndex { $0.id == selectedID }.map { ($0 + 1) % guides.count } ?? 0
        selectedID = guides[index].id
    }

    mutating func move(_ id: Int, to position: Int) {
        guard let index = guides.firstIndex(where: { $0.id == id }) else { return }
        guides[index].position = clamp(position, guides[index].axis)
    }

    /// Moves the selected guide by `delta` pixels. Returns false when nothing is selected.
    @discardableResult
    mutating func nudgeSelected(by delta: Int) -> Bool {
        guard let selected else { return false }
        move(selected.id, to: selected.position + delta)
        return true
    }

    /// Removes the selected guide. Returns false when nothing is selected.
    @discardableResult
    mutating func removeSelected() -> Bool {
        guard let selectedID else { return false }
        guides.removeAll { $0.id == selectedID }
        self.selectedID = nil
        return true
    }

    /// The guide closest to the pixel (x, y), if one is within `distance` pixels.
    func hit(x: Int, y: Int, within distance: Int) -> Guide? {
        guides
            .map { guide in (guide, abs((guide.axis == .vertical ? x : y) - guide.position)) }
            .filter { $0.1 <= distance }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Gaps between neighbouring guides on one axis, left to right or top to bottom.
    /// Guides at the same position make no gap.
    func gaps(_ axis: Guide.Axis) -> [GuideGap] {
        let positions = Array(Set(guides.filter { $0.axis == axis }.map(\.position))).sorted()
        return zip(positions, positions.dropFirst()).map { GuideGap(start: $0, end: $1) }
    }

    private func clamp(_ position: Int, _ axis: Guide.Axis) -> Int {
        min(max(0, position), axis == .vertical ? width : height)
    }
}

extension EdgeFinder {
    /// Moves a guide onto the nearest edge around the pointer when one is within `within` pixels.
    ///
    /// Edges come from the same walk as the hover distances: for a vertical guide, the left and
    /// right boundaries of the same-colored run through the pointer's row; for a horizontal guide,
    /// the top and bottom boundaries of the run through its column.
    static func snapGuide(_ axis: Guide.Axis, position: Int, pointerX: Int, pointerY: Int,
                          in pixels: PixelBuffer, tolerance: Int = defaultTolerance, within: Int) -> Int {
        let d = distances(in: pixels, x: pointerX, y: pointerY, tolerance: tolerance)
        let x = min(max(0, pointerX), pixels.width - 1)
        let y = min(max(0, pointerY), pixels.height - 1)
        let candidates = axis == .vertical
            ? [x - d.left, x + d.right + 1]
            : [y - d.up, y + d.down + 1]
        guard let nearest = candidates.min(by: { abs($0 - position) < abs($1 - position) }),
              abs(nearest - position) <= within else { return position }
        return nearest
    }
}
