//
//  file: PrefsWindowController+Language.m
//  project: lulu_plus (main app)
//  description: the Language tab: picks the language the UI runs in
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "PrefsWindowController+Private.h"
#import "Language.h"

//the pane's own geometry (the nib's panes are 650 wide)
#define LANGUAGE_VIEW_WIDTH 650
#define LANGUAGE_VIEW_HEIGHT 214

//a label in the panes' own style, Menlo like the nib's cells
static NSTextField* languageLabel(NSRect frame, NSString* text, NSFont* font, NSColor* color)
{
    NSTextField* label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = font;
    label.textColor = color;

    return label;
}

@implementation PrefsWindowController (Language)

//the language tab's view, built on first use
-(void)buildLanguageView
{
    NSFont* titleFont = [NSFont fontWithName:@"Menlo-Bold" size:13] ?: [NSFont boldSystemFontOfSize:13];
    NSFont* noteFont = [NSFont fontWithName:@"Menlo-Regular" size:11] ?: [NSFont systemFontOfSize:11];
    NSFont* itemFont = [NSFont fontWithName:@"Menlo-Regular" size:11] ?: [NSFont systemFontOfSize:11];

    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, LANGUAGE_VIEW_WIDTH, LANGUAGE_VIEW_HEIGHT)];
    view.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

    //title
    [view addSubview:languageLabel(NSMakeRect(39, 176, 400, 19),
                                   NSLocalizedString(@"Language", @"Language"),
                                   titleFont, [NSColor labelColor])];

    //picker: every language the catalogs carry, each written in that language
    NSPopUpButton* picker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(37, 132, 240, 25) pullsDown:NO];
    picker.font = itemFont;

    for(NSString* code in [Language shippedLanguages])
    {
        [picker addItemWithTitle:[Language displayNameForLanguage:code]];
        picker.lastItem.representedObject = code;
    }

    picker.target = self;
    picker.action = @selector(languageChanged:);
    [view addSubview:picker];

    //what happens with the pick
    NSTextField* note = languageLabel(NSMakeRect(39, 100, LANGUAGE_VIEW_WIDTH - 80, 32),
                                      NSLocalizedString(@"LuLu_Plus applies a new language after it is restarted.",
                                                        @"LuLu_Plus applies a new language after it is restarted."),
                                      noteFont, [NSColor secondaryLabelColor]);
    note.cell.wraps = YES;
    note.cell.lineBreakMode = NSLineBreakByWordWrapping;
    [view addSubview:note];

    //restarting is what actually swaps the language
    NSButton* restart = [NSButton buttonWithTitle:NSLocalizedString(@"Restart Now", @"Restart Now")
                                           target:self
                                           action:@selector(restartNow:)];
    restart.bezelStyle = NSBezelStyleRounded;

    //wide enough for the title in every language ("Jetzt neu starten", "ابھی دوبارہ شروع کریں"), centred
    // note: the font has to be set before -sizeToFit, which measures with whatever font is on the button
    restart.font = titleFont;
    [restart sizeToFit];
    CGFloat restartWidth = MAX(150.0, NSWidth(restart.frame));
    restart.frame = NSMakeRect(round((LANGUAGE_VIEW_WIDTH - restartWidth) / 2.0), 24, restartWidth, 32);

    [view addSubview:restart];

    //remember them for -refreshLanguageView
    self.languageView = view;
    self.languagePicker = picker;
    self.restartButton = restart;

    return;
}

//reflect the stored pick in the language tab
-(void)refreshLanguageView
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    //select the language in force
    NSString* language = [Language resolvedLanguage:defaults];

    for(NSMenuItem* item in self.languagePicker.itemArray)
    {
        if(YES == [item.representedObject isEqualToString:language])
        {
            [self.languagePicker selectItem:item];
            break;
        }
    }

    //restarting only means something once the pick differs from what is loaded
    self.restartButton.enabled = [Language restartRequired:defaults];

    return;
}

//user picked a language
-(IBAction)languageChanged:(id)sender
{
    //remember it; the running UI keeps its strings until the next launch
    [Language selectLanguage:self.languagePicker.selectedItem.representedObject];

    //button reflects whether a restart would now change anything
    [self refreshLanguageView];

    return;
}

//relaunch, so the pick takes effect
-(IBAction)restartNow:(id)sender
{
    //a fresh copy of ourselves
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.createsNewApplicationInstance = YES;

    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSBundle mainBundle].bundleURL
                                      configuration:configuration
                                completionHandler:^(NSRunningApplication* application, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{

            //couldn't come back up (moved app, e.g.): stay alive instead of vanishing
            if(nil != error)
            {
                os_log_error(logHandle, "failed to relaunch: %{public}@", error);
                return;
            }

            //the new copy is running; hand over
            [NSApp terminate:nil];
        });
    }];

    return;
}

@end
