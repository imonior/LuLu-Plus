//
//  file: PrefsWindowController+Private.h
//  project: LuLu_Plus
//  description: what the files making up PrefsWindowController share
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "PrefsWindowController.h"

/* note: the add-profile wizard lives in its own file now; it is the same class, so the sheet's
   buttons still find their handler, and nothing about the window's behaviour changed */

/* note: the language tab lives in PrefsWindowController+Language.m, and builds its view in code
   rather than in the nib - it is the one pane whose contents come from the shipping languages */

@interface PrefsWindowController (Language)

//build the language tab's view and its controls
-(void)buildLanguageView;

//reflect the stored pick in the language tab
-(void)refreshLanguageView;

@end

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//xpc for daemon comms
extern XPCDaemonClient* xpcDaemonClient;
