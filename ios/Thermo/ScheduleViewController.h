//
//  ScheduleViewController.h
//  Thermo
//
//  Created by Dale Low on 2/17/16.
//  Copyright © 2016 gumbypp consulting. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ScheduleViewController;

@protocol ScheduleViewControllerDelegate <NSObject>

- (void)scheduleViewControllerDidCancel:(ScheduleViewController *)svc;
- (void)scheduleViewController:(ScheduleViewController *)svc didEditWeekdaySchedule:(NSData *)weekdaySchedule
               weekendSchedule:(NSData *)weekendSchedule;

@end

@interface ScheduleViewController : UIViewController

@property (nonatomic, weak) id<ScheduleViewControllerDelegate> delegate;
@property (nonatomic, strong) NSData *rawWeekdaySchedule;
@property (nonatomic, strong) NSData *rawWeekendSchedule;

@end
