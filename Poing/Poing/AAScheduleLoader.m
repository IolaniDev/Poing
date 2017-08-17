//
//  AADataLoader.m
//  Poing
//
//  Created by Kyle Oba on 12/14/13.
//  Copyright (c) 2013 AgencyAgency. All rights reserved.
//

#import "AAScheduleLoader.h"
#import "Bell+Create.h"
#import "Cycle+Create.h"
#import "Period+Create.h"
#import "SchoolDay+Create.h"
#import "BellCycle+Create.h"
#import "BellCyclePeriod+Create.h"
#import "BellCyclePeriod+Info.h"
#import "SchoolDay+Info.h"
#import <CoreData/CoreData.h>
#import <Parse/PFCloud.h>
#import <Parse/PFQuery.h>
#import <Parse/PFConfig.h>

#define BELL_ASSEMBLY_1 @"Assembly 1 Schedule"
#define BELL_ASSEMBLY_3 @"Assembly 3 Schedule"
#define BELL_BASIC @"Basic Schedule"
#define BELL_CHAPEL @"Chapel Schedule"
#define BELL_SPECIAL_FAIR_DAY @"Special Fair Day Schedule"
#define BELL_ATHLETIC_ASSEMBLY @"Athletic Assembly Schedule"
#define BELL_SCHEDULE_A @"A Schedule"
#define BELL_SCHEDULE_B @"B Schedule"
#define BELL_SCHEDULE_C @"C Schedule"
#define BELL_SCHEDULE_D @"D Schedule"
#define BELL_SCHEDULE_E @"E Schedule"
#define BELL_SCHEDULE_F @"F Schedule"
#define BELL_ASSEMBLY_E1 @"E1 Schedule"
#define BELL_ASSEMBLY_F1 @"F1 Schedule"
#define BELL_ASSEMBLY_E2 @"E2 Schedule"
#define BELL_ASSEMBLY_F2 @"F2 Schedule"
#define BELL_ASSEMBLY_E3 @"E3 Schedule"
#define BELL_ASSEMBLY_F3 @"F3 Schedule"

#define CYCLE_REGULAR @"Regular"
#define CYCLE_ALTERNATE @"Alternate"

#define PERIOD_HOME_ROOM @"Home Room"
#define PERIOD_1 @"1"
#define PERIOD_2 @"2"
#define PERIOD_3 @"3"
#define PERIOD_4 @"4"
#define PERIOD_5 @"5"
#define PERIOD_6 @"6"
#define PERIOD_7 @"7"
#define PERIOD_8 @"8"
#define PERIOD_ASSEMBLY @"Assembly"
#define PERIOD_CHAPEL   @"Chapel"
#define PERIOD_LUNCH    @"Lunch"
#define PERIOD_MEETING  @"Meeting"
#define PERIOD_CONVOCATION @"Convocation"
#define PERIOD_CEREMONY @"Ceremony"
#define PERIOD_BREAK @"Break"

@implementation AAScheduleLoader

+ (BOOL)scheduleLoadRequired:(NSManagedObjectContext *)context
{
    // Check if schedules need to be loaded from JSON file
    PFConfig *config = [PFConfig currentConfig];
    if(config[@"firstDay"] && config[@"lastDay"]) {
        BOOL hasFirstDay = (BOOL)[SchoolDay schoolDayForString:config[@"firstDay"]
                                                inContext:context];
    
        BOOL hasLastDay = (BOOL)[SchoolDay schoolDayForString:config[@"lastDay"]
                                                inContext:context];
        return !(hasFirstDay && hasLastDay);
    } else {
        // Return true if PFConfig is not loaded yet (e.g. app has never been run)
        return true;
    }
}

+ (void)loadScheduleDataWithContext:(NSManagedObjectContext *)context
{
    [self verifyCurrentAppVersion];
    if ([self scheduleLoadRequired:context])    {
        // Parse schedule:
        [self loadScheduleJSONIntoContext:context];
        // Test data load:
        [self verifyBellsCyclesPeriodsWithContext:context];
        // Load period times:
        [self loadBellCyclePeriodDataIntoContext:context];
    } else  {
        [self fetchNewSchedules: context];
    }
}

+ (void)verifyCurrentAppVersion {
    NSString *currentVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *bundleID = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
    [PFConfig getConfigInBackgroundWithBlock:^(PFConfig *config, NSError *error) {
        if(!error) {
            if([bundleID isEqualToString:config[@"appleDistroBundleID"]]) {
                NSString *currentTFVer = config[@"currentTFVer"];
                NSString *currentASVer = config[@"currentASVer"];
                NSString *currentARVer = config[@"currentARVer"];
                NSLog(@"Fetched latest version info for iobot Apple distro v%@, v%@, and v%@.", currentASVer, currentTFVer, currentARVer);
                if(!error && ![currentVer containsString:currentTFVer] && ![currentVer containsString:currentASVer] && ![currentVer containsString:currentARVer]) {
                    NSString *message = config[@"messageAppleDistro"];
                    NSString *header = config[@"headerAppleDistro"];
                    NSLog(@"iobot v%@ is out of date.  Currently valid versions are: %@, %@, %@.  Received prompt: %@, %@", currentVer, currentASVer, currentTFVer, currentARVer, header, message);
                    
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:header message:message delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
                    [alert show];
                }
            } else if([bundleID isEqualToString:config[@"selfServiceBundleID"]]) {
                NSString *appVer = config[@"currentSSVer"];
                NSString *message = config[@"messageSS"];
                NSString *header = config[@"messageHeaderSS"];
                NSLog(@"Fetched latest version info for iobot in-house v%@.", appVer);
                if(![currentVer isEqualToString:appVer]) {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:header message:message delegate:self cancelButtonTitle:nil otherButtonTitles:nil, nil];
                    NSLog(@"App is out of date.  Version %@ reported, currently running version %@.  Received prompt: %@, %@", appVer, currentVer, header, message);
                    [alert show];
                } else {
                    NSLog(@"App install is up to date.");
                }
            } else {
                NSLog(@"Currently running unsupported bundle ID: %@.", bundleID);
            }
        }
        else {
            // currentVer was not retrieved, handle
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unable to connect to the Internet!" message:@"Please connect to the Internet to get the latest schedule updates." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
            NSLog(@"Error retrieving current app version, running version %@.", currentVer);
            [alert show];
        }
    }];
}

+ (void)verifyBellsCyclesPeriodsWithContext:(NSManagedObjectContext *)context
{
    // Test and load bells:
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Bell"];
    NSError *error;
    NSArray *bells = [context executeFetchRequest:request error:&error];
    NSAssert(!error, @"error loading bell data");
    DLog(@"Bells count: %lu", (unsigned long)[bells count]);
    
    // Test and load cycles:
    request = [NSFetchRequest fetchRequestWithEntityName:@"Cycle"];
    NSArray *cycles = [context executeFetchRequest:request error:&error];
    NSAssert(!error, @"error loading cycle data");
    DLog(@"Cycles count: %lu", (unsigned long)[cycles count]);
    
    // Test and load periods:
    request = [NSFetchRequest fetchRequestWithEntityName:@"Period"];
    NSArray *periods = [context executeFetchRequest:request error:&error];
    NSAssert(!error, @"error loading period data");
    DLog(@"Cycles count: %lu", (unsigned long)[periods count]);
}


#pragma mark - JSON Schedule Data Load

+ (void)loadScheduleJSONIntoContext:(NSManagedObjectContext *)context
{
    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"schedule"
                                                         ofType:@"json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    NSError *error = nil;
    NSArray *schedule = [NSJSONSerialization JSONObjectWithData:jsonData
                                              options:kNilOptions
                                                error:&error];
    if (!error) {
        for (NSDictionary *schoolDayInfo in schedule) {
            [SchoolDay schoolDayWithDayString:schoolDayInfo[@"day"]
                                     bellName:schoolDayInfo[@"title"]
                                    cycleName:[NSString stringWithFormat:@"%@", schoolDayInfo[@"cycle"]]
                       inManagedObjectContext:context];
        }
    } else {
        NSAssert(NO, @"Could not parse JSON schedule.");
    }
}

+ (void)fetchNewSchedules:(NSManagedObjectContext *)context
{
    // fetch new schedules from Parse
    PFQuery *newScheduleQuery = [PFQuery queryWithClassName:@"NewSchedule"];
    // set cache policy
    newScheduleQuery.cachePolicy = kPFCachePolicyCacheThenNetwork;
    [newScheduleQuery addAscendingOrder:@"updatedAt"];
    // load any new schedules from Parse into context
    [newScheduleQuery findObjectsInBackgroundWithBlock:^(NSArray *newSchedules, NSError *error) {
        if(!error)  {
            for(PFObject *schedule in newSchedules)    {
                [self loadBellName:[schedule objectForKey:@"bellName"]
                         cycleName:[schedule objectForKey:@"cycleName"]
                           periods:[schedule objectForKey:@"periods"]
                             times:[schedule objectForKey:@"times"]
          intoManagedObjectContext:context];
            }
        }
    }];
    
    PFQuery *missingScheduleQuery = [PFQuery queryWithClassName:@"Override"];
    missingScheduleQuery.cachePolicy = kPFCachePolicyCacheThenNetwork;
    [missingScheduleQuery addAscendingOrder:@"updatedAt"];
    [missingScheduleQuery whereKey:@"isMissing" equalTo:@YES];
    [missingScheduleQuery findObjectsInBackgroundWithBlock:^(NSArray *missingSchedules, NSError *error) {
        if(!error)  {
            for(PFObject *schedule in missingSchedules) {
                [SchoolDay schoolDayWithDayString:[schedule objectForKey:@"dayString"]
                                         bellName:[schedule objectForKey:@"bellName"]
                                        cycleName:[schedule objectForKey:@"cycleName"]
                           inManagedObjectContext:context];
            }
        }
    }];
    
    [self overrides:context];
}

#pragma mark - Load Bell Cycle Period Data

+ (void)loadBellName:(NSString *)bellName
           cycleName:(NSString *)cycleName
             periods:(NSArray*)periods
               times:(NSArray *)times
intoManagedObjectContext:(NSManagedObjectContext *)context
{
    NSError *error;
    NSArray *matches = [BellCyclePeriod bellCyclePeriodsInSchedule:bellName
                                                         withCycle:cycleName
                                            inManagedObjectContext:context];
    if([matches count])  {
        for(BellCyclePeriod *period in matches) {
            [context deleteObject:period];
        }
        [context save:&error];
    }
    for (int i=0; i<[periods count]; i++) {
        [BellCyclePeriod bellCyclePeriodWithBellName:bellName
                                           cycleName:cycleName
                                          periodName:periods[i]
                                     startTimeString:times[i][@"start"]
                                       endTimeString:times[i][@"end"]
                              inManagedObjectContext:context];
    }
}

#pragma mark - Load Bell Cycle Periods

+ (void)loadBellCyclePeriodDataIntoContext:(NSManagedObjectContext *)context
{
    [self loadBasicPeriodDataIntoContext:context];
    [self loadAssembly1PeriodDataIntoContext:context];
    [self loadAssembly3PeriodDataIntoContext:context];
    [self loadAthleticPeriodDataIntoContext:context];
    [self loadFairPeriodDataIntoContext:context];
    [self loadABCDScheduleDataIntoContext:context];
    [self loadEFScheduleDataIntoContext:context];
    [self loadAssemblyEF1ScheduleDataIntoContect:context];
    [self loadAssemblyEF2ScheduleDataIntoContect:context];
    [self loadAssemblyEF3ScheduleDataIntoContect:context];
 
    // These must go last. They correct errors in the raw schedule.
    [self fetchNewSchedules:context];
}

+ (void)overDayString:(NSString *)dayString
             bellName:(NSString *)bellName
            cycleName:(NSString *)cycleName
              context:(NSManagedObjectContext *)context
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"SchoolDay"];
    NSDate *day = [SchoolDay dateFromSchoolDayString:dayString];
    request.predicate = [NSPredicate predicateWithFormat:@"day = %@", day];
    
    NSError *error;
    NSArray *matches = [context executeFetchRequest:request error:&error];
    
    if (!matches || ([matches count] > 1 || ![matches count])) {
        // handle error
        NSAssert(NO, @"wrong number of school day matches returned.");
    } else {
        BellCycle *bellCycle = [BellCycle bellCycleWithBellName:bellName cycleName:cycleName inManagedObjectContext:context];
        SchoolDay *schoolDay = [matches lastObject];
        schoolDay.bellCycle = bellCycle;
    }
}

+ (void)overrides:(NSManagedObjectContext *)context
{
    PFQuery *overrideQuery = [PFQuery queryWithClassName:@"Override"];
    // load query from cache first (if available), then load from network
    overrideQuery.cachePolicy = kPFCachePolicyCacheThenNetwork;
    // load most recent overrides first
    [overrideQuery addAscendingOrder:@"updatedAt"];
    [overrideQuery whereKey:@"isMissing" equalTo:@NO];
    [overrideQuery findObjectsInBackgroundWithBlock:^(NSArray *overrides, NSError *error) {
        if(!error)  {
            for(PFObject *schedule in overrides)   {
                [self overDayString:[schedule objectForKey:@"dayString"]
                           bellName:[schedule objectForKey:@"bellName"]
                          cycleName:[schedule objectForKey:@"cycleName"]
                            context:context];
            }
            NSLog(@"Retrieved and loaded overrides.");
        } else  {
            NSLog(@"Unable to retrieve overrides from both network and cache.");
        }
    }];
    // Leaving overrides in as example code
    // Change bell-cycle for Moving Up Chapel day from
    // regular "Chapel" to "Chapel Moving Up".
//    [self overDayString:@"2014-05-22"
//               bellName:BELL_CHAPEL_MOVING_UP
//              cycleName:CYCLE_7
//                context:context];
    
    // Change bell-cycle for March 31, 2014 from
    // "Chapel - Cycle 1" to "Assembly 1 - Cycle 1".
//    [self overDayString:@"2014-03-31"
//               bellName:BELL_ASSEMBLY_1
//              cycleName:CYCLE_1
//                context:context];
}

+ (void)loadBasicPeriodDataIntoContext:(NSManagedObjectContext *)context
{
    NSString *bellType = BELL_BASIC;
    NSArray *periods = nil;
    
    // BASIC - CYCLE 1
    NSArray *times = @[@{@"start": @"07:40", @"end": @"07:45"},
                       @{@"start": @"07:50", @"end": @"08:34"},
                       @{@"start": @"08:39", @"end": @"09:23"},
                       @{@"start": @"09:28", @"end": @"10:12"},
                       @{@"start": @"10:17", @"end": @"11:01"},
                       @{@"start": @"11:06", @"end": @"11:50"},
                       @{@"start": @"11:50", @"end": @"12:33"},
                       @{@"start": @"12:38", @"end": @"13:22"},
                       @{@"start": @"13:27", @"end": @"14:11"},
                       @{@"start": @"14:16", @"end": @"15:00"}];
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_3,
                PERIOD_4,
                PERIOD_5,
                PERIOD_LUNCH,
                PERIOD_6,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:bellType
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadAssembly1PeriodDataIntoContext:(NSManagedObjectContext *)context
{
    NSString *bellType = BELL_ASSEMBLY_1;
    NSArray *periods = nil;
    
    // ASSEMBLY 1 - CYCLE 1
    NSArray *times = @[@{@"start": @"07:40", @"end": @"07:45"},
                       @{@"start": @"07:50", @"end": @"08:34"},
                       @{@"start": @"08:39", @"end": @"09:18"},
                       @{@"start": @"09:23", @"end": @"10:02"},
                       @{@"start": @"10:07", @"end": @"10:46"},
                       @{@"start": @"10:51", @"end": @"11:30"},
                       @{@"start": @"11:35", @"end": @"12:14"},
                       @{@"start": @"12:14", @"end": @"12:48"},
                       @{@"start": @"12:53", @"end": @"13:32"},
                       @{@"start": @"13:37", @"end": @"14:16"},
                       @{@"start": @"14:21", @"end": @"15:00"}];
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_ASSEMBLY,
                PERIOD_1,
                PERIOD_2,
                PERIOD_3,
                PERIOD_4,
                PERIOD_5,
                PERIOD_LUNCH,
                PERIOD_6,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:bellType
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadAssembly3PeriodDataIntoContext:(NSManagedObjectContext *)context
{
    NSString *bellType = BELL_ASSEMBLY_3;
    NSArray *periods = nil;
    
    // ASSEMBLY 3 - CYCLE 1
    NSArray *times = @[@{@"start": @"07:40", @"end": @"07:45"},
                       @{@"start": @"07:50", @"end": @"08:29"},
                       @{@"start": @"08:34", @"end": @"09:13"},
                       @{@"start": @"09:18", @"end": @"09:57"},
                       @{@"start": @"10:02", @"end": @"10:41"},
                       @{@"start": @"10:46", @"end": @"11:25"},
                       @{@"start": @"11:30", @"end": @"12:09"},
                       @{@"start": @"12:09", @"end": @"12:44"},
                       @{@"start": @"12:49", @"end": @"13:28"},
                       @{@"start": @"13:33", @"end": @"14:12"},
                       @{@"start": @"14:17", @"end": @"15:00"}];
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_3,
                PERIOD_4,
                PERIOD_5,
                PERIOD_6,
                PERIOD_LUNCH,
                PERIOD_7,
                PERIOD_8,
                PERIOD_ASSEMBLY];
    [self loadBellName:bellType
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadAthleticPeriodDataIntoContext:(NSManagedObjectContext *)context
{
    NSString *bellType = BELL_ATHLETIC_ASSEMBLY;
    NSArray *periods = nil;
    
    // ATHLETIC - CYCLE 1
    NSArray *times = @[@{@"start": @"07:40", @"end": @"07:45"},
                       @{@"start": @"07:50", @"end": @"08:26"},
                       @{@"start": @"08:31", @"end": @"09:07"},
                       @{@"start": @"09:12", @"end": @"09:48"},
                       @{@"start": @"09:53", @"end": @"10:29"},
                       @{@"start": @"10:34", @"end": @"11:10"},
                       @{@"start": @"11:15", @"end": @"12:15"},
                       @{@"start": @"12:15", @"end": @"12:57"},
                       @{@"start": @"13:02", @"end": @"13:38"},
                       @{@"start": @"13:43", @"end": @"14:19"},
                       @{@"start": @"14:24", @"end": @"15:00"}];
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_3,
                PERIOD_4,
                PERIOD_5,
                PERIOD_ASSEMBLY,
                PERIOD_LUNCH,
                PERIOD_6,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:bellType
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadFairPeriodDataIntoContext:(NSManagedObjectContext *)context
{
    NSString *bellType = BELL_SPECIAL_FAIR_DAY;
    NSArray *periods = nil;
    
    NSArray *times = @[@{@"start": @"07:40", @"end": @"07:45"},
                       @{@"start": @"07:50", @"end": @"08:10"},
                       @{@"start": @"08:15", @"end": @"08:35"},
                       @{@"start": @"08:40", @"end": @"09:00"},
                       @{@"start": @"09:05", @"end": @"09:25"},
                       @{@"start": @"09:35", @"end": @"09:55"},
                       @{@"start": @"10:00", @"end": @"10:20"},
                       @{@"start": @"10:25", @"end": @"10:45"},
                       @{@"start": @"10:50", @"end": @"11:10"}];
    
    // Fair Day
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_3,
                PERIOD_4,
                PERIOD_5,
                PERIOD_6,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:bellType
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
}

+ (void)loadABCDScheduleDataIntoContext: (NSManagedObjectContext *)context
{
    NSArray *periods = nil;
    NSArray *times = @[@{@"start": @"07:40", @"end": @"08:10"},
                       @{@"start": @"08:15", @"end": @"09:10"},
                       @{@"start": @"09:15", @"end": @"10:10"},
                       @{@"start": @"10:10", @"end": @"10:20"},
                       @{@"start": @"10:20", @"end": @"11:15"},
                       @{@"start": @"11:20", @"end": @"12:15"},
                       @{@"start": @"12:15", @"end": @"13:00"},
                       @{@"start": @"13:05", @"end": @"14:00"},
                       @{@"start": @"14:05", @"end": @"15:00"}];
    // SCHEDULE A
    periods = @[PERIOD_HOME_ROOM " / " PERIOD_CHAPEL,
                PERIOD_1,
                PERIOD_2,
                PERIOD_BREAK,
                PERIOD_3,
                PERIOD_4,
                PERIOD_LUNCH,
                PERIOD_5,
                PERIOD_6];
    [self loadBellName:BELL_SCHEDULE_A
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];

    // SCHEDULE B
    periods = @[PERIOD_HOME_ROOM " / " PERIOD_CHAPEL,
                PERIOD_7,
                PERIOD_8,
                PERIOD_BREAK,
                PERIOD_1,
                PERIOD_2,
                PERIOD_LUNCH,
                PERIOD_3,
                PERIOD_4];
    [self loadBellName:BELL_SCHEDULE_B
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // SCHEDULE C
    periods = @[PERIOD_HOME_ROOM " / " PERIOD_CHAPEL,
                PERIOD_5,
                PERIOD_6,
                PERIOD_BREAK,
                PERIOD_7,
                PERIOD_8,
                PERIOD_LUNCH,
                PERIOD_1,
                PERIOD_2];
    [self loadBellName:BELL_SCHEDULE_C
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // SCHEDULE D
    periods = @[PERIOD_HOME_ROOM " / " PERIOD_CHAPEL,
                PERIOD_3,
                PERIOD_4,
                PERIOD_BREAK,
                PERIOD_5,
                PERIOD_6,
                PERIOD_LUNCH,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:BELL_SCHEDULE_D
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadEFScheduleDataIntoContext:(NSManagedObjectContext *)context
{
    NSArray *periods = nil;
    NSArray *times = @[@{@"start": @"07:40", @"end": @"08:10"},
                       @{@"start": @"08:15", @"end": @"09:25"},
                       @{@"start": @"09:30", @"end": @"10:40"},
                       @{@"start": @"10:40", @"end": @"12:30"},
                       @{@"start": @"12:35", @"end": @"13:45"},
                       @{@"start": @"13:50", @"end": @"15:00"}];
    
    // SCHEDULE E and F
    
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_3,
                PERIOD_4];
    [self loadBellName:BELL_SCHEDULE_E
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_5,
                PERIOD_6,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_7,
                PERIOD_8];
    
    [self loadBellName:BELL_SCHEDULE_F
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // SCHEDULE E and F (ALTERNATE)
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_3,
                PERIOD_4,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_1,
                PERIOD_2];
    
    [self loadBellName:BELL_SCHEDULE_E
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_7,
                PERIOD_8,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_5,
                PERIOD_6];
    
    [self loadBellName:BELL_SCHEDULE_F
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];

}

+ (void)loadAssemblyEF1ScheduleDataIntoContect:(NSManagedObjectContext *)context
{
    NSArray *periods = nil;
    NSArray *times = @[@{@"start": @"07:40", @"end": @"07:45"},
                       @{@"start": @"07:50", @"end": @"08:35"},
                       @{@"start": @"08:40", @"end": @"09:50"},
                       @{@"start": @"09:55", @"end": @"11:05"},
                       @{@"start": @"11:05", @"end": @"12:30"},
                       @{@"start": @"12:35", @"end": @"13:45"},
                       @{@"start": @"13:50", @"end": @"15:00"}];
    
    // ASSEMBLY SCHEDULE E1
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_CHAPEL " / " PERIOD_ASSEMBLY,
                PERIOD_1,
                PERIOD_2,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_3,
                PERIOD_4];
    [self loadBellName:BELL_ASSEMBLY_E1
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ALTERNATE E1
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_CHAPEL " / " PERIOD_ASSEMBLY,
                PERIOD_3,
                PERIOD_4,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_1,
                PERIOD_2];
    [self loadBellName:BELL_ASSEMBLY_E1
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ASSEMBLY SCHEDULE F1
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_CHAPEL " / " PERIOD_ASSEMBLY,
                PERIOD_5,
                PERIOD_6,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:BELL_ASSEMBLY_F1
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ALTERNATE F1
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_CHAPEL " / " PERIOD_ASSEMBLY,
                PERIOD_7,
                PERIOD_8,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_5,
                PERIOD_6];
    [self loadBellName:BELL_ASSEMBLY_F1
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadAssemblyEF2ScheduleDataIntoContect:(NSManagedObjectContext *)context
{
    NSArray *periods = nil;
    NSArray *times = @[@{@"start": @"07:40", @"end": @"08:10"},
                       @{@"start": @"08:15", @"end": @"09:25"},
                       @{@"start": @"09:30", @"end": @"10:40"},
                       @{@"start": @"10:45", @"end": @"11:30"},
                       @{@"start": @"11:30", @"end": @"12:30"},
                       @{@"start": @"12:35", @"end": @"13:45"},
                       @{@"start": @"13:50", @"end": @"15:00"}];
    
    // ASSEMBLY SCHEDULE E2
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_ASSEMBLY,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_3,
                PERIOD_4];
    [self loadBellName:BELL_ASSEMBLY_E2
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ALTERNATE E2
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_3,
                PERIOD_4,
                PERIOD_ASSEMBLY,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_1,
                PERIOD_2];
    [self loadBellName:BELL_ASSEMBLY_E2
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ASSEMBLY SCHEDULE F2
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_5,
                PERIOD_6,
                PERIOD_ASSEMBLY,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_7,
                PERIOD_8];
    [self loadBellName:BELL_ASSEMBLY_F2
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ALTERNATE F2
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_7,
                PERIOD_8,
                PERIOD_ASSEMBLY,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_5,
                PERIOD_6];
    [self loadBellName:BELL_ASSEMBLY_F2
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
}

+ (void)loadAssemblyEF3ScheduleDataIntoContect:(NSManagedObjectContext *)context
{
    NSArray *periods = nil;
    NSArray *times = @[@{@"start": @"07:40", @"end": @"08:10"},
                       @{@"start": @"08:15", @"end": @"09:25"},
                       @{@"start": @"09:30", @"end": @"10:40"},
                       @{@"start": @"10:45", @"end": @"11:55"},
                       @{@"start": @"11:55", @"end": @"12:55"},
                       @{@"start": @"13:00", @"end": @"14:10"},
                       @{@"start": @"14:15", @"end": @"15:00"}];
    
    // ASSEMBLY SCHEDULE E3
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_1,
                PERIOD_2,
                PERIOD_3,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_4,
                PERIOD_ASSEMBLY];
    [self loadBellName:BELL_ASSEMBLY_E3
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ALTERNATE E3
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_3,
                PERIOD_4,
                PERIOD_1,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_2,
                PERIOD_ASSEMBLY];
    [self loadBellName:BELL_ASSEMBLY_E3
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ASSEMBLY SCHEDULE F3
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_5,
                PERIOD_6,
                PERIOD_7,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_8,
                PERIOD_ASSEMBLY,];
    [self loadBellName:BELL_ASSEMBLY_F3
             cycleName:CYCLE_REGULAR
               periods:periods
                 times:times intoManagedObjectContext:context];
    
    // ALTERNATE F3
    periods = @[PERIOD_HOME_ROOM,
                PERIOD_7,
                PERIOD_8,
                PERIOD_5,
                PERIOD_MEETING " / " PERIOD_LUNCH,
                PERIOD_6,
                PERIOD_ASSEMBLY];
    [self loadBellName:BELL_ASSEMBLY_F3
             cycleName:CYCLE_ALTERNATE
               periods:periods
                 times:times intoManagedObjectContext:context];
}

@end
