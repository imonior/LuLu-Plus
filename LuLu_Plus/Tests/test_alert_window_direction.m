//
//  file: test_alert_window_direction.m
//  project: LuLu_Plus (tests)
//  description: loads the alert window the app ships, feeds it an outbound and an inbound flow,
//               and checks what the user is told and what the app hands back to the extension
//
//  usage: test_alert_window_direction <path/to/AlertWindow.nib> <language>
//

@import Cocoa;
@import OSLog;
#import <sys/socket.h>

#import "consts.h"
#import "XPCDaemonClient.h"
#import "AlertWindowController.h"

/* GLOBALS (the ones AlertWindowController.m expects) */

os_log_t logHandle = NULL;
XPCDaemonClient* xpcDaemonClient = nil;
NSMutableDictionary* alerts = nil;

//language the run is testing
static NSString* gLanguage = nil;

static int gFailures = 0;

static void check(const char* what, BOOL condition)
{
    printf("  [%s] %s\n", condition ? "ok  " : "FAIL", what);
    if(YES != condition) gFailures++;
}

static NSString* cstr(id value)
{
    if(nil == value) return @"(nil)";
    if([value isKindOfClass:NSString.class]) return value;
    return [value description];
}

//an alert as the extension would deliver it
// note: pid is this test's own pid, so the app's (real) process-hierarchy code has a live
//       process to walk and doesn't take the exited-process branch
static NSMutableDictionary* alertFor(NSInteger direction)
{
    return [@{KEY_UUID:[NSUUID UUID].UUIDString,
              KEY_KEY:@"/usr/bin/whoever",
              KEY_PROCESS_ID:@((int)getpid()),
              KEY_PROCESS_NAME:@"whoever",
              KEY_PATH:@"/usr/bin/whoever",
              KEY_PROCESS_ARGS:@[@"/usr/bin/whoever", @"--flag"],
              KEY_HOST:(TrafficDirectionInbound == direction) ? @"192.168.1.50" : @"203.0.113.7",
              KEY_ENDPOINT_PORT:(TrafficDirectionInbound == direction) ? @"548" : @"443",
              KEY_PROTOCOL:@(IPPROTO_TCP),
              KEY_DIRECTION:@(direction)} mutableCopy];
}

//load the alert window for `alert`, letting the controller run its real -windowDidLoad
static AlertWindowController* loaded(NSDictionary* alert)
{
    NSString* nibPath = [NSProcessInfo.processInfo.arguments objectAtIndex:1];

    AlertWindowController* controller = [[AlertWindowController alloc] init];
    controller = [controller initWithWindowNibPath:nibPath owner:controller];

    //set before touching -window, which is what loads the nib
    controller.alert = alert;

    NSWindow* window = controller.window;
    if(nil == window)
    {
        check("alert window loaded from the nib", NO);
        return nil;
    }

    return controller;
}

//every view below `views`, depth first
static NSArray<NSView*>* collectViews(NSArray<NSView*>*views)
{
    NSMutableArray* all = [NSMutableArray array];

    for(NSView* view in views)
    {
        [all addObject:view];
        [all addObjectsFromArray:collectViews(view.subviews)];
    }

    return all;
}

//the wording the alert is expected to use, per language the fork translates
// note: keyed off the message the app builds - 'is connecting to X' / 'is being connected to from X'
static NSString* expectedOutbound(void)
{
    NSDictionary* table = @{@"en":@"is connecting to",
                            @"zh-Hans":@"正在连接到",
                            @"zh-Hant":@"正在連線至"};

    return table[gLanguage] ?: table[@"en"];
}

static NSString* expectedInbound(void)
{
    NSDictionary* table = @{@"en":@"is being connected to from",
                            @"zh-Hans":@"正在接收来自",
                            @"zh-Hant":@"正在接收來自"};

    return table[gLanguage] ?: table[@"en"];
}

/* CASES */

static void testOutbound(void)
{
    NSMutableDictionary* alert = alertFor(TrafficDirectionOutbound);
    AlertWindowController* controller = loaded(alert);
    if(nil == controller) return;

    NSString* message = controller.alertMessage.string;

    check("outbound: describes the mac reaching out",
          (nil != message) && (NSNotFound != [message rangeOfString:expectedOutbound()].location));
    check("outbound: names the endpoint it reached",
          (nil != message) && (NSNotFound != [message rangeOfString:@"203.0.113.7"].location));
    check("outbound: is NOT worded as an inbound connection",
          (nil == message) || (YES != [message containsString:expectedInbound()]));
    check("outbound: message came from the string catalog, not a raw key",
          (nil != message) && (YES != [message containsString:@"%@"]));

    //the details the user checks the prompt against
    check("outbound: shows the remote address",
          (nil != controller.ipAddress) && (0 == [controller.ipAddress.stringValue compare:@"203.0.113.7"]));
    check("outbound: shows the destination port",
          (nil != controller.portProto) && (NSNotFound != [controller.portProto.stringValue rangeOfString:@"443"].location));

    [controller.window close];
    controller = nil;
}

static void testInbound(void)
{
    //response the app hands back to the extension
    __block NSDictionary* response = nil;

    NSMutableDictionary* alert = alertFor(TrafficDirectionInbound);
    AlertWindowController* controller = loaded(alert);
    if(nil == controller) return;

    NSString* message = controller.alertMessage.string;

    check("inbound: says a peer is connecting in, not that this mac reached out",
          (nil != message) && (NSNotFound != [message rangeOfString:expectedInbound()].location));
    check("inbound: names the peer",
          (nil != message) && (NSNotFound != [message rangeOfString:@"192.168.1.50"].location));
    check("inbound: is NOT worded as this mac reaching out",
          (nil == message) || (YES != [message containsString:expectedOutbound()]));
    check("inbound: message came from the string catalog, not a raw key",
          (nil != message) && (YES != [message containsString:@"%@"]));

    check("inbound: shows the peer as the address",
          (nil != controller.ipAddress) && (0 == [controller.ipAddress.stringValue compare:@"192.168.1.50"]));
    check("inbound: shows the port being listened on",
          (nil != controller.portProto) && (NSNotFound != [controller.portProto.stringValue rangeOfString:@"548"].location));

    //and what the user's answer turns into
    controller.reply = ^(NSDictionary* reply){ response = reply; };

    NSButton* allow = controller.allowButton;
    if(nil == allow)
    {
        check("inbound: allow button is wired up", NO);
        return;
    }

    check("inbound: allow button is tagged 'allow'", (1 == allow.tag));

    [controller handleUserResponse:allow];

    if(nil == response)
    {
        check("inbound: user's response reached the extension", NO);
        return;
    }

    check("inbound: response is an allow", (RULE_STATE_ALLOW == [cstr(response[KEY_ACTION]) integerValue]));
    check("inbound: response keeps the inbound direction, so the rule it creates is inbound",
          (TrafficDirectionInbound == [response[KEY_DIRECTION] integerValue]));
    check("inbound: rule endpoint is the peer",
          (0 == [cstr(response[KEY_ENDPOINT_ADDR]) compare:@"192.168.1.50"]));
    check("inbound: rule port is the port that was reached",
          (0 == [cstr(response[KEY_ENDPOINT_PORT]) compare:@"548"]));
    check("inbound: response is a user-created rule",
          (RULE_TYPE_USER == [response[KEY_TYPE] integerValue]));
}

static void testInboundBlock(void)
{
    __block NSDictionary* response = nil;

    AlertWindowController* controller = loaded(alertFor(TrafficDirectionInbound));
    if(nil == controller) return;

    controller.reply = ^(NSDictionary* reply){ response = reply; };

    //any button tagged 'block' (0)
    NSButton* block = nil;
    for(NSView* view in collectViews(@[controller.window.contentView]))
    {
        if(YES != [view isKindOfClass:NSButton.class]) continue;
        if(0 == ((NSButton*)view).tag && (NSNotFound != [((NSButton*)view).title rangeOfString:@"lock"].location))
        {
            block = (NSButton*)view;
            break;
        }
    }

    if(nil == block)
    {
        check("inbound: block button found", NO);
        return;
    }

    [controller handleUserResponse:block];

    check("inbound: block response is a block", (RULE_STATE_BLOCK == [cstr(response[KEY_ACTION]) integerValue]));
    check("inbound: block response is still an inbound rule",
          (TrafficDirectionInbound == [response[KEY_DIRECTION] integerValue]));
}

/* MAIN */

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        if(argc < 3)
        {
            fprintf(stderr, "usage: %s <AlertWindow.nib> <language>\n", argv[0]);
            return 2;
        }

        logHandle = os_log_create("com.imonior.lulu-plus", "tests");
        alerts = [NSMutableDictionary dictionary];

        gLanguage = [@(argv[2]) copy];

        //pick the language in-process: the environment is only honored by a launched app
        [[NSUserDefaults standardUserDefaults] setObject:@[gLanguage, @"en"] forKey:@"AppleLanguages"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        printf("== alert window direction (%s) ==\n", gLanguage.UTF8String);

        testOutbound();
        testInbound();
        testInboundBlock();

        printf("\n%s: %d failure(s)\n", (0 == gFailures) ? "RESULT: pass" : "RESULT: fail", gFailures);
    }

    return (0 == gFailures) ? 0 : 1;
}
