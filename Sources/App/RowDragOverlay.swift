import AppKit
import QuartzCore

/// 拖动排序期间盖在面板上的一层，放各行的截图。
/// 真实的行由栈视图的自动布局管着，直接改 frame 会在下一次布局时被排回原位，所以拖动只动这里的图。
@MainActor
final class RowDragOverlay: NSView {
    private let tiles: [NSView]
    private let slots: [NSRect]
    private let draggedIndex: Int
    private var target: Int

    init(frame: NSRect, snapshots: [(image: NSImage, frame: NSRect)], draggedIndex: Int) {
        slots = snapshots.map(\.frame)
        self.draggedIndex = draggedIndex
        target = draggedIndex
        tiles = snapshots.map { snapshot in
            let tile = NSView(frame: snapshot.frame)
            tile.wantsLayer = true
            tile.layer?.contents = snapshot.image
            tile.layer?.contentsGravity = .resize
            return tile
        }
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = true
        wantsLayer = true
        for (index, tile) in tiles.enumerated() where index != draggedIndex {
            addSubview(tile)
        }
        addSubview(tiles[draggedIndex])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func moveDragged(toMinY minY: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tiles[draggedIndex].frame.origin.y = minY
        CATransaction.commit()
    }

    /// 让位的行移到相邻行的原位置，行距不一致时也能对齐。
    func setTarget(_ index: Int) {
        guard index != target else { return }
        target = index
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
            context.allowsImplicitAnimation = true
            for (row, tile) in tiles.enumerated() where row != draggedIndex {
                var slot = row
                if target > draggedIndex, row > draggedIndex, row <= target {
                    slot = row - 1
                } else if target < draggedIndex, row >= target, row < draggedIndex {
                    slot = row + 1
                }
                tile.animator().frame = slots[slot]
            }
        }
    }
}
