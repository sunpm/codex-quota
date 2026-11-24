#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <string.h>

static id attribute(id node, NSString *name) {
    CFTypeRef value = NULL;
    AXUIElementCopyAttributeValue((__bridge AXUIElementRef)node, (__bridge CFStringRef)name, &value);
    return CFBridgingRelease(value);
}

static NSString *textValue(id node) {
    for (NSString *key in @[@"AXTitle", @"AXDescription", @"AXValue"]) {
        id value = attribute(node, key);
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return nil;
}

static id refreshButton(id node) {
    NSString *role = attribute(node, @"AXRole");
    if ([role isEqualToString:@"AXWebArea"]) {
        NSDictionary *query = @{@"AXSearchKey": @"AXButtonSearchKey",
                                @"AXSearchText": @"Refresh quota and credits data"};
        CFTypeRef buttons = NULL;
        AXUIElementCopyParameterizedAttributeValue((__bridge AXUIElementRef)node,
            CFSTR("AXUIElementsForSearchPredicate"), (__bridge CFTypeRef)query, &buttons);
        for (id button in CFBridgingRelease(buttons)) {
            if ([textValue(button) isEqualToString:@"Refresh quota and credits data"]) return button;
        }
        return nil;
    }
    for (id child in attribute(node, @"AXChildren")) {
        id found = refreshButton(child);
        if (found) return found;
    }
    return nil;
}

static NSString *headingText(id heading) {
    NSString *name = textValue(heading);
    if (name) return name;
    for (id child in attribute(heading, @"AXChildren")) {
        name = headingText(child);
        if (name) return name;
    }
    return nil;
}

static void collect(id node, NSMutableArray *items, BOOL *hasSection) {
    NSString *role = attribute(node, @"AXRole");
    if ([role isEqualToString:@"AXHeading"]) {
        NSString *name = headingText(node);
        if (name) {
            [items addObject:@{@"heading": name}];
            *hasSection = YES;
        }
    } else if ([role isEqualToString:@"AXStaticText"]) {
        NSString *text = textValue(node);
        if (text) [items addObject:@{@"text": text}];
    } else if ([role isEqualToString:@"AXGroup"] || [role isEqualToString:@"AXScrollArea"]
               || [role isEqualToString:@"AXList"] || [role isEqualToString:@"AXSection"]) {
        for (id child in attribute(node, @"AXChildren")) collect(child, items, hasSection);
    }
}

// Settings renders its quota groups as siblings after the header containing the refresh button.
static NSArray *sectionsFollowing(id header) {
    for (id node = header; node; ) {
        id parent = attribute(node, @"AXParent");
        if (!parent) break;
        NSArray *siblings = attribute(parent, @"AXChildren");
        NSUInteger index = siblings ? [siblings indexOfObject:node] : NSNotFound;
        if (index == NSNotFound) break;
        NSMutableArray *items = [NSMutableArray array];
        BOOL hasSection = NO;
        for (NSUInteger i = index + 1; i < siblings.count; ++i) collect(siblings[i], items, &hasSection);
        if (hasSection) return items;
        NSString *role = attribute(parent, @"AXRole");
        if ([role isEqualToString:@"AXWebArea"] || [role isEqualToString:@"AXWindow"]) break;
        node = parent;
    }
    return @[];
}

int cq_read_antigravity_panel(char **json) {
    @autoreleasepool {
        NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.google.antigravity"];
        if (!apps.count) return 2;
        if (!AXIsProcessTrusted()) return 1;
        for (NSRunningApplication *app in apps) {
            id root = CFBridgingRelease(AXUIElementCreateApplication(app.processIdentifier));
            AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)root, 1.0);
            // Electron lazily instantiates its accessibility tree for assistive clients.
            AXUIElementSetAttributeValue((__bridge AXUIElementRef)root, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
            for (id window in attribute(root, @"AXWindows")) {
                if ([attribute(window, @"AXMinimized") boolValue]) continue;
                id button = refreshButton(window);
                if (!button) continue;
                NSData *data = [NSJSONSerialization dataWithJSONObject:sectionsFollowing(button) options:0 error:NULL];
                NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (!result) return 3;
                *json = strdup(result.UTF8String);
                return *json ? 0 : 3;
            }
        }
        return 2;
    }
}
