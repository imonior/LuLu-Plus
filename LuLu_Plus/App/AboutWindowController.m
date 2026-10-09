//
//  file: AboutWindowController.m
//  project: lulu_plus (main app)
//  description: 'about' window controller
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

#import "consts.h"
#import "utilities.h"
#import "AboutWindowController.h"

@implementation AboutWindowController

@synthesize patrons;
@synthesize versionLabel;

//automatically called when nib is loaded
// ->center window
-(void)awakeFromNib
{
    //center
    [self.window center];
}

//automatically invoked when window is loaded
// set to window to white, set app version, patrons, etc
-(void)windowDidLoad
{
    //version
    NSString* version = nil;
    
    //super
    [super windowDidLoad];
    
    //not in dark mode?
    // make window white
    if(YES != isDarkMode())
    {
        //make white
        self.window.backgroundColor = NSColor.whiteColor;
    }
    
    //grab app version
    version = getAppVersion();
    if(nil == version)
    {
        //default
        version = NSLocalizedString(@"unknown", @"unknown");
    }
    
    //set version sting
    self.versionLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Version: %@", @"Version: %@"), version];

    //attribution
    // note: laid out here rather than in the nib, so the sentence goes through the shared
    //       string catalog and reads in every language the app ships
    NSTextField* attribution = [NSTextField labelWithString:NSLocalizedString(@"LuLu_Plus is a fork of LuLu by Objective-See, based on its master branch after the 4.5.1 release. Thanks to Patrick Wardle for open-sourcing LuLu.",
                                                                              @"LuLu_Plus is a fork of LuLu by Objective-See, based on its master branch after the 4.5.1 release. Thanks to Patrick Wardle for open-sourcing LuLu.")];

    //footnote styling, wrapped across the width of the window
    attribution.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    attribution.textColor = NSColor.secondaryLabelColor;
    attribution.alignment = NSTextAlignmentCenter;
    attribution.maximumNumberOfLines = 0;
    attribution.cell.wraps = YES;
    attribution.lineBreakMode = NSLineBreakByWordWrapping;

    //the band the nib leaves between the buttons and the patrons list
    attribution.frame = NSMakeRect(20, 48, 446, 32);

    [self.window.contentView addSubview:attribution];

    //load patrons
    self.patrons.string = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"patrons" ofType:@"txt"] encoding:NSUTF8StringEncoding error:NULL];
    if(nil == self.patrons.string)
    {
        //default
        self.patrons.string = NSLocalizedString(@"ERROR: failed to load patrons", @"ERROR: failed to load patrons");
    }

    return;
}

//automatically invoked when window is closing
// ->make window unmodal
-(void)windowWillClose:(NSNotification *)notification
{
    //make un-modal
    [[NSApplication sharedApplication] stopModal];
    
    return;
}

//automatically invoked when user clicks any of the buttons
// open the project's page, either as support or as documentation
-(IBAction)buttonHandler:(id)sender
{
    //support us button
    if(((NSButton*)sender).tag == BUTTON_SUPPORT_US)
    {
        //open URL
        // invokes user's default browser
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:PRODUCT_URL]];
    }
    
    //more info button
    else if(((NSButton*)sender).tag == BUTTON_MORE_INFO)
    {
        //open URL
        // invokes user's default browser
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:PRODUCT_URL]];
    }

    return;
}
@end
