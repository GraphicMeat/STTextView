//  Created by Marcin Krzyzanowski
//  https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md

import AppKit

extension STTextView: NSTextLayoutManagerDelegate {

    public func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = STTextLayoutFragment(
            textElement: textElement,
            range: textElement.elementRange,
            defaultTypingAttributes: _defaultTypingAttributes
        )

        // A paragraph collapses when it lies fully inside a folded (body)
        // range. The fold's head paragraph is never fully contained by its
        // own body range, so it stays visible.
        if let elementRange = textElement.elementRange {
            fragment.isCollapsed = foldedRanges.contains { $0.contains(elementRange) }
        }

        return fragment
    }
}
