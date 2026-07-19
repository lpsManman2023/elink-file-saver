//
//  ELKFileExporter.m
//  ELKFileSaver - v17 全功能版
//
#import "ELKFileExporter.h"
#import "ELKMenuHook.h"
#import "ELKRuntimeHelper.h"
#import <QuickLook/QuickLook.h>

// ── 10秒缓存 ──
static NSArray *g_cachedFiles = nil;
static NSDate *g_cacheTime = nil;
static NSUInteger g_cachedCount = 0;

// ── 文件 emoji 图标 ──
static NSString *fileIcon(NSString *name) {
    NSString *ext = [[name pathExtension] lowercaseString];
    if (ext.length == 0) return @"📎";
    if ([ext isEqualToString:@"pdf"])                         return @"📕";
    if ([ext isEqualToString:@"doc"]||[ext isEqualToString:@"docx"]) return @"📝";
    if ([ext isEqualToString:@"xls"]||[ext isEqualToString:@"xlsx"]||[ext isEqualToString:@"csv"]) return @"📊";
    if ([ext isEqualToString:@"ppt"]||[ext isEqualToString:@"pptx"]) return @"📽️";
    if ([ext isEqualToString:@"txt"]||[ext isEqualToString:@"rtf"]) return @"📄";
    if ([ext isEqualToString:@"png"]||[ext isEqualToString:@"jpg"]||[ext isEqualToString:@"jpeg"]||
        [ext isEqualToString:@"gif"]||[ext isEqualToString:@"bmp"]||[ext isEqualToString:@"heic"]||
        [ext isEqualToString:@"webp"]) return @"🖼️";
    if ([ext isEqualToString:@"mp4"]||[ext isEqualToString:@"mov"]||[ext isEqualToString:@"m4v"]) return @"🎬";
    if ([ext isEqualToString:@"mp3"]||[ext isEqualToString:@"m4a"]||[ext isEqualToString:@"wav"]||
        [ext isEqualToString:@"aac"]) return @"🎵";
    if ([ext isEqualToString:@"zip"]||[ext isEqualToString:@"rar"]||[ext isEqualToString:@"7z"]) return @"📦";
    if ([ext isEqualToString:@"dwg"]||[ext isEqualToString:@"dxf"]||[ext isEqualToString:@"dgn"]) return @"📐";
    return @"📎";
}

// ── 纯数字文件名检测 ──
static BOOL isNumericName(NSString *name) {
    NSString *base = [name stringByDeletingPathExtension];
    if (base.length == 0) return NO;
    return [base rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
}

// ── 方案4过滤 ──
static BOOL shouldIncludeFile(NSString *path, unsigned long long size) {
    if (size < 100) return NO;
    NSString *name = [path lastPathComponent];
    NSString *ext = [[name pathExtension] lowercaseString];
    if (ext.length > 0) return YES;
    if (isNumericName(name)) return NO;
    if (size > 100000) return YES;
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

// ── 扫描所有文件 ──
static NSArray *listAllFiles(BOOL forceRefresh) {
    if (!forceRefresh && g_cachedFiles && g_cacheTime &&
        [[NSDate date] timeIntervalSinceDate:g_cacheTime] < 10.0) {
        return g_cachedFiles;
    }
    NSMutableArray *files = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in scanRoots()) {
        NSString *source = [root lastPathComponent];
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
    g_cachedFiles = files;
    g_cacheTime = [NSDate date];
    g_cachedCount = files.count;
    return files;
}

// ── 分类定义 ──
static NSArray *catDefs(void) {
    return @[
        @{@"title":@"全部",   @"exts":@[]},
        @{@"title":@"📄 文档", @"exts":@[@"pdf",@"doc",@"docx",@"txt",@"rtf",@"ppt",@"pptx"]},
        @{@"title":@"📊 表格", @"exts":@[@"xls",@"xlsx",@"csv"]},
        @{@"title":@"🖼️ 图片", @"exts":@[@"png",@"jpg",@"jpeg",@"gif",@"bmp",@"heic",@"webp"]},
        @{@"title":@"📦 压缩", @"exts":@[@"zip",@"rar",@"7z"]},
        @{@"title":@"📐 CAD",  @"exts":@[@"dwg",@"dxf",@"dgn"]},
    ];
}

static BOOL fileMatchesCat(NSDictionary *file, NSDictionary *cat) {
    NSArray *exts = cat[@"exts"];
    if (exts.count == 0) return YES;
    NSString *ext = [[file[@"path"] pathExtension] lowercaseString];
    return [exts containsObject:ext];
}

// ── 日期格式化 ──
static NSString *shortDate(NSDate *d) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"MM/dd HH:mm";
    return [f stringFromDate:d];
}

// ============================================================
//  文件浏览器 VC（全功能版）
// ============================================================
@interface FileBrowserVC : UIViewController <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate, QLPreviewControllerDataSource>
@property (nonatomic, strong) NSArray *allFiles;
@property (nonatomic, strong) NSArray *filteredFiles;
@property (nonatomic, strong) NSMutableSet *selectedPaths;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) UIScrollView *catBar;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIToolbar *editToolbar;
@property (nonatomic, assign) NSInteger activeCat;
@property (nonatomic, assign) BOOL editMode;
@property (nonatomic, strong) NSString *searchText;
@property (nonatomic, copy)   NSString *previewPath;
@end

@implementation FileBrowserVC

- (instancetype)initWithFiles:(NSArray *)files {
    if (self = [super init]) {
        _allFiles = files;
        _filteredFiles = files;
        _selectedPaths = [NSMutableSet set];
        _activeCat = 0;
        _searchText = @"";
        _editMode = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"📁 文件浏览器";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 左按钮：选择/取消
    [self updateLeftButton];
    // 右按钮：⚙️ 设置 + ✕ 关闭
    UIBarButtonItem *settingsBtn = [[UIBarButtonItem alloc]
        initWithTitle:@"⚙️" style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
    UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc]
        initWithTitle:@"✕" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems = @[closeBtn, settingsBtn];

    // 搜索框
    self.search = [[UISearchBar alloc] initWithFrame:(CGRect){{0,0},{self.view.bounds.size.width,44}}];
    self.search.placeholder = @"🔍 输入文件名搜索...";
    self.search.delegate = self;
    self.search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.search.autocorrectionType = UITextAutocorrectionTypeNo;

    // 恢复上次搜索
    NSString *lastSearch = [[NSUserDefaults standardUserDefaults] stringForKey:@"meow_search"];
    if (lastSearch.length > 0) {
        self.search.text = lastSearch;
        self.searchText = lastSearch;
    }

    // 分类标签栏
    self.catBar = [[UIScrollView alloc] initWithFrame:(CGRect){{0,0},{self.view.bounds.size.width,38}}];
    self.catBar.showsHorizontalScrollIndicator = NO;
    self.catBar.backgroundColor = [UIColor systemBackgroundColor];
    [self buildCatButtons];

    // 表格
    self.table = [[UITableView alloc] initWithFrame:(CGRect){{0,0},{0,0}} style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 60;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];

    // 长按预览
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.4;
    [self.table addGestureRecognizer:lp];

    // 下拉刷新
    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];
    self.table.refreshControl = rc;

    // 加载动画
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.hidesWhenStopped = YES;

    // 底部统计
    self.countLabel = [[UILabel alloc] init];
    self.countLabel.font = [UIFont systemFontOfSize:12];
    self.countLabel.textColor = [UIColor grayColor];
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    [self updateCount];

    // 多选工具栏
    self.editToolbar = [[UIToolbar alloc] init];
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc] initWithTitle:@"导出选中 (0)"
                                                                  style:UIBarButtonItemStyleDone
                                                                 target:self action:@selector(exportSelected)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.editToolbar.items = @[flex, exportBtn];
    self.editToolbar.hidden = YES;

    // 空状态
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"🐱 没有找到喵～\n试试换个关键词";
    self.emptyLabel.numberOfLines = 2;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor lightGrayColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:16];

    [self.view addSubview:self.search];
    [self.view addSubview:self.catBar];
    [self.view addSubview:self.table];
    [self.view addSubview:self.countLabel];
    [self.view addSubview:self.emptyLabel];
    [self.view addSubview:self.spinner];
    [self.view addSubview:self.editToolbar];

    self.search.translatesAutoresizingMaskIntoConstraints = NO;
    self.catBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.editToolbar.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.catBar.topAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.catBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.catBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.catBar.heightAnchor constraintEqualToConstant:38],
        [self.table.topAnchor constraintEqualToAnchor:self.catBar.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.editToolbar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-44],
        [self.editToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.editToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.editToolbar.heightAnchor constraintEqualToConstant:44],
        [self.countLabel.topAnchor constraintEqualToAnchor:self.table.bottomAnchor],
        [self.countLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.countLabel.bottomAnchor constraintEqualToAnchor:self.editMode ? self.editToolbar.topAnchor : self.view.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [self.countLabel.heightAnchor constraintEqualToConstant:26],
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    // 应用 filter
    [self applyFilters];
}

// ── 分类按钮 ──
- (void)buildCatButtons {
    [self.catBar.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSArray *cats = catDefs();
    CGFloat x = 0;
    for (NSInteger i = 0; i < (NSInteger)cats.count; i++) {
        NSString *title = cats[i][@"title"];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        b.tag = i;
        [b addTarget:self action:@selector(onCatTap:) forControlEvents:UIControlEventTouchUpInside];
        [b sizeToFit];
        b.frame = (CGRect){{x, 4},{b.bounds.size.width + 16, 30}};
        b.layer.cornerRadius = 15;
        b.layer.borderWidth = 1;
        b.layer.borderColor = [UIColor systemBlueColor].CGColor;
        b.layer.backgroundColor = (i == self.activeCat) ? [UIColor systemBlueColor].CGColor : [UIColor clearColor].CGColor;
        [b setTitleColor:(i == self.activeCat) ? [UIColor whiteColor] : [UIColor systemBlueColor] forState:UIControlStateNormal];
        x += b.bounds.size.width + 8;
        [self.catBar addSubview:b];
    }
    self.catBar.contentSize = (CGSize){x + 8, 38};
}

- (void)onCatTap:(UIButton *)sender {
    self.activeCat = sender.tag;
    [self buildCatButtons];
    [self applyFilters];
}

// ── 过滤逻辑 ──
- (void)applyFilters {
    NSArray *result = self.allFiles;
    NSDictionary *cat = catDefs()[self.activeCat];

    if ([cat[@"exts"] count] > 0) {
        result = [result filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, id _) {
                return fileMatchesCat(d, cat);
            }]];
    }

    if (self.searchText.length > 0) {
        NSString *lower = [self.searchText lowercaseString];
        result = [result filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, id _) {
                return [[d[@"path"] lastPathComponent].lowercaseString containsString:lower];
            }]];
    }

    self.filteredFiles = result;
    [self.table reloadData];
    [self updateCount];
}

// ── Search ──
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    self.searchText = text;
    // 保存搜索历史
    [[NSUserDefaults standardUserDefaults] setObject:text forKey:@"meow_search"];
    [self applyFilters];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

// ── 下拉刷新 ──
- (void)onRefresh {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *fresh = listAllFiles(YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allFiles = fresh;
            [self applyFilters];
            [self.table.refreshControl endRefreshing];
        });
    });
}

// ── 长按预览 ──
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [gr locationInView:self.table];
    NSIndexPath *ip = [self.table indexPathForRowAtPoint:p];
    if (!ip) return;
    NSDictionary *d = self.filteredFiles[ip.row];
    NSString *path = d[@"path"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    // 临时保存路径供 QLPreviewItem 使用
    self.previewPath = path;
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    ql.currentPreviewItemIndex = 0;
    [self presentViewController:ql animated:YES completion:nil];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)c {
    return 1;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)c previewItemAtIndex:(NSInteger)i {
    return [NSURL fileURLWithPath:self.previewPath];
}

// ── 多选 ──
- (void)updateLeftButton {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:self.editMode ? @"取消" : @"选择"
        style:UIBarButtonItemStylePlain
        target:self action:@selector(toggleEditMode)];
}

- (void)toggleEditMode {
    self.editMode = !self.editMode;
    [self.selectedPaths removeAllObjects];
    self.editToolbar.hidden = !self.editMode;
    [self updateLeftButton];
    [self updateCount];
    [self.table reloadData];

    // 调整 countLabel 位置
    [self.countLabel removeFromSuperview];
    [self.view addSubview:self.countLabel];
    [NSLayoutConstraint deactivateConstraints:self.countLabel.constraints];
    NSLayoutConstraint *bottomAnchor = [self.countLabel.bottomAnchor constraintEqualToAnchor:
        self.editMode ? self.editToolbar.topAnchor : self.view.safeAreaLayoutGuide.bottomAnchor constant:-4];
    bottomAnchor.active = YES;
    [self.countLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.countLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [self.countLabel.heightAnchor constraintEqualToConstant:26].active = YES;
}

- (void)exportSelected {
    NSArray *paths = [self.selectedPaths allObjects];
    if (paths.count == 0) return;
    if (paths.count == 1) {
        [self dismissViewControllerAnimated:YES completion:^{
            [ELKFileExporter shareFileAtPath:paths.firstObject];
        }];
    } else {
        [self dismissViewControllerAnimated:YES completion:^{
            [ELKFileExporter shareFilesAtPaths:paths];
        }];
    }
}

- (void)updateCount {
    if (self.editMode) {
        self.countLabel.text = [NSString stringWithFormat:@"已选 %lu / %lu 个文件",
            (unsigned long)self.selectedPaths.count, (unsigned long)self.filteredFiles.count];
        UIBarButtonItem *btn = self.editToolbar.items.lastObject;
        btn.title = [NSString stringWithFormat:@"导出选中 (%lu)", (unsigned long)self.selectedPaths.count];
    } else {
        self.countLabel.text = [NSString stringWithFormat:@"共 %lu 个文件", (unsigned long)self.filteredFiles.count];
    }
    self.emptyLabel.hidden = (self.filteredFiles.count > 0);
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openSettings {
    [ELKFileExporter presentSettings];
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
    NSDate *date = d[@"date"];

    c.textLabel.text = [NSString stringWithFormat:@"%@  %@", fileIcon(name), name];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSString *sizeStr;
    if (sz > 1048576)      sizeStr = [NSString stringWithFormat:@"%.1f MB", sz/1048576.0];
    else if (sz > 1024)    sizeStr = [NSString stringWithFormat:@"%llu KB", sz/1024];
    else                   sizeStr = [NSString stringWithFormat:@"%llu B", sz];

    c.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@  ·  %@", sizeStr, source, shortDate(date)];
    c.detailTextLabel.textColor = [UIColor grayColor];
    c.detailTextLabel.font = [UIFont systemFontOfSize:12];

    // 多选模式
    if (self.editMode) {
        BOOL sel = [self.selectedPaths containsObject:d[@"path"]];
        c.accessoryType = sel ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *d = self.filteredFiles[ip.row];
    NSString *path = d[@"path"];

    if (self.editMode) {
        if ([self.selectedPaths containsObject:path]) {
            [self.selectedPaths removeObject:path];
        } else {
            [self.selectedPaths addObject:path];
        }
        [self.table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
        [self updateCount];
    } else {
        [self dismissViewControllerAnimated:YES completion:^{
            [ELKFileExporter shareFileAtPath:path];
        }];
    }
}

@end

// ============================================================
//  设置页 VC
// ============================================================
@interface SettingsVC : UIViewController
@end

@implementation SettingsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"⚙️ 喵喵设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"✕" style:UIBarButtonItemStylePlain target:self action:@selector(close)];

    CGFloat w = self.view.bounds.size.width;

    // ── 水印开关 ──
    UILabel *wmLbl = [[UILabel alloc] initWithFrame:(CGRect){{16,100},{w-32,22}}];
    wmLbl.text = @"🔒 去水印";
    wmLbl.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:wmLbl];

    UILabel *wmDesc = [[UILabel alloc] initWithFrame:(CGRect){{16,124},{w-32,40}}];
    wmDesc.text = @"搜索包含「耿娟」「6789」的半透明覆盖视图并隐藏；\n未命中时走视觉特征兜底（全屏+半透明+无交互）。";
    wmDesc.font = [UIFont systemFontOfSize:11];
    wmDesc.textColor = [UIColor grayColor];
    wmDesc.numberOfLines = 3;
    [self.view addSubview:wmDesc];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:(CGRect){{w - 67, 95},{0,0}}];
    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"meow_watermark_hidden"];
    [sw addTarget:self action:@selector(onWatermarkToggle:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:sw];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onWatermarkToggle:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"meow_watermark_hidden"];
    if (sw.on) {
        [ELKMenuHook hideWatermarksIfEnabled];
    } else {
        [ELKMenuHook showAllWatermarks];
    }
}

@end

// ============================================================
@implementation ELKFileExporter

+ (void)preloadFileList {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        listAllFiles(NO);
    });
}

+ (NSUInteger)cachedFileCount {
    return g_cachedCount;
}

+ (void)presentSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        SettingsVC *vc = [[SettingsVC alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        UIViewController *top = [ELKRuntimeHelper topViewController];
        if (top) [top presentViewController:nav animated:YES completion:nil];
    });
}

+ (void)presentFileBrowser {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *files = listAllFiles(NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            FileBrowserVC *vc = [[FileBrowserVC alloc] initWithFiles:files];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            UIViewController *top = [ELKRuntimeHelper topViewController];
            if (top) [top presentViewController:nav animated:YES completion:nil];
        });
    });
}

+ (void)shareFileAtPath:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *s = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    UIViewController *vc = [ELKRuntimeHelper topViewController];
    if (!vc) return;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad && s.popoverPresentationController) {
        s.popoverPresentationController.sourceView = vc.view;
        s.popoverPresentationController.sourceRect = (CGRect){{vc.view.bounds.size.width/2,vc.view.bounds.size.height/2},{0,0}};
        s.popoverPresentationController.permittedArrowDirections = 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc presentViewController:s animated:YES completion:nil];
    });
}

+ (void)shareFilesAtPaths:(NSArray *)paths {
    NSMutableArray *urls = [NSMutableArray array];
    for (NSString *p in paths) {
        [urls addObject:[NSURL fileURLWithPath:p]];
    }
    UIActivityViewController *s = [[UIActivityViewController alloc]
        initWithActivityItems:urls applicationActivities:nil];
    UIViewController *vc = [ELKRuntimeHelper topViewController];
    if (!vc) return;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad && s.popoverPresentationController) {
        s.popoverPresentationController.sourceView = vc.view;
        s.popoverPresentationController.sourceRect = (CGRect){{vc.view.bounds.size.width/2,vc.view.bounds.size.height/2},{0,0}};
        s.popoverPresentationController.permittedArrowDirections = 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc presentViewController:s animated:YES completion:nil];
    });
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [ELKRuntimeHelper topViewController];
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

@end
