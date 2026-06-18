import SwiftUI

struct SelectableTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> TextContainerView {
        TextContainerView(attributedString: attributedString)
    }

    func updateNSView(_ nsView: TextContainerView, context: Context) {
        nsView.textView.textStorage?.setAttributedString(attributedString)
        nsView.invalidateIntrinsicContentSize()
        nsView.needsLayout = true
    }
}

class TextContainerView: NSView {
    let textView: NSTextView

    init(attributedString: NSAttributedString) {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textStorage?.setAttributedString(attributedString)

        self.textView = textView
        super.init(frame: .zero)
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 0 ? bounds.width : 600
        textView.textContainer?.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let size = textView.layoutManager?.usedRect(for: textView.textContainer!).size ?? .zero
        return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
    }
}
