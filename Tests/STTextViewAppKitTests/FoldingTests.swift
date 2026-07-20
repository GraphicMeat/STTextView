//  Created for MeatPad code folding.
//
//  DECISION (Task 1 spike): Mechanism A (zero-height `layoutFragmentFrame`
//  override on an NSTextLayoutFragment subclass, installed via
//  NSTextLayoutManagerDelegate) WORKS. Measured: with lines 2-4 collapsed,
//  paragraph 5's fragment y-origin lands exactly where paragraph 2's y-origin
//  sits in the uncollapsed baseline layout (subsequent fragments moved up),
//  and usageBoundsForTextContainer.height shrinks by exactly the height of
//  the three collapsed line fragments. NSTextContentStorage's underlying
//  NSTextStorage is never mutated. See testMechanismA_CollapsedFragmentsHideAndStackingMoves
//  and testMechanismA_DocumentStorageIsNeverMutated below for the evidence
//  (kept as a regression guard on the raw mechanism).
//
//  Task 2 turns mechanism A into production API: STTextView.foldedRanges +
//  STTextLayoutFragment.isCollapsed, wired through the
//  NSTextLayoutManagerDelegate. The STTextView-level tests below
//  (testFold*, testUnfold*, testIsRangeFolded*) exercise that public API,
//  both freshly-set-then-laid-out and dynamically toggled after an initial
//  layout already happened (foldedRanges' didSet invalidates layout for
//  documentRange, which forces the delegate to be re-consulted).

#if os(macOS)
    import AppKit
    import XCTest
    @testable import STTextViewAppKit

    final class FoldingTests: XCTestCase {

        /// Fragment subclass that reports zero height while leaving the
        /// underlying line fragments (and therefore the text) intact.
        final class CollapsedFragment: NSTextLayoutFragment {
            override var layoutFragmentFrame: CGRect {
                var frame = super.layoutFragmentFrame
                frame.size.height = 0
                return frame
            }
        }

        final class Delegate: NSObject, NSTextLayoutManagerDelegate {
            var collapse: (NSTextRange) -> Bool = { _ in false }

            func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
                if let range = textElement.elementRange, collapse(range) {
                    return CollapsedFragment(textElement: textElement, range: range)
                }
                return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
            }
        }

        private let documentText = "l1\nl2\nl3\nl4\nl5\nl6\n"

        /// Builds an independent NSTextContentStorage -> NSTextLayoutManager -> NSTextContainer
        /// stack (mirrors what STTextView assembles) and lays out fully.
        /// `collapsedLines` names the paragraph text ("l2", "l3", ...) whose
        /// fragment should report zero height.
        private func makeStack(collapsedLines: Set<String>) -> (contentStorage: NSTextContentStorage, layoutManager: NSTextLayoutManager, delegate: Delegate) {
            let contentStorage = NSTextContentStorage()
            contentStorage.textStorage = NSTextStorage(string: documentText)

            let layoutManager = NSTextLayoutManager()
            let textContainer = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
            layoutManager.textContainer = textContainer
            contentStorage.addTextLayoutManager(layoutManager)

            let delegate = Delegate()
            delegate.collapse = { [contentStorage] range in
                let nsRange = NSRange(range, in: contentStorage)
                let paragraphText = (contentStorage.textStorage!.string as NSString)
                    .substring(with: nsRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return collapsedLines.contains(paragraphText)
            }
            layoutManager.delegate = delegate

            layoutManager.ensureLayout(for: layoutManager.documentRange)

            return (contentStorage, layoutManager, delegate)
        }

        private func fragmentFrames(_ layoutManager: NSTextLayoutManager) -> [CGRect] {
            var frames: [CGRect] = []
            layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                frames.append(fragment.layoutFragmentFrame)
                return true
            }
            return frames
        }

        @MainActor
        func testMechanismA_CollapsedFragmentsHideAndStackingMoves() {
            // Baseline: nothing collapsed.
            let baseline = makeStack(collapsedLines: [])
            let baselineFrames = fragmentFrames(baseline.layoutManager)
            XCTAssertEqual(baselineFrames.count, 6, "expected one fragment per line (l1...l6)")

            let baselineParagraph2Y = baselineFrames[1].origin.y // "l2"

            // Collapse paragraphs 2-4 ("l2", "l3", "l4").
            let collapsed = makeStack(collapsedLines: ["l2", "l3", "l4"])
            let collapsedFrames = fragmentFrames(collapsed.layoutManager)
            XCTAssertEqual(collapsedFrames.count, 6, "fragments still exist for every paragraph, just zero-height")

            // The collapsed fragments themselves report zero height.
            XCTAssertEqual(collapsedFrames[1].size.height, 0, accuracy: 0.001)
            XCTAssertEqual(collapsedFrames[2].size.height, 0, accuracy: 0.001)
            XCTAssertEqual(collapsedFrames[3].size.height, 0, accuracy: 0.001)

            // The key assertion: paragraph 5 ("l5") moved up to occupy the
            // slot paragraph 2 used to have in the uncollapsed baseline --
            // i.e. NSTextLayoutManager positioned it using our overridden
            // zero-height frame, not some internal cached line-height metric.
            let collapsedParagraph5Y = collapsedFrames[4].origin.y
            XCTAssertEqual(collapsedParagraph5Y, baselineParagraph2Y, accuracy: 0.001)

            // usageBoundsForTextContainer shrank by exactly the height that
            // the three collapsed line fragments would otherwise have occupied.
            let baselineLineHeight = baselineFrames[2].origin.y - baselineFrames[1].origin.y // one line's height
            let expectedShrink = baselineLineHeight * 3
            let baselineUsageHeight = baseline.layoutManager.usageBoundsForTextContainer.height
            let collapsedUsageHeight = collapsed.layoutManager.usageBoundsForTextContainer.height
            XCTAssertEqual(baselineUsageHeight - collapsedUsageHeight, expectedShrink, accuracy: 0.5)
        }

        @MainActor
        func testMechanismA_DocumentStorageIsNeverMutated() {
            let collapsed = makeStack(collapsedLines: ["l2", "l3", "l4"])
            // Visual collapse must never touch the backing text storage.
            XCTAssertEqual(collapsed.contentStorage.textStorage?.string, documentText)
        }

        // MARK: - Production API: STTextView.foldedRanges

        /// 6 single-line paragraphs, laid out headlessly -- no window needed,
        /// mirrors the pattern SizeToFitTests already relies on
        /// (`textLayoutManager.ensureLayout(for:)` works without adding the
        /// view to a window).
        @MainActor
        private func makeFoldTextView() -> STTextView {
            let textView = STTextView()
            textView.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = true
            textView.setString((1 ... 6).map { "Line \($0)" }.joined(separator: "\n"))
            return textView
        }

        /// The BODY range MeatPad would pass for a fold over paragraphs 2-4:
        /// everything from the start of "Line 2" up to (not including) the
        /// start of "Line 5". Paragraph 1 ("Line 1", the fold head) is
        /// deliberately excluded so it stays visible.
        @MainActor
        private func bodyRange(_ textView: STTextView) -> NSTextRange {
            let string = textView.text! as NSString
            let start = string.range(of: "Line 2").location
            let end = string.range(of: "Line 5").location
            return NSTextRange(NSRange(location: start, length: end - start), in: textView.textContentManager)!
        }

        @MainActor
        private func fragmentFrames(_ textView: STTextView) -> [CGRect] {
            var frames: [CGRect] = []
            textView.textLayoutManager.enumerateTextLayoutFragments(from: textView.textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                frames.append(fragment.layoutFragmentFrame)
                return true
            }
            return frames
        }

        @MainActor
        func testFoldedRangesCollapseFragmentsAndStackSubsequentLines() {
            let baseline = makeFoldTextView()
            baseline.textLayoutManager.ensureLayout(for: baseline.textLayoutManager.documentRange)
            let baselineFrames = fragmentFrames(baseline)
            XCTAssertEqual(baselineFrames.count, 6)
            let baselineLine2Y = baselineFrames[1].origin.y // "Line 2"

            let textView = makeFoldTextView()
            textView.foldedRanges = [bodyRange(textView)]
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

            let frames = fragmentFrames(textView)
            XCTAssertEqual(frames.count, 6, "fragments still exist for every paragraph -- just zero height")
            XCTAssertEqual(frames[1].height, 0, accuracy: 0.001, "Line 2 (body) collapsed")
            XCTAssertEqual(frames[2].height, 0, accuracy: 0.001, "Line 3 (body) collapsed")
            XCTAssertEqual(frames[3].height, 0, accuracy: 0.001, "Line 4 (body) collapsed")
            XCTAssertGreaterThan(frames[0].height, 0, "Line 1 (fold head) stays visible")
            XCTAssertGreaterThan(frames[4].height, 0, "Line 5 stays visible")

            // Line 5's fragment sits directly below Line 1's head fragment --
            // exactly where Line 2 used to sit in the uncollapsed baseline.
            XCTAssertEqual(frames[4].origin.y, baselineLine2Y, accuracy: 0.001)
        }

        @MainActor
        func testFoldedRangesLeaveTextStorageIntact() {
            let textView = makeFoldTextView()
            let originalText = textView.text

            textView.foldedRanges = [bodyRange(textView)]
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

            XCTAssertEqual(textView.text, originalText)
            XCTAssertEqual(textView.attributedText?.string, originalText)
        }

        @MainActor
        func testClearingFoldedRangesRestoresFullHeight() {
            let textView = makeFoldTextView()
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
            let fullHeight = textView.textLayoutManager.usageBoundsForTextContainer.height

            textView.foldedRanges = [bodyRange(textView)]
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
            XCTAssertLessThan(textView.textLayoutManager.usageBoundsForTextContainer.height, fullHeight)

            textView.foldedRanges = []
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
            XCTAssertEqual(textView.textLayoutManager.usageBoundsForTextContainer.height, fullHeight, accuracy: 0.5)
        }

        // MARK: - Dynamic toggle (fold/unfold AFTER an initial layout already happened)
        //
        // The tests above fold before ever forcing layout once. These prove
        // the dynamic path instead: `foldedRanges`' didSet must invalidate
        // the *already laid out* fragments and force the
        // NSTextLayoutManagerDelegate to be re-consulted so `isCollapsed` is
        // recomputed for each fragment -- not just skip layout of new content.

        @MainActor
        func testDynamicFoldAfterInitialLayoutCollapsesFragments() {
            let textView = makeFoldTextView()
            // Force a real, complete initial layout pass -- fragments already exist.
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
            let fullHeight = textView.textLayoutManager.usageBoundsForTextContainer.height
            XCTAssertEqual(fragmentFrames(textView).count, 6)
            XCTAssertEqual(fragmentFrames(textView).map(\.height).filter { $0 == 0 }.count, 0, "nothing collapsed yet")

            // Fold on the already-laid-out view.
            textView.foldedRanges = [bodyRange(textView)]
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

            let frames = fragmentFrames(textView)
            XCTAssertEqual(frames[1].height, 0, accuracy: 0.001)
            XCTAssertEqual(frames[2].height, 0, accuracy: 0.001)
            XCTAssertEqual(frames[3].height, 0, accuracy: 0.001)
            XCTAssertLessThan(textView.textLayoutManager.usageBoundsForTextContainer.height, fullHeight)
        }

        @MainActor
        func testDynamicUnfoldAfterFoldRestoresFullHeight() {
            let textView = makeFoldTextView()
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
            let fullHeight = textView.textLayoutManager.usageBoundsForTextContainer.height

            textView.foldedRanges = [bodyRange(textView)]
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
            XCTAssertLessThan(textView.textLayoutManager.usageBoundsForTextContainer.height, fullHeight)

            textView.foldedRanges = []
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

            let frames = fragmentFrames(textView)
            XCTAssertEqual(frames.count, 6)
            for frame in frames {
                XCTAssertGreaterThan(frame.height, 0, "no fragment should remain collapsed after unfolding")
            }
            XCTAssertEqual(textView.textLayoutManager.usageBoundsForTextContainer.height, fullHeight, accuracy: 0.5)
        }

        // MARK: - STTextLayoutFragment.draw(at:in:) skip guard

        /// `draw(at:in:)` guards `!isCollapsed` and returns before touching the
        /// context (STTextLayoutFragment.swift). Proves that guard headlessly:
        /// grab a real, production-wired collapsed fragment, hand it an offscreen
        /// bitmap pre-filled with a sentinel byte pattern, call draw, and assert
        /// the buffer is byte-for-byte unchanged -- i.e. nothing was painted.
        @MainActor
        func testCollapsedFragmentDrawIsANoOp() {
            let textView = makeFoldTextView()
            textView.foldedRanges = [bodyRange(textView)]
            textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

            var collapsedFragment: STTextLayoutFragment?
            textView.textLayoutManager.enumerateTextLayoutFragments(from: textView.textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                if let stFragment = fragment as? STTextLayoutFragment, stFragment.isCollapsed {
                    collapsedFragment = stFragment
                    return false // found one, stop enumerating
                }
                return true
            }
            guard let fragment = collapsedFragment else {
                XCTFail("expected at least one collapsed fragment among Line 2-4's bodies")
                return
            }

            let width = 64, height = 32, bytesPerPixel = 4
            let bufferSize = width * height * bytesPerPixel
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4)
            defer { buffer.deallocate() }
            memset(buffer, 0xAB, bufferSize) // sentinel fill -- not the color anything would legitimately draw

            guard let context = CGContext(
                data: buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                XCTFail("failed to create offscreen bitmap context")
                return
            }

            let before = Data(bytes: buffer, count: bufferSize)
            fragment.draw(at: .zero, in: context)
            let after = Data(bytes: buffer, count: bufferSize)

            XCTAssertEqual(before, after, "draw(at:in:) must be a no-op for a collapsed fragment")
        }

        @MainActor
        func testIsRangeFoldedReflectsFoldedRanges() {
            let textView = makeFoldTextView()
            let fold = bodyRange(textView)

            textView.foldedRanges = [fold]
            XCTAssertTrue(textView.isRangeFolded(fold))

            let headRange = NSTextRange(location: textView.textLayoutManager.documentRange.location, end: fold.location)!
            XCTAssertFalse(textView.isRangeFolded(headRange), "the fold head paragraph is not part of the folded body range")

            textView.foldedRanges = []
            XCTAssertFalse(textView.isRangeFolded(fold), "clearing foldedRanges un-folds every range")
        }
    }
#endif
