//
//  file: AboutWindowController.h
//  project: lulu_plus (main app)
//  description: 'about' window controller (header)
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

@import Cocoa;

@interface AboutWindowController : NSWindowController <NSWindowDelegate>
{
    
}

/* PROPERTIES */

//version label/string
@property (weak) IBOutlet NSTextField *versionLabel;

//patrons
@property (unsafe_unretained) IBOutlet NSTextView *patrons;

/* METHODS */

//automatically invoked when user clicks any of the buttons
// ->perform actions, such as opening the project's page
-(IBAction)buttonHandler:(id)sender;

@end
