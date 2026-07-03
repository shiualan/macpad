/*
 macpad

 Native AppKit text editor for macOS.

 BSD 3-Clause License
 Copyright (c) 2026, David William Plummer
 See LICENSE in the repository root for full license terms.
*/

#import <Cocoa/Cocoa.h>

static const unsigned long long RPMaxOpenFileBytes = 64ULL * 1024ULL * 1024ULL;
static NSString * const RPAppName = @"macpad";

typedef NS_ENUM(NSInteger, RPTextEncoding) {
    RPTextEncodingUTF8 = 1,
    RPTextEncodingUTF16LE = 2,
    RPTextEncodingUTF16BE = 3,
    RPTextEncodingANSI = 4
};

@class RPDocumentWindowController;

@interface RPStatusBarView : NSView
@end

@implementation RPStatusBarView

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [NSColor.controlBackgroundColor setFill];
    NSRectFill(self.bounds);
    [NSColor.separatorColor setFill];
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 1.0, self.bounds.size.width, 1.0));
}

@end

@interface RPLineNumberRulerView : NSRulerView
@property (weak) NSTextView *textView;
@end

@implementation RPLineNumberRulerView

- (instancetype)initWithTextView:(NSTextView *)textView {
    self = [super initWithScrollView:textView.enclosingScrollView orientation:NSVerticalRuler];
    if (self) {
        _textView = textView;
        self.ruleThickness = 44.0;
        self.clientView = textView;
    }
    return self;
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    (void)rect;
    [NSColor.controlBackgroundColor setFill];
    NSRectFill(self.bounds);
    [NSColor.separatorColor setFill];
    NSRectFill(NSMakeRect(self.bounds.size.width - 1.0, 0, 1.0, self.bounds.size.height));

    NSLayoutManager *layoutManager = self.textView.layoutManager;
    NSTextContainer *textContainer = self.textView.textContainer;
    NSString *text = self.textView.string ? self.textView.string : @"";
    if (!layoutManager || !textContainer) return;

    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRect visibleRect = self.scrollView.contentView.bounds;
    NSRange glyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:textContainer];
    NSRange characterRange = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];

    NSUInteger firstLine = 1;
    NSUInteger location = 0;
    while (location < characterRange.location && location < text.length) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
        NSUInteger nextLocation = NSMaxRange(lineRange);
        if (nextLocation <= location) break;
        firstLine++;
        location = nextLocation;
    }

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };

    NSUInteger lineNumber = firstLine;
    location = characterRange.location;
    if (location > 0) {
        location = [text lineRangeForRange:NSMakeRange(location, 0)].location;
    }

    while (location <= NSMaxRange(characterRange) && location <= text.length) {
        NSRange lineRange = location < text.length ? [text lineRangeForRange:NSMakeRange(location, 0)] : NSMakeRange(text.length, 0);
        NSRect lineRect = NSZeroRect;
        if (lineRange.location >= text.length) {
            lineRect = layoutManager.extraLineFragmentRect;
        } else {
            NSRange glyphLineRange = [layoutManager glyphRangeForCharacterRange:lineRange actualCharacterRange:NULL];
            NSUInteger glyphIndex = glyphLineRange.length == 0 ? [layoutManager glyphIndexForCharacterAtIndex:lineRange.location] : glyphLineRange.location;
            lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];
        }
        if (NSIsEmptyRect(lineRect)) break;
        CGFloat y = NSMinY(lineRect) - visibleRect.origin.y + self.textView.textContainerOrigin.y;
        NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize numberSize = [number sizeWithAttributes:attributes];
        [number drawAtPoint:NSMakePoint(self.ruleThickness - numberSize.width - 8.0, y) withAttributes:attributes];

        if (lineRange.length == 0 || NSMaxRange(lineRange) <= location) break;
        location = NSMaxRange(lineRange);
        lineNumber++;
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

@end

@interface RPDocumentWindowController : NSObject <NSWindowDelegate, NSTextViewDelegate, NSDraggingDestination>
@property (strong) NSWindow *window;
@property (strong) NSScrollView *scrollView;
@property (strong) NSTextView *textView;
@property (strong) NSView *statusBar;
@property (strong) NSTextField *statusLabel;
@property (strong) RPLineNumberRulerView *lineNumberRuler;
@property (strong) NSURL *currentURL;
@property (assign) NSPoint cascadePoint;
@property (assign) RPTextEncoding currentEncoding;
@property (assign) BOOL modified;
@property (assign) BOOL wordWrap;
@property (assign) BOOL statusVisible;
@property (assign) BOOL lineNumbersVisible;
@property (assign) BOOL closing;
@end

@interface RPAppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
@property (strong) NSMutableArray<RPDocumentWindowController *> *documents;
@property (assign) NSPoint nextWindowOrigin;
- (RPDocumentWindowController *)createDocument;
- (RPDocumentWindowController *)activeDocument;
- (void)documentWindowDidClose:(RPDocumentWindowController *)document;
@end

@implementation RPDocumentWindowController

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentEncoding = RPTextEncodingUTF8;
        _statusVisible = YES;
        [self buildWindow];
        [self updateTitle];
        [self updateStatusBar];
    }
    return self;
}

- (NSString *)stringOrDefault:(NSString *)string fallback:(NSString *)fallback {
    return string ? string : fallback;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 760, 520);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    self.window.minSize = NSMakeSize(360, 240);
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    [self.window registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

    NSView *content = self.window.contentView;
    self.scrollView = [[NSScrollView alloc] initWithFrame:content.bounds];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = YES;
    self.scrollView.autohidesScrollers = NO;

    self.textView = [[NSTextView alloc] initWithFrame:self.scrollView.contentView.bounds];
    self.textView.delegate = self;
    self.textView.minSize = NSMakeSize(0, 0);
    self.textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.textView.verticallyResizable = YES;
    self.textView.horizontallyResizable = YES;
    self.textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.textView.allowsUndo = YES;
    self.textView.richText = NO;
    self.textView.importsGraphics = NO;
    self.textView.usesFindBar = YES;
    self.textView.automaticQuoteSubstitutionEnabled = NO;
    self.textView.automaticDashSubstitutionEnabled = NO;
    NSFont *fixedFont = [NSFont userFixedPitchFontOfSize:13.0];
    self.textView.font = fixedFont ? fixedFont : [NSFont systemFontOfSize:13.0];
    self.textView.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.textView.textContainer.widthTracksTextView = NO;
    self.scrollView.documentView = self.textView;

    self.lineNumberRuler = [[RPLineNumberRulerView alloc] initWithTextView:self.textView];
    self.scrollView.verticalRulerView = self.lineNumberRuler;
    self.scrollView.hasVerticalRuler = NO;
    self.scrollView.rulersVisible = NO;
    self.scrollView.contentView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scrollViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:self.scrollView.contentView];

    self.statusBar = [[RPStatusBarView alloc] initWithFrame:NSMakeRect(0, 0, content.bounds.size.width, 24)];
    self.statusBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.frame = NSMakeRect(12, 3, content.bounds.size.width - 24, 18);
    self.statusLabel.autoresizingMask = NSViewWidthSizable;
    self.statusLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self.statusBar addSubview:self.statusLabel];

    [content addSubview:self.scrollView];
    [content addSubview:self.statusBar];
    [self layoutViews];
}

- (void)showWindow {
    if (!NSEqualPoints(self.cascadePoint, NSZeroPoint)) {
        self.cascadePoint = [self.window cascadeTopLeftFromPoint:self.cascadePoint];
    }
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.textView];
}

- (void)layoutViews {
    NSView *content = self.window.contentView;
    CGFloat statusHeight = self.statusVisible ? 24.0 : 0.0;
    self.statusBar.hidden = !self.statusVisible;
    self.statusBar.frame = NSMakeRect(0, 0, content.bounds.size.width, statusHeight);
    self.scrollView.frame = NSMakeRect(0, statusHeight, content.bounds.size.width, content.bounds.size.height - statusHeight);
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self layoutViews];
    [self updateStatusBar];
    [self.lineNumberRuler setNeedsDisplay:YES];
}

- (void)scrollViewBoundsDidChange:(NSNotification *)notification {
    (void)notification;
    [self.lineNumberRuler setNeedsDisplay:YES];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    if (self.closing) return YES;
    return [self promptSaveChanges];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (self.closing) return;
    self.closing = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.textView.delegate = nil;
    self.window.delegate = nil;
    RPAppDelegate *delegate = (RPAppDelegate *)NSApp.delegate;
    [delegate documentWindowDidClose:self];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pasteboard = sender.draggingPasteboard;
    return [pasteboard canReadObjectForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}] ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSURL *url = urls.firstObject;
    if (!url) return NO;
    return [self loadURL:url];
}

- (void)textDidChange:(NSNotification *)notification {
    (void)notification;
    self.modified = YES;
    [self updateTitle];
    [self updateStatusBar];
    [self.lineNumberRuler setNeedsDisplay:YES];
}

- (void)textViewDidChangeSelection:(NSNotification *)notification {
    (void)notification;
    [self updateStatusBar];
    [self.lineNumberRuler setNeedsDisplay:YES];
}

- (void)newDocument:(id)sender {
    (void)sender;
    RPAppDelegate *delegate = (RPAppDelegate *)NSApp.delegate;
    [[delegate createDocument] showWindow];
}

- (void)openDocument:(id)sender {
    (void)sender;
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    if ([panel runModal] == NSModalResponseOK) {
        RPAppDelegate *delegate = (RPAppDelegate *)NSApp.delegate;
        for (NSURL *url in panel.URLs) {
            RPDocumentWindowController *document = [delegate createDocument];
            if ([document loadURL:url]) {
                [document showWindow];
            } else {
                [document.window close];
            }
        }
    }
}

- (void)saveDocument:(id)sender {
    (void)sender;
    if (self.currentURL) {
        [self saveToURL:self.currentURL];
    } else {
        [self saveDocumentAs:nil];
    }
}

- (void)saveDocumentAs:(id)sender {
    (void)sender;
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.nameFieldStringValue = [self stringOrDefault:self.currentURL.lastPathComponent fallback:@"Untitled.txt"];
    if ([panel runModal] == NSModalResponseOK) {
        [self saveToURL:panel.URL];
    }
}

- (void)pageSetup:(id)sender {
    (void)sender;
    [[NSPageLayout pageLayout] runModal];
}

- (void)printDocument:(id)sender {
    (void)sender;
    [self.textView print:nil];
}

- (void)showFind:(id)sender {
    (void)sender;
    [self performFindAction:NSFindPanelActionShowFindPanel];
}

- (void)showReplace:(id)sender {
    (void)sender;
    [self performFindAction:NSTextFinderActionShowReplaceInterface];
}

- (void)findNext:(id)sender {
    (void)sender;
    [self performFindAction:NSFindPanelActionNext];
}

- (void)findPrevious:(id)sender {
    (void)sender;
    [self performFindAction:NSFindPanelActionPrevious];
}

- (void)performFindAction:(NSInteger)tag {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    item.tag = tag;
    [self.textView performFindPanelAction:item];
}

- (void)goToLine:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Go To Line";
    alert.informativeText = @"Line number:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
    field.stringValue = @"1";
    alert.accessoryView = field;
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSInteger requestedLine = field.integerValue;
    if (requestedLine < 1) {
        [self showMessage:@"Enter a valid line number."];
        return;
    }

    NSString *text = [self stringOrDefault:self.textView.string fallback:@""];
    NSUInteger targetLocation = 0;
    for (NSInteger currentLine = 1; currentLine < requestedLine && targetLocation < text.length; currentLine++) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(targetLocation, 0)];
        targetLocation = NSMaxRange(lineRange);
    }
    if (targetLocation > text.length) targetLocation = text.length;
    [self.textView setSelectedRange:NSMakeRange(targetLocation, 0)];
    [self.textView scrollRangeToVisible:self.textView.selectedRange];
}

- (void)insertTimeDate:(id)sender {
    (void)sender;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    [self.textView insertText:[formatter stringFromDate:NSDate.date] replacementRange:self.textView.selectedRange];
}

- (void)toggleWordWrap:(id)sender {
    (void)sender;
    self.wordWrap = !self.wordWrap;
    self.textView.horizontallyResizable = !self.wordWrap;
    self.scrollView.hasHorizontalScroller = !self.wordWrap;
    if (self.wordWrap) {
        self.textView.textContainer.containerSize = NSMakeSize(self.scrollView.contentSize.width, CGFLOAT_MAX);
        self.textView.textContainer.widthTracksTextView = YES;
    } else {
        self.textView.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        self.textView.textContainer.widthTracksTextView = NO;
    }
    [self layoutViews];
    [self updateStatusBar];
}

- (void)toggleStatusBar:(id)sender {
    (void)sender;
    self.statusVisible = !self.statusVisible;
    [self layoutViews];
    [self updateStatusBar];
}

- (void)toggleLineNumbers:(id)sender {
    (void)sender;
    self.lineNumbersVisible = !self.lineNumbersVisible;
    self.scrollView.hasVerticalRuler = self.lineNumbersVisible;
    self.scrollView.rulersVisible = self.lineNumbersVisible;
    [self.lineNumberRuler setNeedsDisplay:YES];
}

- (BOOL)promptSaveChanges {
    if (!self.modified) return YES;

    NSAlert *alert = [[NSAlert alloc] init];
    NSString *name = [self stringOrDefault:self.currentURL.lastPathComponent fallback:@"Untitled"];
    alert.messageText = [NSString stringWithFormat:@"Do you want to save changes to %@?", name];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [self saveDocument:nil];
        return !self.modified;
    }
    if (response == NSAlertSecondButtonReturn) return NO;
    return YES;
}

- (BOOL)loadURL:(NSURL *)url {
    BOOL securityScoped = [url startAccessingSecurityScopedResource];
    if (![self validateReadableFileURL:url]) {
        if (securityScoped) [url stopAccessingSecurityScopedResource];
        return NO;
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    if (securityScoped) [url stopAccessingSecurityScopedResource];
    if (!data) {
        [self showError:@"Unable to open file." error:error];
        return NO;
    }

    RPTextEncoding encoding = RPTextEncodingUTF8;
    NSString *text = [self decodeData:data encoding:&encoding];
    if (!text) {
        [self showMessage:@"Unable to decode file."];
        return NO;
    }

    self.textView.string = text;
    self.currentURL = url;
    self.currentEncoding = encoding;
    self.modified = NO;
    [self.textView.undoManager removeAllActions];
    [self updateTitle];
    [self updateStatusBar];
    [self.lineNumberRuler setNeedsDisplay:YES];
    return YES;
}

- (BOOL)saveToURL:(NSURL *)url {
    NSData *data = [self encodedDataForString:[self stringOrDefault:self.textView.string fallback:@""] encoding:self.currentEncoding];
    if (!data) {
        [self showMessage:@"Unable to encode file without losing characters. Use Save As with UTF-8 if this document contains characters outside the original file encoding."];
        return NO;
    }

    NSError *error = nil;
    BOOL securityScoped = [url startAccessingSecurityScopedResource];
    BOOL wrote = [data writeToURL:url options:NSDataWritingAtomic error:&error];
    if (securityScoped) [url stopAccessingSecurityScopedResource];
    if (!wrote) {
        [self showError:@"Failed writing file." error:error];
        return NO;
    }

    self.currentURL = url;
    self.modified = NO;
    [self updateTitle];
    return YES;
}

- (BOOL)validateReadableFileURL:(NSURL *)url {
    if (!url.isFileURL) {
        [self showMessage:@"Only local files can be opened."];
        return NO;
    }

    NSError *error = nil;
    NSDictionary<NSURLResourceKey, id> *values = [url resourceValuesForKeys:@[
        NSURLIsRegularFileKey,
        NSURLIsDirectoryKey,
        NSURLFileSizeKey
    ] error:&error];
    if (!values) {
        [self showError:@"Unable to inspect file." error:error];
        return NO;
    }

    NSNumber *isDirectory = values[NSURLIsDirectoryKey];
    NSNumber *isRegular = values[NSURLIsRegularFileKey];
    if (isDirectory.boolValue || !isRegular.boolValue) {
        [self showMessage:@"Only regular text files can be opened."];
        return NO;
    }

    NSNumber *fileSize = values[NSURLFileSizeKey];
    if (fileSize && fileSize.unsignedLongLongValue > RPMaxOpenFileBytes) {
        [self showMessage:@"This file is too large to open safely in macpad."];
        return NO;
    }

    return YES;
}

- (NSString *)decodeData:(NSData *)data encoding:(RPTextEncoding *)encodingOut {
    const unsigned char *bytes = data.bytes;
    NSUInteger length = data.length;
    NSStringEncoding stringEncoding = NSUTF8StringEncoding;
    NSUInteger offset = 0;

    if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        stringEncoding = NSUTF16LittleEndianStringEncoding;
        *encodingOut = RPTextEncodingUTF16LE;
        offset = 2;
    } else if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        stringEncoding = NSUTF16BigEndianStringEncoding;
        *encodingOut = RPTextEncodingUTF16BE;
        offset = 2;
    } else if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        stringEncoding = NSUTF8StringEncoding;
        *encodingOut = RPTextEncodingUTF8;
        offset = 3;
    } else {
        NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (utf8) {
            *encodingOut = RPTextEncodingUTF8;
            return utf8;
        }
        stringEncoding = NSWindowsCP1252StringEncoding;
        *encodingOut = RPTextEncodingANSI;
    }

    NSData *body = (offset == 0) ? data : [data subdataWithRange:NSMakeRange(offset, length - offset)];
    return [[NSString alloc] initWithData:body encoding:stringEncoding];
}

-(NSData *)encodedDataForString:(NSString *)string encoding:(RPTextEncoding)encoding {
    NSMutableData *result = [NSMutableData data];
    NSStringEncoding stringEncoding = NSUTF8StringEncoding;

    switch (encoding) {
        case RPTextEncodingUTF16LE: {
            const unsigned char bom[] = {0xFF, 0xFE};
            [result appendBytes:bom length:sizeof(bom)];
            stringEncoding = NSUTF16LittleEndianStringEncoding;
            break;
        }
        case RPTextEncodingANSI:
            stringEncoding = NSWindowsCP1252StringEncoding;
            break;
        case RPTextEncodingUTF16BE:
        case RPTextEncodingUTF8:
        default: {
            const unsigned char bom[] = {0xEF, 0xBB, 0xBF};
            [result appendBytes:bom length:sizeof(bom)];
            stringEncoding = NSUTF8StringEncoding;
            break;
        }
    }

    NSData *body = [string dataUsingEncoding:stringEncoding allowLossyConversion:NO];
    if (!body) return nil;
    [result appendData:body];
    return result;
}

- (void)updateTitle {
    NSString *name = [self stringOrDefault:self.currentURL.lastPathComponent fallback:@"Untitled"];
    self.window.title = [NSString stringWithFormat:@"%@%@ - %@", self.modified ? @"*" : @"", name, RPAppName];
    self.window.documentEdited = self.modified;
    self.window.representedURL = self.currentURL;
}

- (void)updateStatusBar {
    if (!self.statusVisible) return;
    NSString *text = [self stringOrDefault:self.textView.string fallback:@""];
    NSRange selected = self.textView.selectedRange;
    NSUInteger caret = selected.location < text.length ? selected.location : text.length;
    NSUInteger lineStart = 0;
    [text getLineStart:&lineStart end:NULL contentsEnd:NULL forRange:NSMakeRange(caret, 0)];
    NSUInteger col = caret >= lineStart ? caret - lineStart + 1 : 1;
    NSUInteger line = 1;
    for (NSUInteger location = 0; location < caret && location < text.length;) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
        NSUInteger nextLine = NSMaxRange(lineRange);
        if (nextLine <= caret && nextLine > location) {
            line++;
            location = nextLine;
        } else {
            break;
        }
    }
    __block NSUInteger lines = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        (void)substring;
        (void)substringRange;
        (void)enclosingRange;
        (void)stop;
        lines++;
    }];
    if (lines == 0 || [text hasSuffix:@"\n"] || [text hasSuffix:@"\r"]) lines++;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Ln %lu, Col %lu    Lines: %lu", (unsigned long)line, (unsigned long)col, (unsigned long)lines];
}

- (void)showMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showError:(NSString *)message error:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = [self stringOrDefault:error.localizedDescription fallback:@""];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

@implementation RPAppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _documents = [NSMutableArray array];
        _nextWindowOrigin = NSMakePoint(80.0, 80.0);
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSWindow.allowsAutomaticWindowTabbing = NO;
    [self buildMenu];
    [[self createDocument] showWindow];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    (void)app;
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender;
    if (flag) {
        [NSApp arrangeInFront:nil];
    } else {
        [[self createDocument] showWindow];
    }
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    for (RPDocumentWindowController *document in [self.documents copy]) {
        if (![document promptSaveChanges]) return NSTerminateCancel;
    }
    return NSTerminateNow;
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    (void)application;
    for (NSURL *url in urls) {
        RPDocumentWindowController *document = [self createDocument];
        if ([document loadURL:url]) {
            [document showWindow];
        } else {
            [document.window close];
        }
    }
}

- (RPDocumentWindowController *)createDocument {
    RPDocumentWindowController *document = [[RPDocumentWindowController alloc] init];
    document.cascadePoint = self.nextWindowOrigin;
    self.nextWindowOrigin = NSMakePoint(self.nextWindowOrigin.x + 24.0, self.nextWindowOrigin.y + 24.0);
    if (self.nextWindowOrigin.x > 260.0 || self.nextWindowOrigin.y > 260.0) {
        self.nextWindowOrigin = NSMakePoint(80.0, 80.0);
    }
    [self.documents addObject:document];
    return document;
}

- (void)documentWindowDidClose:(RPDocumentWindowController *)document {
    [self.documents removeObjectIdenticalTo:document];
}

-(RPDocumentWindowController *)activeDocument {
    NSWindow *keyWindow = NSApp.keyWindow ? NSApp.keyWindow : NSApp.mainWindow;
    for (RPDocumentWindowController *document in self.documents) {
        if (document.window == keyWindow) return document;
    }
    return self.documents.lastObject;
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSApp.mainMenu = mainMenu;

    NSMenuItem *appItem = [mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:RPAppName];
    appItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"About macpad" action:@selector(showAbout:) keyEquivalent:@""].target = self;
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Hide macpad" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Quit macpad" action:@selector(terminate:) keyEquivalent:@"q"];

    NSMenuItem *fileItem = [mainMenu addItemWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;
    [self addItem:@"New" action:@selector(newDocument:) key:@"n" to:fileMenu];
    [self addItem:@"Open..." action:@selector(openDocument:) key:@"o" to:fileMenu];
    [fileMenu addItem:NSMenuItem.separatorItem];
    [self addItem:@"Save" action:@selector(saveDocument:) key:@"s" to:fileMenu];
    NSMenuItem *saveAs = [self addItem:@"Save As..." action:@selector(saveDocumentAs:) key:@"S" to:fileMenu];
    saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItem:NSMenuItem.separatorItem];
    [self addItem:@"Page Setup..." action:@selector(pageSetup:) key:@"" to:fileMenu];
    [self addItem:@"Print..." action:@selector(printDocument:) key:@"p" to:fileMenu];
    [fileMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *closeItem = [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    closeItem.target = nil;

    NSMenuItem *editItem = [mainMenu addItemWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = editMenu;
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"].keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:NSMenuItem.separatorItem];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
    [editMenu addItem:NSMenuItem.separatorItem];
    [self addItem:@"Find..." action:@selector(showFind:) key:@"f" to:editMenu];
    [self addItem:@"Find Next" action:@selector(findNext:) key:@"g" to:editMenu];
    [self addItem:@"Find Previous" action:@selector(findPrevious:) key:@"G" to:editMenu].keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [self addItem:@"Replace..." action:@selector(showReplace:) key:@"h" to:editMenu];
    [self addItem:@"Go To..." action:@selector(goToLine:) key:@"l" to:editMenu];
    [editMenu addItem:NSMenuItem.separatorItem];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [self addItem:@"Time/Date" action:@selector(insertTimeDate:) key:@"" to:editMenu];

    NSMenuItem *formatItem = [mainMenu addItemWithTitle:@"Format" action:nil keyEquivalent:@""];
    NSMenu *formatMenu = [[NSMenu alloc] initWithTitle:@"Format"];
    formatItem.submenu = formatMenu;
    [self addItem:@"Word Wrap" action:@selector(toggleWordWrap:) key:@"" to:formatMenu];
    [formatMenu addItemWithTitle:@"Font..." action:@selector(orderFrontFontPanel:) keyEquivalent:@"t"];

    NSMenuItem *viewItem = [mainMenu addItemWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    viewItem.submenu = viewMenu;
    [self addItem:@"Status Bar" action:@selector(toggleStatusBar:) key:@"" to:viewMenu];
    [self addItem:@"Show Line Numbers" action:@selector(toggleLineNumbers:) key:@"" to:viewMenu];

    NSMenuItem *windowItem = [mainMenu addItemWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    windowItem.submenu = windowMenu;
    [self addWindowItem:@"Minimize" action:@selector(performMiniaturize:) key:@"m" to:windowMenu];
    [self addWindowItem:@"Zoom" action:@selector(performZoom:) key:@"" to:windowMenu];
    [windowMenu addItem:NSMenuItem.separatorItem];
    [self addWindowItem:@"Bring All to Front" action:@selector(arrangeInFront:) key:@"" to:windowMenu];
    NSApp.windowsMenu = windowMenu;

    NSMenuItem *helpItem = [mainMenu addItemWithTitle:@"Help" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    helpItem.submenu = helpMenu;
    [self addItem:@"License" action:@selector(showHelp:) key:@"" to:helpMenu];
}

-(NSMenuItem *)addItem:(NSString *)title action:(SEL)action key:(NSString *)key to:(NSMenu *)menu {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    return item;
}

-(NSMenuItem *)addWindowItem:(NSString *)title action:(SEL)action key:(NSString *)key to:(NSMenu *)menu {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.target = nil;
    return item;
}

-(BOOL)validateMenuItem:(NSMenuItem *)item {
    RPDocumentWindowController *document = self.activeDocument;
    BOOL needsDocument = item.action == @selector(saveDocument:) ||
                         item.action == @selector(saveDocumentAs:) ||
                         item.action == @selector(pageSetup:) ||
                         item.action == @selector(printDocument:) ||
                         item.action == @selector(showFind:) ||
                         item.action == @selector(showReplace:) ||
                         item.action == @selector(findNext:) ||
                         item.action == @selector(findPrevious:) ||
                         item.action == @selector(goToLine:) ||
                         item.action == @selector(insertTimeDate:) ||
                         item.action == @selector(toggleWordWrap:) ||
                         item.action == @selector(toggleStatusBar:) ||
                         item.action == @selector(toggleLineNumbers:);
    if (needsDocument && !document) return NO;
    if (item.action == @selector(saveDocument:)) return document.modified;
    if (item.action == @selector(toggleWordWrap:)) item.state = document.wordWrap ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(toggleStatusBar:)) item.state = document.statusVisible ? NSControlStateValueOn : NSControlStateValueOff;
    if (item.action == @selector(toggleLineNumbers:)) item.state = document.lineNumbersVisible ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}

-(void)newDocument:(id)sender { (void)sender; [[self createDocument] showWindow]; }
-(void)openDocument:(id)sender {
    (void)sender;
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    if ([panel runModal] == NSModalResponseOK) {
        for (NSURL *url in panel.URLs) {
            RPDocumentWindowController *document = [self createDocument];
            if ([document loadURL:url]) {
                [document showWindow];
            } else {
                [document.window close];
            }
        }
    }
}
-(void)saveDocument:(id)sender { [self.activeDocument saveDocument:sender]; }
-(void)saveDocumentAs:(id)sender { [self.activeDocument saveDocumentAs:sender]; }
-(void)pageSetup:(id)sender { [self.activeDocument pageSetup:sender]; }
-(void)printDocument:(id)sender { [self.activeDocument printDocument:sender]; }
-(void)showFind:(id)sender { [self.activeDocument showFind:sender]; }
-(void)showReplace:(id)sender { [self.activeDocument showReplace:sender]; }
-(void)findNext:(id)sender { [self.activeDocument findNext:sender]; }
-(void)findPrevious:(id)sender { [self.activeDocument findPrevious:sender]; }
-(void)goToLine:(id)sender { [self.activeDocument goToLine:sender]; }
-(void)insertTimeDate:(id)sender { [self.activeDocument insertTimeDate:sender]; }
-(void)toggleWordWrap:(id)sender { [self.activeDocument toggleWordWrap:sender]; }
-(void)toggleStatusBar:(id)sender { [self.activeDocument toggleStatusBar:sender]; }
-(void)toggleLineNumbers:(id)sender { [self.activeDocument toggleLineNumbers:sender]; }

-(void)showHelp:(id)sender {
    (void)sender;
    NSString *licenseText = [self normalizedLicenseText:[self bundledLicenseText]];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"macpad License";
    alert.informativeText = @"BSD 3-Clause License details.";
    [alert addButtonWithTitle:@"OK"];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 560, 320)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    NSTextView *licenseView = [[NSTextView alloc] initWithFrame:scrollView.contentView.bounds];
    licenseView.editable = NO;
    licenseView.selectable = YES;
    licenseView.richText = NO;
    licenseView.font = [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    licenseView.textColor = NSColor.labelColor;
    licenseView.backgroundColor = NSColor.textBackgroundColor;
    licenseView.string = licenseText;
    licenseView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    licenseView.textContainer.containerSize = NSMakeSize(scrollView.contentSize.width, CGFLOAT_MAX);
    licenseView.textContainer.widthTracksTextView = YES;
    scrollView.documentView = licenseView;
    alert.accessoryView = scrollView;
    [alert runModal];
}

-(void)showAbout:(id)sender {
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"macpad";
    alert.informativeText = @"A native macOS AppKit text editor.\n\nBSD 3-Clause licensed.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

-(NSString *)bundledLicenseText {
    NSURL *licenseURL = [NSBundle.mainBundle URLForResource:@"LICENSE" withExtension:nil];
    if (licenseURL) {
        NSError *error = nil;
        NSString *text = [NSString stringWithContentsOfURL:licenseURL encoding:NSUTF8StringEncoding error:&error];
        if (text.length > 0 && !error) return text;
    }
    return @"BSD 3-Clause License\n\nCopyright (c) 2026, David William Plummer\n\nRedistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n\n2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.\n\n3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.\n\nTHIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.";
}

-(NSString *)normalizedLicenseText:(NSString *)text {
    NSArray<NSString *> *paragraphs = [text componentsSeparatedByString:@"\n\n"];
    NSMutableArray<NSString *> *normalized = [NSMutableArray arrayWithCapacity:paragraphs.count];
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *paragraph in paragraphs) {
        NSArray<NSString *> *lines = [paragraph componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSMutableArray<NSString *> *trimmedLines = [NSMutableArray arrayWithCapacity:lines.count];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:whitespace];
            if (trimmed.length > 0) [trimmedLines addObject:trimmed];
        }
        if (trimmedLines.count > 0) [normalized addObject:[trimmedLines componentsJoinedByString:@" "]];
    }
    return [normalized componentsJoinedByString:@"\n\n"];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        RPAppDelegate *delegate = [[RPAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
