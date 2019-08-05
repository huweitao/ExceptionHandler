//
//  ViewController.m
//  ExceptionHandlerDemo
//
//  Created by huweitao on 2019/8/5.
//  Copyright © 2019 huweitao. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 200, 50)];
    [button setTitle:@"Trigger Crash!" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(crashClick:) forControlEvents:UIControlEventTouchUpInside];
    [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.view addSubview:button];
}

- (IBAction)crashClick:(UIButton *)sender
{
    NSString *str;
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:0];
    
    [dic setObject:str forKey:@"ddd"];
    NSLog(@"%@---%@",dic[@"ddd"],dic[@"dddddd"]);
}


@end
