#import <Cocoa/Cocoa.h>

// MARK: - KubeContext Model

@interface KubeContext : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *clusterServer;
@property (nonatomic, assign) BOOL isLocal;
@end

@implementation KubeContext
@end

// MARK: - App Delegate

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSString *lastContext;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    [self refreshMenu];

    // Poll for changes every 2 seconds
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                  target:self
                                                selector:@selector(checkForChanges)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
}

- (void)checkForChanges {
    NSString *currentContext = [self getCurrentContext];
    if (currentContext && ![currentContext isEqualToString:self.lastContext]) {
        [self refreshMenu];
    }
}

- (void)refreshMenu {
    NSString *currentContext = [self getCurrentContext];
    if (!currentContext || currentContext.length == 0) {
        [self updateStatusTitle:@"k8s: none" isLocal:YES];
        return;
    }

    self.lastContext = currentContext;

    NSArray<KubeContext *> *contexts = [self getContexts];
    BOOL isLocal = NO;

    for (KubeContext *ctx in contexts) {
        if ([ctx.name isEqualToString:currentContext]) {
            isLocal = ctx.isLocal;
            break;
        }
    }

    NSString *displayName = [self truncate:currentContext maxLen:10];
    [self updateStatusTitle:displayName isLocal:isLocal];
    [self buildMenu:contexts currentContext:currentContext];
}

- (void)updateStatusTitle:(NSString *)title isLocal:(BOOL)isLocal {
    NSStatusBarButton *button = self.statusItem.button;
    if (!button) return;

    NSString *icon = isLocal ? @"⬡" : @"🔴";
    NSString *fullTitle = [NSString stringWithFormat:@"%@ %@", icon, title];

    if (!isLocal) {
        // Make text red for non-local clusters
        NSDictionary *attributes = @{
            NSForegroundColorAttributeName: [NSColor systemRedColor],
            NSFontAttributeName: [NSFont menuBarFontOfSize:0]
        };
        button.attributedTitle = [[NSAttributedString alloc] initWithString:fullTitle
                                                                 attributes:attributes];
    } else {
        button.title = fullTitle;
    }
}

- (void)buildMenu:(NSArray<KubeContext *> *)contexts currentContext:(NSString *)currentContext {
    NSMenu *menu = [[NSMenu alloc] init];

    // Header
    NSMenuItem *headerItem = [[NSMenuItem alloc] initWithTitle:@"Kubernetes Contexts"
                                                        action:nil
                                                 keyEquivalent:@""];
    [headerItem setEnabled:NO];
    [menu addItem:headerItem];
    [menu addItem:[NSMenuItem separatorItem]];

    // Context items
    for (KubeContext *context in contexts) {
        BOOL isCurrent = [context.name isEqualToString:currentContext];
        NSString *displayName = [self truncate:context.name maxLen:40];
        NSString *title = isCurrent ?
            [NSString stringWithFormat:@"✓ %@", displayName] :
            [NSString stringWithFormat:@"   %@", displayName];

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(contextSelected:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = context.name;
        item.toolTip = context.name;

        // Mark non-local with a red dot in the menu
        if (!context.isLocal) {
            item.image = [self redDotImage];
        }

        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Kubebar"
                                                      action:@selector(quitApp)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (NSImage *)redDotImage {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
    [image lockFocus];
    [[NSColor systemRedColor] setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 8, 8)];
    [path fill];
    [image unlockFocus];
    [image setTemplate:NO];
    return image;
}

- (void)contextSelected:(NSMenuItem *)sender {
    NSString *contextName = sender.representedObject;
    if (contextName) {
        [self switchContext:contextName];
        [self refreshMenu];
    }
}

- (void)quitApp {
    [NSApp terminate:nil];
}

// MARK: - kubectl helpers

- (NSString *)runKubectl:(NSArray<NSString *> *)args {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];

    NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:@"kubectl"];
    [fullArgs addObjectsFromArray:args];
    task.arguments = fullArgs;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];

    NSError *error;
    [task launchAndReturnError:&error];
    if (error) return nil;

    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)getCurrentContext {
    return [self runKubectl:@[@"config", @"current-context"]];
}

- (NSArray<KubeContext *> *)getContexts {
    NSString *contextList = [self runKubectl:@[@"config", @"get-contexts", @"-o", @"name"]];
    if (!contextList || contextList.length == 0) return @[];

    NSArray *names = [contextList componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<KubeContext *> *contexts = [NSMutableArray array];

    for (NSString *name in names) {
        if (name.length == 0) continue;

        KubeContext *ctx = [[KubeContext alloc] init];
        ctx.name = name;

        // Get the cluster server for this context
        NSString *clusterName = [self runKubectl:@[
            @"config", @"view", @"-o",
            [NSString stringWithFormat:@"jsonpath={.contexts[?(@.name==\"%@\")].context.cluster}", name]
        ]];

        if (clusterName && clusterName.length > 0) {
            NSString *server = [self runKubectl:@[
                @"config", @"view", @"-o",
                [NSString stringWithFormat:@"jsonpath={.clusters[?(@.name==\"%@\")].cluster.server}", clusterName]
            ]];

            ctx.clusterServer = server;
            ctx.isLocal = [self isLocalServer:server];
        } else {
            ctx.isLocal = NO;
        }

        [contexts addObject:ctx];
    }

    return contexts;
}

- (BOOL)isLocalServer:(NSString *)server {
    if (!server || server.length == 0) return NO;

    NSString *lowerServer = [server lowercaseString];
    NSArray *localPatterns = @[
        @"localhost",
        @"127.0.0.1",
        @"0.0.0.0",
        @"host.docker.internal",
        @"kubernetes.docker.internal"
    ];

    for (NSString *pattern in localPatterns) {
        if ([lowerServer containsString:pattern]) {
            return YES;
        }
    }

    return NO;
}

- (void)switchContext:(NSString *)contextName {
    [self runKubectl:@[@"config", @"use-context", contextName]];
}

- (NSString *)truncate:(NSString *)string maxLen:(NSInteger)maxLen {
    if (string.length <= maxLen) {
        return string;
    }
    return [[string substringToIndex:maxLen - 1] stringByAppendingString:@"…"];
}

@end

// MARK: - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
