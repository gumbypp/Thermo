//
//  ScheduleViewController.m
//  Thermo
//
//  Created by Dale Low on 2/17/16.
//  Copyright © 2016 gumbypp consulting. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// - The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "ScheduleViewController.h"

typedef NS_ENUM(NSInteger, EditTypeTag)
{
    kEditTypeTagStartTime = 1,
    kEditTypeTagEndTime,
    kEditTypeTagTemp
};

#define INDEX_TO_TAG(index)     (index << 8)
#define TAG_TO_INDEX(tag)       (tag >> 8)
#define EDIT_TYPE_TO_TAG(tf)    (tf)
#define TAG_TO_EDIT_TYPE(tag)   (tag & 0xFF)

#define kDatePickerTagBit       0x8000

typedef NS_ENUM(NSInteger, TableSection)
{
    kTableSectionHeading,
    kTableSectionSchedule,
    kTableSectionGraph,
    kTableSection_Count
};

#define kTableSectionHeadingHeight  30
#define kTableSectionScheduleHeight 44
#define kTableSectionGraphHeight    120

@interface OneSchedule : NSObject

@property (nonatomic, assign) time_t startTimePastMidnight;
@property (nonatomic, assign) time_t duration;
@property (nonatomic, assign) int targetTempF;

- (id)initWithStartTimeQuarterHours:(int)startTimeQuarterHours durationQuarterHours:(int)durationQuarterHours targetTempF:(int)targetTempF;

@end

@implementation OneSchedule

- (id)initWithStartTimeQuarterHours:(int)startTimeQuarterHours durationQuarterHours:(int)durationQuarterHours targetTempF:(int)targetTempF
{
    self = [super init];
    if (self) {
        if (durationQuarterHours) {
            _startTimePastMidnight = startTimeQuarterHours * 15*kSecondsPerMinute;
            _duration = durationQuarterHours * 15*kSecondsPerMinute;
            _targetTempF = targetTempF;
        } else {
            // disabled schedule - treat as full day, min temp
            _startTimePastMidnight = 0;
            _duration = kSecondsPerDay;
            _targetTempF = kMinTargetTempF;
        }
    }
    return self;
}

@end

@interface ScheduleTableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
@property (nonatomic, weak) IBOutlet UITextField *startTimeTextField;
@property (nonatomic, weak) IBOutlet UITextField *endTimeTextField;
@property (nonatomic, weak) IBOutlet UITextField *temperatureTextField;

@end

@implementation ScheduleTableViewCell

@end

@interface ScheduleViewController () <UITextFieldDelegate>

@property (nonatomic, weak) IBOutlet UISegmentedControl *segmentControl;
@property (nonatomic, weak) IBOutlet UIButton *doneButton;
@property (nonatomic, weak) IBOutlet UITableView *tableView;

@property (nonatomic, assign) BOOL updateFromTextField;
@property (nonatomic, assign) BOOL scheduleChanged;
@property (nonatomic, strong) NSMutableArray *weekdaySchedules;
@property (nonatomic, strong) NSMutableArray *weekendSchedules;
@property (nonatomic, weak) NSMutableArray *currentSchedules;
@property (nonatomic, strong) NSArray *scheduleColours;
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, strong) UIToolbar *inputAccessoryToolbar;
@property (nonatomic, weak) UITextField *textFieldWithVisibleKeyboard;

@end

@implementation ScheduleViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    self.datePicker.datePickerMode = UIDatePickerModeTime;
    [self.datePicker setPreferredDatePickerStyle:UIDatePickerStyleWheels];

    // Create a toolbar for the "Done" button
    self.inputAccessoryToolbar = [[UIToolbar alloc] init];
    [self.inputAccessoryToolbar sizeToFit];
    
    UIBarButtonItem *bbiDone = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemDone
                                                                             target:self action:@selector(inputAccessoryDonePressed:)];
    UIBarButtonItem *bbiSpacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace
                                                                               target:nil action:nil];
    UIBarButtonItem *bbiCancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemCancel
                                                                               target:self action:@selector(inputAccessoryCancelPressed:)];
    [self.inputAccessoryToolbar setItems:@[bbiCancel, bbiSpacer, bbiDone]];
    
    uint8_t *weekdayBytes = (uint8_t *)[self.rawWeekdaySchedule bytes];
    uint8_t *weekendBytes = (uint8_t *)[self.rawWeekendSchedule bytes];
    
    self.weekdaySchedules = [NSMutableArray arrayWithCapacity:kScheduleOptionCount];
    self.weekendSchedules = [NSMutableArray arrayWithCapacity:kScheduleOptionCount];
    for (int i=0; i<kScheduleOptionCount; i++) {
        [self.weekdaySchedules addObject:[[OneSchedule alloc] initWithStartTimeQuarterHours:weekdayBytes[3*i]
                                                                       durationQuarterHours:weekdayBytes[3*i + 1]
                                                                                targetTempF:weekdayBytes[3*i + 2]]];

        [self.weekendSchedules addObject:[[OneSchedule alloc] initWithStartTimeQuarterHours:weekendBytes[3*i]
                                                                       durationQuarterHours:weekendBytes[3*i + 1]
                                                                                targetTempF:weekendBytes[3*i + 2]]];
    }
    
    [self.segmentControl addTarget:self action:@selector(segmentControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.segmentControl.selectedSegmentIndex = 0;
    self.currentSchedules = self.weekdaySchedules;
    
    self.scheduleColours = @[ [UIColor redColor], [UIColor blueColor], [UIColor magentaColor]];
}

#pragma mark - internal methods

- (NSString *)friendlyTimeFromSecondsPastMidnight:(time_t)secondsPastMidnight
{
    return [NSString stringWithFormat:@"%ld:%02ld", secondsPastMidnight/kSecondsPerHour, (secondsPastMidnight/kMinutesPerHour)%kMinutesPerHour];
}

- (NSDate *)referenceDateForHour:(NSInteger)hour minute:(NSInteger)minute
{
    NSDateComponents *dc = [[NSDateComponents alloc] init];
    dc.year = 2001;
    dc.month = 1;
    dc.day = 1;
    dc.hour = hour;
    dc.minute = minute;
    dc.second = 0;
    
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    
    return [calendar dateFromComponents:dc];
}

- (UIView *)graphForCurrentSchedule
{
#define kLabelSpacer 3
    
    CGRect sizeRect = [UIScreen mainScreen].applicationFrame;
    CGFloat width = sizeRect.size.width;
    CGFloat secondWidth = width/kSecondsPerDay;
    
    UIView *graphView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kTableSectionGraphHeight)];
    
    // leave some room at the top for the labels
    CGFloat graphYOffset = 25;
    CGFloat height = kTableSectionGraphHeight - graphYOffset;

    // iterate backwards so that higher priority schedules get drawn on top of lower pri ones
    for (int i=kScheduleOptionCount; i--;) {
        OneSchedule *s = self.currentSchedules[i];
        
        CGFloat y = graphYOffset + (1.0 - ((CGFloat)s.targetTempF - kMinTargetTempF)/(kMaxTargetTempF - kMinTargetTempF))*height;
        y = MIN(y, kTableSectionGraphHeight - 2);   // so that we see something for schedules with the min temp
        
        UIView *scheduleView = [[UIView alloc] initWithFrame:CGRectMake(s.startTimePastMidnight*secondWidth,
                                                                        y,
                                                                        s.duration*secondWidth,
                                                                        kTableSectionGraphHeight - y)];
        scheduleView.backgroundColor = self.scheduleColours[i];
        [graphView addSubview:scheduleView];

        UIView *nonScheduleView = [[UIView alloc] initWithFrame:CGRectMake(s.startTimePastMidnight*secondWidth,
                                                                           0,
                                                                           s.duration*secondWidth,
                                                                           y)];
        nonScheduleView.backgroundColor = [UIColor whiteColor];
        [graphView addSubview:nonScheduleView];

        UILabel *tempLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        tempLabel.text = [NSString stringWithFormat:@"%d °F", s.targetTempF];
        tempLabel.textColor = self.scheduleColours[i];
        [tempLabel sizeToFit];
        
        CGFloat x = scheduleView.frame.origin.x;
        if (tempLabel.frame.size.width > scheduleView.frame.size.width) {
            x += (scheduleView.frame.size.width - tempLabel.frame.size.width)/2;
        }
        if (x < 0) {
            x = 0;
        }
        
        tempLabel.frame = CGRectMake(x, y - tempLabel.frame.size.height - kLabelSpacer, tempLabel.frame.size.width, tempLabel.frame.size.height);
        [graphView addSubview:tempLabel];
    }
    
    return graphView;
}

#pragma mark - event handlers

- (void)segmentControlChanged:(UISegmentedControl *)sender
{
    self.currentSchedules = sender.selectedSegmentIndex ? self.weekendSchedules : self.weekdaySchedules;
    [self.tableView reloadData];
}

- (void)inputAccessoryCancelPressed:(id)sender
{
    self.updateFromTextField = NO;
    [self.textFieldWithVisibleKeyboard resignFirstResponder];
}

- (void)inputAccessoryDonePressed:(id)sender
{
    self.updateFromTextField = YES;
    [self.textFieldWithVisibleKeyboard resignFirstResponder];
}

- (IBAction)cancelPressed:(id)sender
{
    [self.delegate scheduleViewControllerDidCancel:self];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)donePressed:(id)sender
{
    if (!self.scheduleChanged) {
        [self cancelPressed:nil];
        return;
    }
    
    uint8_t weekdaySchedule[9];
    uint8_t weekendSchedule[9];
    
    for (int schedule=0; schedule<2; schedule++) {
        NSArray *schedules = schedule ? self.weekendSchedules : self.weekdaySchedules;
        uint8_t *p = schedule ? weekendSchedule : weekdaySchedule;
        
        for (int i=0; i<kScheduleOptionCount; i++) {
            OneSchedule *s = schedules[i];
            if (s.duration == kSecondsPerDay) {
                // start_time==end_time is the same as start_time=0, duration=1 day
                s.startTimePastMidnight = 0;
            }
            
            *p++ = s.startTimePastMidnight / (15*kSecondsPerMinute);                        // convert back to quarter-hours
            
            if (s.duration < 0) {
                [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Cannot have end time before start time" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
                return;
            }
            
            *p++ = s.duration / (15*kSecondsPerMinute);    // convert back to quarter-hours
            *p++ = s.targetTempF;
        }
    }

    [self.delegate scheduleViewController:self
                   didEditWeekdaySchedule:[NSData dataWithBytes:weekdaySchedule length:sizeof(weekdaySchedule)]
                          weekendSchedule:[NSData dataWithBytes:weekendSchedule length:sizeof(weekendSchedule)]];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource/Delegate methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kTableSection_Count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case kTableSectionHeading:
            return 1;
        case kTableSectionSchedule:
            return kScheduleOptionCount;
        case kTableSectionGraph:
            return 1;
    }
    
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case kTableSectionHeading:
            return kTableSectionHeadingHeight;
        case kTableSectionSchedule:
            return kTableSectionScheduleHeight;
        case kTableSectionGraph:
            return kTableSectionGraphHeight;
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case kTableSectionHeading: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ScheduleTitle" forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
        case kTableSectionSchedule: {
            ScheduleTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ScheduleTableViewCell" forIndexPath:indexPath];
            
            int index = (int)indexPath.row;
            
            OneSchedule *s = self.currentSchedules[index];
            time_t endTimePastMidnight = s.startTimePastMidnight + s.duration;
            if (!s.startTimePastMidnight && (endTimePastMidnight >= (24 * kSecondsPerHour))) {
                endTimePastMidnight = 0;    // schedule applies to entire day (so 0:00 - 0:00)
            }
            
            // priority
            cell.titleLabel.text = [Common getSchedulePriorityForIndex:index];            
            cell.titleLabel.textColor = self.scheduleColours[index];
            
            cell.startTimeTextField.text = [self friendlyTimeFromSecondsPastMidnight:s.startTimePastMidnight];
            cell.startTimeTextField.tag = INDEX_TO_TAG(index) | EDIT_TYPE_TO_TAG(kEditTypeTagStartTime);
            cell.startTimeTextField.inputView = self.datePicker;
            cell.startTimeTextField.inputAccessoryView = self.inputAccessoryToolbar;
            cell.startTimeTextField.delegate = self;
            
            cell.endTimeTextField.text = [self friendlyTimeFromSecondsPastMidnight:endTimePastMidnight];
            cell.endTimeTextField.tag = INDEX_TO_TAG(index) | EDIT_TYPE_TO_TAG(kEditTypeTagEndTime);
            cell.endTimeTextField.inputView = self.datePicker;
            cell.endTimeTextField.inputAccessoryView = self.inputAccessoryToolbar;
            cell.endTimeTextField.delegate = self;
            
            cell.temperatureTextField.text = [NSString stringWithFormat:@"%d °F", s.targetTempF];
            cell.temperatureTextField.tag = INDEX_TO_TAG(index) | EDIT_TYPE_TO_TAG(kEditTypeTagTemp);
            cell.temperatureTextField.keyboardType = UIKeyboardTypeNumberPad;
            cell.temperatureTextField.inputAccessoryView = self.inputAccessoryToolbar;
            cell.temperatureTextField.delegate = self;
            
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
        case kTableSectionGraph: {
            UITableViewCell *cell = [[UITableViewCell alloc] init];
            [cell.contentView addSubview:[self graphForCurrentSchedule]];
            
            return cell;
        }
    }

    return nil;
}

#pragma mark - UITextFieldDelegate methods

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    EditTypeTag editType = TAG_TO_EDIT_TYPE(textField.tag);
    switch (editType) {
        case kEditTypeTagStartTime:
        case kEditTypeTagEndTime: {
            self.datePicker.tag = textField.tag | kDatePickerTagBit;
            
            int hours, minutes;
            int rc = sscanf([textField.text UTF8String], "%d:%02d", &hours, &minutes);
            if (2 != rc) {
                hours = minutes = 0;
            }
            
            [self.datePicker setDate:[self referenceDateForHour:hours minute:minutes]];
            self.datePicker.minuteInterval = 15;
            break;
        }

        case kEditTypeTagTemp: {
            // remove units
            textField.text = [@([textField.text intValue]) stringValue];
            break;
        }
    }

    // hide keyboard of a previous text field that has one showing
    [self.textFieldWithVisibleKeyboard resignFirstResponder];
    self.textFieldWithVisibleKeyboard = textField;

    // cannot exit while editing (with uncommitted values)
    self.doneButton.enabled = NO;
    self.segmentControl.enabled = NO;

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (!self.updateFromTextField) {
        self.doneButton.enabled = YES;
        self.segmentControl.enabled = YES;
        self.textFieldWithVisibleKeyboard = nil;

        return;
    }
    
    if (TAG_TO_EDIT_TYPE(textField.tag) != kEditTypeTagTemp) {
        time_t secondsPastMidnight = (time_t)[self.datePicker.date timeIntervalSinceReferenceDate] % kSecondsPerDay;
        textField.text = [self friendlyTimeFromSecondsPastMidnight:secondsPastMidnight];
        
        NSInteger textFieldTag = textField.tag & ~kDatePickerTagBit;
        int index = (int)TAG_TO_INDEX(textFieldTag);
        EditTypeTag editType = TAG_TO_EDIT_TYPE(textFieldTag);
        
        OneSchedule *s = self.currentSchedules[index];
        if (kEditTypeTagEndTime == editType) {
            s.duration = secondsPastMidnight - s.startTimePastMidnight;
        } else {
            NSAssert(kEditTypeTagStartTime == editType, @"expect kEditTypeTagStartTime here");
            time_t durationDelta = s.startTimePastMidnight - secondsPastMidnight;
            s.startTimePastMidnight = secondsPastMidnight;
            s.duration += durationDelta;
        }
        
        if (!s.duration) {
            // start_time==end_time
            s.duration = kSecondsPerDay;
        }
    } else {
        int newTargetTemp = [textField.text intValue];
        newTargetTemp = MIN(MAX(newTargetTemp, kMinTargetTempF), kMaxTargetTempF);
        
        textField.text = [NSString stringWithFormat:@"%d °F", newTargetTemp];
        
        int index = (int)TAG_TO_INDEX(textField.tag);
        OneSchedule *s = self.currentSchedules[index];
        s.targetTempF = newTargetTemp;
    }

    self.doneButton.enabled = YES;
    self.segmentControl.enabled = YES;
    self.textFieldWithVisibleKeyboard = nil;
    
    self.scheduleChanged = YES;
    [self.tableView reloadData];    // update the graph
}

@end
