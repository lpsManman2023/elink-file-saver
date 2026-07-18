//
//  ELKFileExporter.m
//  ELKFileSaver - v15 智能过滤
//
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"

// ── 文件名纯数字检测 ──
static BOOL isNumericName(NSString *name) {
    NSString *base = [name stringByDeletingPathExtension];
    if (base.length == 0) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [base rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

// ── 方案4过滤：应该显示这个文件吗？ ──
static BOOL shouldIncludeFile(NSString *path, unsigned long long size) {
    if (size < 100) return NO;
    NSString *name = [path lastPathComponent];
    NSString *ext  = [[name pathExtension] lowercaseString];

    // 规则1: 有扩展名 → 显示
    if (ext.length > 0) return YES;

    // 无扩展名
    // 规则2: 纯数字文件名 → 不显示
    if (isNumericName(name)) return NO;

    // 规则3: 非纯数字 + 大于100KB → 显示
    if (size > 100000) return YES;

    // 规则4: 小于100KB → 不显示
    return NO;
}

// ── 扫描根目录 ──
static NSArray *scanRoots(void) {
    NSMutableArray *roots = [NSMutableArray array];
    NSString *profilesDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Profiles"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *pid in [fm contentsOfDirectoryAtPath:profilesDir error:nil]) {
        NSString *pidPath = [profilesDir stringByAppendingPathComponent:pid];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:pidPath isDirectory:&isDir] || !isDir) continue;
        for (NSString *sub in @[@"Decript", @"Files"]) {
            NSString *p = [pidPath stringByAppendingPathComponent:sub];
            if ([fm fileExistsAtPath:p]) [roots addObject:p];
        }
    }
    return roots;
}

// ── 扫描所有文件（后台调用） ──
static NSArray *listAllFiles(void) {
    NSMutableArray *files = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in scanRoots()) {
        NSString *source = [root lastPathComponent]; // "Decript" or "Files"
        @try {
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
            if (!e) continue;
            NSString *rp;
            while ((rp = [e nextObject])) {
                @autoreleasepool {
                    NSString *fp = [root stringByAppendingPathComponent:rp];
                    NSDictionary *a = [fm attributesOfItemAtPath:fp error:nil];
                    if (!a || [a[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
                    unsigned long long sz = [a[NSFileSize] unsignedLongLongValue];
                    if (!shouldIncludeFile(fp, sz)) continue;
                    [files addObject:@{
                        @"path":   fp,
                        @"size":   @(sz),
                        @"date":   a[NSFileModificationDate] ?: [NSDate distantPast],
                        @"source": source
                    }];
                }
            }
        } @catch (...) {}
    }
    [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];
    return files;
}

// ============================================================
//  文件浏览器 VC
// ============================================================
@interface FileBrowserVC : UIViewController <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray *allFiles;
@property (nonatomic, strong) NSArray *filteredFiles;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation FileBrowserVC

- (instancetype)initWithFiles:(NSArray *)files {
    if (self = [super init]) {
        _allFiles = files;
        _filteredFiles = files;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择文件导出";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 关闭按钮
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"关闭" style:UIBarButtonItemStyleDone target:self action:@selector(close)];

    // 搜索框
    self.search = [[UISearchBar alloc] initWithFrame:(CGRect){{0,0},{self.view.bounds.size.width,44}}];
    self.search.placeholder = @"输入文件名搜索...";
    self.search.delegate = self;
    self.search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.search.autocorrectionType = UITextAutocorrectionTypeNo;

    // 底部统计
    self.countLabel = [[UILabel alloc] init];
    self.countLabel.font = [UIFont systemFontOfSize:12];
    self.countLabel.textColor = [UIColor grayColor];
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    [self updateCount];

    // 表格 — 使用 subtitle 样式显示目录来源
    self.table = [[UITableView alloc] initWithFrame:(CGRect){{0,0},{0,0}} style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 52;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];

    [self.view addSubview:self.search];
    [self.view addSubview:self.table];
    [self.view addSubview:self.countLabel];

    self.search.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.topAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.countLabel.topAnchor constraintEqualToAnchor:self.table.bottomAnchor],
        [self.countLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.countLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [self.countLabel.heightAnchor constraintEqualToConstant:26],
    ]];
}

- (void)updateCount {
    self.countLabel.text = [NSString stringWithFormat:@"共 %lu 个文件", (unsigned long)self.filteredFiles.count];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// ── Search ──
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    if (text.length == 0) {
        self.filteredFiles = self.allFiles;
    } else {
        NSString *lower = [text lowercaseString];
        self.filteredFiles = [self.allFiles filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, id _) {
                return [[d[@"path"] lastPathComponent].lowercaseString containsString:lower];
            }]];
    }
    [self.table reloadData];
    [self updateCount];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

// ── Table ──
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.filteredFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    NSDictionary *d = self.filteredFiles[ip.row];
    NSString *name = [[d[@"path"] lastPathComponent] copy];
    unsigned long long sz = [d[@"size"] unsignedLongLongValue];
    NSString *source = d[@"source"];

    // 标题：文件名
    c.textLabel.text = name;
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    // 副标题：大小 + 来源目录
    NSString *sizeStr;
    if (sz > 1048576)      sizeStr = [NSString stringWithFormat:@"%.1f MB", sz / 1048576.0];
    else if (sz > 1024)    sizeStr = [NSString stringWithFormat:@"%llu KB", sz / 1024];
    else                   sizeStr = [NSString stringWithFormat:@"%llu B", sz];

    c.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@", sizeStr, source];
    c.detailTextLabel.textColor = [UIColor grayColor];
    c.detailTextLabel.font = [UIFont systemFontOfSize:12];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *d = self.filteredFiles[ip.row];
    [self dismissViewControllerAnimated:YES completion:^{
        [ELKFileExporter shareFileAtPath:d[@"path"]];
    }];
}

@end

// ============================================================
@implementation ELKFileExporter

+ (void)presentFileBrowser {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *files = listAllFiles();
        dispatch_async(dispatch_get_main_queue(), ^{
            FileBrowserVC *vc = [[FileBrowserVC alloc] initWithFiles:files];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            UIViewController *top = [ELKRuntimeHelper topViewController];
            if (top) {
                [top presentViewController:nav animated:YES completion:nil];
            }
        });
    });
}

+ (void)shareFileAtPath:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *shareVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    UIViewController *vc = [ELKRuntimeHelper topViewController];
    if (!vc) return;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
        shareVC.popoverPresentationController) {
        shareVC.popoverPresentationController.sourceView = vc.view;
        shareVC.popoverPresentationController.sourceRect =
            (CGRect){{vc.view.bounds.size.width/2, vc.view.bounds.size.height/2}, {0, 0}};
        shareVC.popoverPresentationController.permittedArrowDirections = 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc presentViewController:shareVC animated:YES completion:nil];
    });
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [ELKRuntimeHelper topViewController];
        if (!vc) return;
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:title message:message
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

@end
