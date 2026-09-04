//
//  main.m
//  GameLink
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

#define SDL_MAIN_HANDLED
#import <SDL.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        SDL_SetMainReady();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
