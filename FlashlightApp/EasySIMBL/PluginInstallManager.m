//
//  PluginInstallManager.m
//  Flashlight
//
//  Created by Nate Parrott on 3/24/15.
//
//

#import "PluginInstallManager.h"
#import "PluginInstallTask.h"
#import "PluginModel.h"

NSString *PluginInstallManagerDidUpdatePluginStatusesNotification = @"PluginInstallManagerDidUpdatePluginStatusesNotification";
NSString *PluginInstallManagerSetOfInstalledPluginsChangedNotification = @"PluginInstallManagerSetOfInstalledPluginsChangedNotification";

@interface PluginInstallManager ()

@property (nonatomic) NSSet *installTasksInProgress;

@end

@implementation PluginInstallManager

+ (PluginInstallManager *)shared {
    static PluginInstallManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [PluginInstallManager new];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    self.installTasksInProgress = [NSSet new];
    return self;
}

#pragma mark (Un)?installation
- (BOOL)isPluginCurrentlyBeingInstalled:(PluginModel *)plugin {
    for (PluginInstallTask *task in self.installTasksInProgress) {
        if ([task.plugin.name isEqualToString:plugin.name]) {
            return YES;
        }
    }
    return NO;
}

- (void)installPlugin:(PluginModel *)plugin {
    [self installPlugin:plugin callback:^(BOOL success, NSError *error) {
        if (!success) {
            NSAlert *alert;
            if (error) {
                alert = [NSAlert alertWithError:error];
            } else {
                alert = [[NSAlert alloc] init];
                [alert setMessageText:NSLocalizedString(@"Couldn't install plugin.", @"")];
                [alert addButtonWithTitle:NSLocalizedString(@"Okay", @"")];
            }
            alert.alertStyle = NSWarningAlertStyle;
            [alert runModal];
        }
    }];
}

- (void)installPlugin:(PluginModel *)plugin callback:(void(^)(BOOL success, NSError *error))callback {
    if ([self isPluginCurrentlyBeingInstalled:plugin]) return;
    
    NSLog(@"Installing plugin: %@", plugin.name);
    
    PluginInstallTask *task = [[PluginInstallTask alloc] initWithPlugin:plugin];
    self.installTasksInProgress = self.installTasksInProgress ? [self.installTasksInProgress setByAddingObject:task] : [NSSet setWithObject:task];
    [[NSNotificationCenter defaultCenter] postNotificationName:PluginInstallManagerDidUpdatePluginStatusesNotification object:self];
    [task startInstallationIntoPluginsDirectory:[PluginModel pluginsDir] withCallback:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"Successfully installed plugin: %@", plugin.name);
        } else {
            NSLog(@"Failed to install plugin: %@", plugin.name);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableSet *tasks = self.installTasksInProgress.mutableCopy;
            [tasks removeObject:task];
            [self clearNLPModelCache];
            self.installTasksInProgress = tasks;
            [[NSNotificationCenter defaultCenter] postNotificationName:PluginInstallManagerSetOfInstalledPluginsChangedNotification object:self];
            callback(success, error);
        });
    }];
}
- (void)uninstallPlugin:(PluginModel *)plugin {
    if ([self isPluginCurrentlyBeingInstalled:plugin]) return;
    
    NSString *path = [[PluginModel pluginsDir] stringByAppendingPathComponent:[plugin.name stringByAppendingPathExtension:@"bundle"]];
    NSString *disabledPath = [[PluginModel pluginsDir] stringByAppendingPathComponent:[plugin.name stringByAppendingPathExtension:@"disabled-bundle"]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:disabledPath isDirectory:nil]) {
        [[NSFileManager defaultManager] removeItemAtPath:disabledPath error:nil];
    }
    [[NSFileManager defaultManager] moveItemAtPath:path toPath:disabledPath error:nil];
    [self clearNLPModelCache];
    [[NSNotificationCenter defaultCenter] postNotificationName:PluginInstallManagerSetOfInstalledPluginsChangedNotification object:nil];
}
- (void)clearNLPModelCache {
    // TODO: get FlashlightKit to clear its cache somehow
}

@end
