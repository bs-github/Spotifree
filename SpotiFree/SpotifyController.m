//
//  SpotifyController.m
//  SpotiFree
//
//  Created by Eneas on 21.12.13.
//  Copyright (c) 2013 Eneas. All rights reserved.
//

#import "SpotifyController.h"
#import "Spotify.h"
#import "AppData.h"
#import "AppDelegate.h"
#import "FileHash.h"

#define SPOTIFY_BUNDLE_IDENTIFIER @"com.spotify.client"

@interface SpotifyController ()

@property (strong) SpotifyApplication *spotify;
@property (strong) AppData *appData;
@property (assign) NSInteger currentVolume;
@property (assign) BOOL adPlaying;

@property (assign) BOOL shouldRun;

@end

@implementation SpotifyController

#pragma mark -
#pragma mark Initialisation
+ (id)spotifyController {
    return [[self alloc] init];
}

- (id)init
{
    self = [super init];

    if (self) {
        self.spotify = [SBApplication applicationWithBundleIdentifier:SPOTIFY_BUNDLE_IDENTIFIER];
        self.appData = [AppData sharedData];
        
        [self fixSpotifyIfNecessary];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidLaunchApplicationNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if ([note.userInfo[@"NSApplicationName"] isEqualToString:@"Spotify"]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self fixSpotifyIfNecessary];
                });
            }
        }];
        
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStateChanged:) name:@"com.spotify.client.PlaybackStateChanged" object:nil];
    }

    return self;
}

#pragma mark -
#pragma mark Public Methods
- (void)firstAdCheck {
    if (self.spotify.isRunning && self.spotify.playerState == SpotifyEPlSPlaying && [self.spotify.currentTrack.spotifyUrl hasPrefix:@"spotify:ad"]) {
        [self mute];
    } else {
        [self updateAdState:NO];
    }
}

#pragma mark -
#pragma mark Notifications

- (void)playbackStateChanged:(NSNotification *)notification {
    NSString *playerState = notification.userInfo[@"Player State"];
    NSString *trackID = notification.userInfo[@"Track ID"];
    
    if (!self.adPlaying && [trackID hasPrefix:@"spotify:ad"]) {
        [self mute];
    }
    if (self.adPlaying && [playerState isEqualToString:@"Stopped"]) {
        [self updateAdState:NO];
    }
    if (self.adPlaying && ![trackID hasPrefix:@"spotify:ad"]) {
        [self unmute];
    }
}

#pragma mark -
#pragma mark Player Control Methods
- (void)mute {
    [self updateAdState:YES];
    
    self.currentVolume = self.spotify.soundVolume;
    [self.spotify pause];
    [self.spotify setSoundVolume:0];
    [self.spotify play];

	if (self.appData.shouldShowNotifications) {
		NSUserNotification *notification = [[NSUserNotification alloc] init];
		[notification setTitle:@"Spotifree"];
		[notification setInformativeText:[NSString stringWithFormat:@"A Spotify ad was detected! Music will be back in about %ld seconds…", (long)self.spotify.currentTrack.duration]];
		[notification setSoundName:nil];

		[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
	}
}

- (void)unmute {
    [self updateAdState:NO];
    
    [self.spotify setSoundVolume:self.currentVolume];
}

- (void)updateAdState:(BOOL)ad {
    self.adPlaying = ad;
    ad ? [self.delegate activeStateShouldGetUpdated:kSFSpotifyStateBlockingAd] : [self.delegate activeStateShouldGetUpdated:kSFSpotifyStateActive];
}

#pragma mark -
#pragma mark Modifying Spotify
- (void)fixSpotifyIfNecessary {
    BOOL fixedScriptingDefinitonFile = [self fixScriptingDefinitionFileIfNecessary];
    BOOL patchedSpotify = [self patchSpotifyIfNecessary];
    
    if (!patchedSpotify && !fixedScriptingDefinitonFile)
        return;
    
    if (self.spotify.isRunning) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Spotify restart required" defaultButton:@"OK" alternateButton:@"I'll do it myself" otherButton:nil informativeTextWithFormat:@"Sorry to interrupt, but your Spotify app must be restarted to work with Spotifree. You can do it now or later, manually, if you'd rather enjoy that last McDonald's ad."];
        [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:"fixAlert"];
    }
}

- (BOOL)fixScriptingDefinitionFileIfNecessary {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *spotifyResourceFolder = [[[[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.spotify.client"] path] stringByAppendingString:@"/Contents/Resources/"];
    NSString *rightFile = [spotifyResourceFolder stringByAppendingString:@"Spotify.sdef"];
    
    if ([manager fileExistsAtPath:rightFile])
        return FALSE;
    
    NSString *wrongFile = [spotifyResourceFolder stringByAppendingString:@"applescript/Spotify.sdef"];
    [manager copyItemAtPath:wrongFile toPath:rightFile error:nil];
    
    return TRUE;
}

- (BOOL)patchSpotifyIfNecessary {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *spotifyMacOSFolder = [[[[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.spotify.client"] path] stringByAppendingString:@"/Contents/MacOS/"];
    NSString *originalFile = [spotifyMacOSFolder stringByAppendingString:@"Spotify"];
    
    NSDictionary *patches = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"patches" ofType:@"plist"]];
    NSDictionary *currentPatch = patches[[FileHash md5HashOfFileAtPath:(originalFile)]];
    
    if (!currentPatch) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Spotify not supported" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Sorry, but your Spotify version is currently not supported."];
        [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:nil contextInfo:nil];
        return FALSE;
    }
    if ([currentPatch[@"patched"] boolValue]) {
        return FALSE;
    }
    
    NSString *backupFile = [spotifyMacOSFolder stringByAppendingString:@"SpotifyBackup"];
    [manager copyItemAtPath:originalFile toPath:backupFile error:nil];
    
    NSData *data = [NSData dataWithContentsOfFile:originalFile];
    uint8_t *bytes = (uint8_t *)[data bytes];
    
    for (NSDictionary *patch in currentPatch[@"patchData"]) {
        int offset = [patch[@"offset"] intValue];
        uint8_t data = [patch[@"data"] intValue];
        
        bytes[offset] = data;
    }
    
    [data writeToFile:originalFile atomically:YES];
    
    return TRUE;
}

#pragma mark -
#pragma mark NSAlertModalDelegate
- (void) alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == 1) {
        if (strcmp(contextInfo, "fixAlert") == 0) {
            NSRunningApplication *spotify = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.spotify.client"] firstObject];
            [spotify terminate];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[NSWorkspace sharedWorkspace] launchApplication:@"Spotify"];
            });
        }
    }
}


- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

@end
