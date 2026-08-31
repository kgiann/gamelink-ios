//
//  AppDelegate.m
//  GameLink
//

#import "AppDelegate.h"

@implementation AppDelegate

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

#if TARGET_OS_TV
static NSString* DB_NAME = @"GameLink_tvOS.bin";
#else
static NSString* DB_NAME = @"GameLink_iOS.sqlite";
#endif

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [self saveContext];
}

- (void)saveContext {
    NSManagedObjectContext *managedObjectContext = [self managedObjectContext];
    if (managedObjectContext == nil) {
        return;
    }

    // Save synchronously so the tvOS NSUserDefaults backup below reflects the
    // committed store. (The Caches copy can be purged, so NSUserDefaults is the
    // only durable location on tvOS.)
    [managedObjectContext performBlockAndWait:^{
        if (![managedObjectContext hasChanges]) {
            return;
        }
        NSError *error = nil;
        if (![managedObjectContext save:&error]) {
            Log(LOG_E, @"Critical database error: %@, %@", error, [error userInfo]);
        }

#if TARGET_OS_TV
        NSData* dbData = [NSData dataWithContentsOfURL:[self getStoreURL]];
        if (dbData != nil) {
            [[NSUserDefaults standardUserDefaults] setObject:dbData forKey:DB_NAME];
            // Flush immediately; tvOS may suspend/kill us right after leaving a screen.
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
#endif
    }];
}

- (NSManagedObjectContext *)managedObjectContext {
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return _managedObjectContext;
}

- (NSManagedObjectModel *)managedObjectModel {
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    _managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    NSDictionary *options = @{
        NSMigratePersistentStoresAutomaticallyOption: @YES,
        NSInferMappingModelAutomaticallyOption: @YES
    };

#if TARGET_OS_TV
    NSString* storeType = NSBinaryStoreType;
#else
    NSString* storeType = NSSQLiteStoreType;
#endif

    // Ensure the store is ready to open (tvOS may need to inflate it from NSUserDefaults)
    [self preparePersistentStore];

    if (![_persistentStoreCoordinator addPersistentStoreWithType:storeType
                                                   configuration:nil
                                                             URL:[self getStoreURL]
                                                         options:options
                                                           error:&error]) {
        Log(LOG_E, @"Critical database error: %@, %@", error, [error userInfo]);
        [self dropDatabase];
        return [self persistentStoreCoordinator];
    }
    return _persistentStoreCoordinator;
}

- (NSURL *)applicationDocumentsDirectory {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (void)preparePersistentStore {
#if TARGET_OS_TV
    NSString* dbPath = [[self getStoreURL] path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        NSData* data = [[NSUserDefaults standardUserDefaults] dataForKey:DB_NAME];
        if (data != nil) {
            Log(LOG_I, @"Inflating database from NSUserDefaults");
            [data writeToFile:dbPath atomically:YES];
        }
    }
#endif
}

- (void)dropDatabase {
    [[NSFileManager defaultManager] removeItemAtURL:[self getStoreURL] error:nil];
#if TARGET_OS_TV
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:DB_NAME];
#endif
}

- (NSURL *)getStoreURL {
#if TARGET_OS_TV
    return [[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:DB_NAME];
#else
    return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:DB_NAME];
#endif
}

@end
