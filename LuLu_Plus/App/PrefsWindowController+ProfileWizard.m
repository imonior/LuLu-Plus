//
//  file: PrefsWindowController+ProfileWizard.m
//  project: LuLu_Plus
//  description: the steps of the add-profile wizard: the name, the networks the profile is for, the rules, modes, lists and updates it takes, and what the last button commits
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "consts.h"
#import "utilities.h"
#import "AppDelegate.h"
#import "PrefsWindowController+Private.h"
#import "ProfileConditionsViewController.h"

@implementation PrefsWindowController (ProfileWizard)

//add profile button handler
// show sheet for user to specify settings
-(IBAction)addProfile:(id)sender {
    
    //dbg msg
    os_log_debug(logHandle, "%s invoked", __PRETTY_FUNCTION__);
    
    //init dictionary to collect preferences
    self.profilePreferences = [NSMutableDictionary dictionary];

    //start the network-conditions page from the last run of the wizard
    self.networkConditionsPage.conditionSets = nil;
    
    //init/reset
    self.profileName = nil;
    
    //init/reset
    self.continueProfileButton.tag = 0;
    
    //remove any old view
    if(self.currentProfileSubview) {
        
        //remove current view
        [self.currentProfileSubview removeFromSuperview];
    }

    //init current view (with profile name)
    self.currentProfileSubview = self.profileNameView;
    
    //add initial (profile name) view
    [self.addProfileSheet.contentView addSubview:self.currentProfileSubview positioned:NSWindowBelow relativeTo:nil];
    
    //make next button first responder
    [self.addProfileSheet makeFirstResponder:self.continueProfileButton];

    //watch for end of editing in name field so we can shift focus to Next
    self.profileNameLabel.delegate = self;
    
    //disable autoresizing mask
    self.currentProfileSubview.translatesAutoresizingMaskIntoConstraints = NO;

    //pin to top, leading, and trailing edges
    [NSLayoutConstraint activateConstraints:@[
        [self.currentProfileSubview.topAnchor constraintEqualToAnchor:self.addProfileSheet.contentView.topAnchor],
        [self.currentProfileSubview.leadingAnchor constraintEqualToAnchor:self.addProfileSheet.contentView.leadingAnchor],
        [self.currentProfileSubview.trailingAnchor constraintEqualToAnchor:self.addProfileSheet.contentView.trailingAnchor]
    ]];
    
    //reset button name
    self.continueProfileButton.title = NSLocalizedString(@"Next", @"Next");
    
    //set profile name
    self.profileNameLabel.stringValue = @"";
    
    //show sheet for user to add profile
    [self.window beginSheet:self.addProfileSheet
               completionHandler:^(NSModalResponse returnCode) {
        
            //add profile?
            // and handle UI refreshes, etc
            if (returnCode == NSModalResponseOK) {
            
                //dbg msg
                os_log_debug(logHandle, "user wants to add profile '%{public}@'", self.profileName);
                
                //add profile via XPC
                [xpcDaemonClient addProfile:self.profileName preferences:self.profilePreferences];
                
                //hide profile sheet
                [self.addProfileSheet orderOut:self];
                
                //tell app profiles changed
                // will grab profile's preferences too
                [((AppDelegate*)[[NSApplication sharedApplication] delegate]) profilesChanged];
                
                //tell app preferences changed
                [((AppDelegate*)[[NSApplication sharedApplication] delegate]) preferencesChanged:self.preferences];
                
                //show alert
                showAlert(NSAlertStyleInformational, NSLocalizedString(@"Added Profile", @"Added Profile"), [NSString stringWithFormat:NSLocalizedString(@"New profile '%@' saved and activated.", @"New profile '%@' saved and activated."), self.profileName], @[NSLocalizedString(@"OK", @"OK")]);
            }
            
            //cancel
            else {
                
                //close sheet
                [self.addProfileSheet orderOut:self];
            }
    }];
    
    return;
}

//cancel creation of profile
- (IBAction)cancelProfileButtonHandler:(id)sender {
    
    //end w/ cancel
    [self.window endSheet:self.addProfileSheet returnCode:NSModalResponseCancel];
    
    return;
}

//show next view
// note: each case is current view, going to next!
//the wizard's network-conditions page, made the first time it is asked for
-(NSView*)networkConditionsPageView
{
    if(nil == self.networkConditionsPage)
    {
        self.networkConditionsPage = [[ProfileConditionsViewController alloc] init];
        
        //the page outlives the wizard run it was made for, so a fresh one starts from what this
        //        profile says - which, for a profile being added, is nothing
        self.networkConditionsPage.conditionSets = self.profilePreferences[KEY_CONDITIONS];
    }

    return self.networkConditionsPage.view;
}

-(IBAction)continueProfileButtonHandler:(NSButton*)sender {
    
    //switch on current view
    // last view, will add the profile
    switch (sender.tag) {
            
        //current view: name
        // setup next view: rules
        case profileName:
        {
            //check against empty
            if(!self.profileNameLabel.stringValue.length)
            {
                //show alert
                showAlert(NSAlertStyleInformational, NSLocalizedString(@"Invalid Profile Name", @"Invalid Profile Name"), NSLocalizedString(@"Profile name can't be blank", @"Profile name can't be blank"), @[NSLocalizedString(@"OK", @"OK")]);
                
                self.profileNameLabel.stringValue = @"";
                goto bail;
            }
            
            //check against 'Default'
            if(NSOrderedSame == [self.profileNameLabel.stringValue caseInsensitiveCompare:NSLocalizedString(@"Default", @"Default")])
            {
                //show alert
                showAlert(NSAlertStyleInformational, NSLocalizedString(@"Invalid Profile Name", @"Invalid Profile Name"), NSLocalizedString(@"'Default' is a reserved profile name.", @"'Default' is a reserved profile name."), @[NSLocalizedString(@"OK", @"OK")]);
                
                goto bail;
            }
            
            //check against existing names
            for(NSString *name in [xpcDaemonClient getProfiles])
            {
                if(NSOrderedSame == [self.profileNameLabel.stringValue caseInsensitiveCompare:name])
                {
                    //show alert
                    showAlert(NSAlertStyleInformational, NSLocalizedString(@"Invalid Profile Name", @"Invalid Profile Name"), [NSString stringWithFormat:NSLocalizedString(@"'%@' matches an existing profile name.", @"'%@' matches an existing profile name."), name], @[NSLocalizedString(@"OK", @"OK")]);
                    
                    self.profileNameLabel.stringValue = @"";
                    goto bail;
                }
            }
            
            //save name
            self.profileName = self.profileNameLabel.stringValue;
            
            //remove current view
            [self.currentProfileSubview removeFromSuperview];
            
            //update: which networks this profile should adopt comes before what it does
            self.currentProfileSubview = [self networkConditionsPageView];
            
            //add to the sheet
            [self.addProfileSheet.contentView addSubview:self.currentProfileSubview positioned:NSWindowBelow relativeTo:nil];
            
            //make next button first responder
            [self.addProfileSheet makeFirstResponder:self.continueProfileButton];
            
            //update tag
            self.continueProfileButton.tag = profileConditions;
            
            break;
        }
            
        //current view: network conditions
        // setup next view: rules
        case profileConditions:
        {
            //what the user wrote down, in the form a profile stores
            // note: an empty list is left out entirely, which is what makes the profile
            //       apply whatever the network is
            NSArray* conditions = [self.networkConditionsPage editedConditionSets];
            
            if(0 != conditions.count)
            {
                self.profilePreferences[KEY_CONDITIONS] = conditions;
            }
            else
            {
                [self.profilePreferences removeObjectForKey:KEY_CONDITIONS];
            }
            
            //remove current view
            [self.currentProfileSubview removeFromSuperview];
            
            //update
            self.currentProfileSubview = self.rulesView;
            
            //hide 'show buttons'
            self.showRulesButton.hidden = YES;
            
            //add to rule's view
            [self.addProfileSheet.contentView addSubview:self.currentProfileSubview positioned:NSWindowBelow relativeTo:nil];
            
            //make next button first responder
            [self.addProfileSheet makeFirstResponder:self.continueProfileButton];
            
            //update tag
            self.continueProfileButton.tag = profileRules;
            
            break;
        }
            
        //current view: rules
        // setup next view: modes
        case profileRules:
            
            //remove current view
            [self.currentProfileSubview removeFromSuperview];
            
            //update
            self.currentProfileSubview = self.modesView;
            
            //add to mode's view
            [self.addProfileSheet.contentView addSubview:self.currentProfileSubview positioned:NSWindowBelow relativeTo:nil];
            
            //make next button first responder
            [self.addProfileSheet makeFirstResponder:self.continueProfileButton];
            
            //update tag
            self.continueProfileButton.tag = profileModes;
            
            break;
        
        //current view: modes
        // setup next view: lists
        case profileModes:
            
            //remove current view
            [self.currentProfileSubview removeFromSuperview];
            
            //update
            self.currentProfileSubview = self.listsView;
            
            //add to list's view
            [self.addProfileSheet.contentView addSubview:self.currentProfileSubview positioned:NSWindowBelow relativeTo:nil];
            
            //make next button first responder
            [self.addProfileSheet makeFirstResponder:self.continueProfileButton];
            
            //update tag
            self.continueProfileButton.tag = profileLists;
            
            break;
        
        //current view: lists
        // setup next view: updates
        case profileLists:
            
            //remove current view
            [self.currentProfileSubview removeFromSuperview];
            
            //update
            self.currentProfileSubview = self.updateView;
            
            //hide button
            self.updateButton.hidden = YES;
            
            //unset label
            self.updateLabel.stringValue = @"";
            
            //add to mode's view
            [self.addProfileSheet.contentView addSubview:self.currentProfileSubview positioned:NSWindowBelow relativeTo:nil];
            
            //make next button first responder
            [self.addProfileSheet makeFirstResponder:self.continueProfileButton];
            
            //update tag
            self.continueProfileButton.tag = profileUpdates;
            
            //update button name to "Add Profile"
            self.continueProfileButton.title = NSLocalizedString(@"Add Profile", @"Add Profile");
            
            break;
            
        //current view: updates
        // add profile as this is the last one!
        case profileUpdates:
            
            //end with 'ok'
            [self.window endSheet:self.addProfileSheet returnCode:NSModalResponseOK];
            
        default:
            break;
    }
    
    //uncheck all checks buttons (might be set from current preferences)
    for (NSView *subview in self.currentProfileSubview.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)subview;
            // Uncheck only if the button has a toggleable state
                if (button.allowsMixedState || button.state != NSControlStateValueOff) {
                    button.state = NSControlStateValueOff;
                }
        }
    }
    
    //update view's fame
    NSRect bounds = self.addProfileSheet.contentView.bounds;
    NSRect frame = self.currentProfileSubview.frame;
    frame.origin.x  = 0;
    frame.origin.y  = bounds.size.height - frame.size.height;
    
    //set frame
    self.currentProfileSubview.frame = frame;
    
bail:

    return;
}

@end
