//
//  file: test_about_window_layout.m
//  project: LuLu_Plus (tests)
//  description: loads the real About window nib and checks the fork attribution has room for
//                every language the app ships, without colliding with the existing controls
//
//  usage: test_about_window_layout <path to compiled AboutWindow.nib>
//

@import Cocoa;
@import OSLog;

#import "AboutWindowController.h"

//defined by the app at runtime; the sources under test only log through it
os_log_t logHandle = NULL;

static NSUInteger testsRun = 0;
static NSUInteger testsFailed = 0;

static void check(const char* description, BOOL condition)
{
    testsRun++;

    if(YES != condition)
    {
        testsFailed++;
        printf("  FAIL  %s\n", description);
        return;
    }

    printf("  ok    %s\n", description);
}

//the band the controller lays the attribution out in
static const NSRect kAttributionFrame = {20, 48, 446, 32};

static BOOL overlaps(NSRect a, NSRect b)
{
    return (YES != NSIsEmptyRect(NSIntersectionRect(a, b)));
}

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc < 3)
        {
            printf("usage: %s <compiled AboutWindow.nib> <language>\n", argv[0]);
            return 2;
        }

        NSString* nibPath = [NSString stringWithUTF8String:argv[1]];
        NSString* requested = [NSString stringWithUTF8String:argv[2]];

        //ask AppKit to localize as the caller wants, before any bundle caches one
        [[NSUserDefaults standardUserDefaults] setObject:@[requested] forKey:@"AppleLanguages"];

        if(YES != [[NSFileManager defaultManager] fileExistsAtPath:nibPath])
        {
            printf("ERROR: no nib at %s\n", nibPath.UTF8String);
            return 2;
        }

        [NSApplication sharedApplication];

        //what the harness is rendering, and what the window will show
        NSString* language = [[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: requested;

        printf("\nAbout window [%s]\n", language.UTF8String);
        printf("---------------------------------\n");

        //the controller is the nib's File's Owner, as it is in the app
        AboutWindowController* controller = [[AboutWindowController alloc] init];
        controller = [controller initWithWindowNibPath:nibPath owner:controller];

        //loads the nib, which runs -windowDidLoad
        NSWindow* window = controller.window;

        check("the nib loads", nil != window);
        if(nil == window)
        {
            printf("%lu/%lu checks passed\n", (unsigned long)(testsRun - testsFailed), (unsigned long)testsRun);
            return 1;
        }

        NSView* content = window.contentView;

        check("the window is 486x326 (the nib grew 25pt for the attribution)",
              486 == content.frame.size.width && 326 == content.frame.size.height);

        //find the attribution: the only subview that isn't in the nib
        NSTextField* attribution = nil;

        for(NSView* view in content.subviews)
        {
            if(YES != [view isKindOfClass:NSTextField.class]) continue;
            if(YES == [view isEqual:controller.versionLabel]) continue;

            attribution = (NSTextField*)view;
        }

        check("the controller adds an attribution label", nil != attribution);
        if(nil == attribution)
        {
            printf("%lu/%lu checks passed\n", (unsigned long)(testsRun - testsFailed), (unsigned long)testsRun);
            return 1;
        }

        NSString* text = attribution.stringValue;

        printf("   \"%s\"\n", text.UTF8String);

        check("the attribution names the upstream baseline",
              NSNotFound != [text rangeOfString:@"4.5.1"].location);

        //the point of naming a branch: the fork is not the 4.5.1 release
        check("the attribution says the baseline is a branch",
              NSNotFound != [text rangeOfString:@"master"].location);

        check("the attribution no longer claims LuLu_Plus 4.5.1 itself is the baseline",
              NSNotFound == [text rangeOfString:@"LuLu_Plus 4.5.1"].location);

        check("the attribution names Objective-See",
              NSNotFound != [text rangeOfString:@"Objective-See"].location);

        check("the attribution credits Patrick Wardle",
              NSNotFound != [text rangeOfString:@"Patrick Wardle"].location);

        //does the text actually fit the band it was given?
        NSDictionary* attributes = @{NSFontAttributeName : attribution.font};

        NSRect needed = [text boundingRectWithSize:NSMakeSize(kAttributionFrame.size.width, CGFLOAT_MAX)
                                           options:(NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading)
                                        attributes:attributes];

        needed = NSIntegralRect(needed);

        printf("   needs %.0fx%.0f in a %.0fx%.0f band\n",
               needed.size.width, needed.size.height,
               kAttributionFrame.size.width, kAttributionFrame.size.height);

        check("the text fits its band (no truncation)",
              needed.size.height <= kAttributionFrame.size.height &&
              needed.size.width <= kAttributionFrame.size.width);

        check("the label frame is the documented band",
              NSEqualRects(attribution.frame, kAttributionFrame));

        //it must not sit on top of a neighbour, and must stay inside the window
        BOOL overlapsNeighbour = NO;
        BOOL allInside = YES;

        for(NSView* view in content.subviews)
        {
            if(YES != [view isEqual:attribution])
            {
                if(YES == overlaps(attribution.frame, view.frame))
                {
                    printf("   overlaps: %s %s\n", NSStringFromClass(view.class).UTF8String,
                           NSStringFromRect(view.frame).UTF8String);
                    overlapsNeighbour = YES;
                }
            }

            if(YES != NSContainsRect(content.bounds, view.frame))
            {
                printf("   out of bounds: %s %s\n", NSStringFromClass(view.class).UTF8String,
                       NSStringFromRect(view.frame).UTF8String);
                allInside = NO;
            }
        }

        check("the attribution overlaps no other control", YES != overlapsNeighbour);
        check("every control is inside the window", allInside);

        printf("\n%lu/%lu checks passed\n", (unsigned long)(testsRun - testsFailed), (unsigned long)testsRun);

        if(0 != testsFailed)
        {
            printf("FAILED: %lu check(s)\n", (unsigned long)testsFailed);
            return 1;
        }
    }

    return 0;
}
