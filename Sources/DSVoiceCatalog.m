#import "DSVoiceCatalog.h"
#import "DSAPILocalization.h"
#import <AVFoundation/AVFoundation.h>
static NSString *const DSVoiceKey=@"DSAPIAdapter.speechVoice";
NSString *DSSelectedLocalVoice(void) {
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:DSVoiceKey];
    if ([AVSpeechSynthesisVoice voiceWithIdentifier:saved ?: @""]) return saved;
    NSString *locale=[DSOriginalLocalized(@"locale") stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return [AVSpeechSynthesisVoice voiceWithLanguage:locale].identifier ?: [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"].identifier ?: @"";
}
BOOL DSSelectLocalVoice(NSString *identifier) {
    if (![AVSpeechSynthesisVoice voiceWithIdentifier:identifier]) return NO;
    [NSUserDefaults.standardUserDefaults setObject:identifier forKey:DSVoiceKey]; return YES;
}
NSDictionary *DSLocalVoiceConfiguration(void) {
    NSString *selected=DSSelectedLocalVoice();
    NSString *language=[[DSOriginalLocalized(@"locale") stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"].firstObject;
    NSMutableArray *voices=[NSMutableArray array];
    for (AVSpeechSynthesisVoice *voice in AVSpeechSynthesisVoice.speechVoices) {
        if (![voice.identifier isEqual:selected] && (![voice.language hasPrefix:language] || voice.quality!=AVSpeechSynthesisVoiceQualityDefault)) continue;
        NSString *escaped=[voice.identifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
        NSString *url=[@"https://chat.deepseek.com/api/v0/chat/tts/local_demo/" stringByAppendingString:escaped];
        NSMutableDictionary *names=[NSMutableDictionary dictionary], *descriptions=[NSMutableDictionary dictionary], *demos=[NSMutableDictionary dictionary];
        NSString *description=[NSLocale.currentLocale localizedStringForLocaleIdentifier:voice.language] ?: voice.language;
        for (NSString *locale in [NSBundle.mainBundle.localizations arrayByAddingObjectsFromArray:@[@"en",@"en-US",@"zh",@"zh-CN",@"zh-TW",@"zh-Hans",@"zh-Hant"]]) {
            names[locale]=voice.name; descriptions[locale]=description; demos[locale]=url;
        }
        [voices addObject:@{@"voice_id":voice.identifier,@"name_i18n":names,@"description_i18n":descriptions,
            @"languages":@[voice.language],@"demo_urls":demos,@"is_default":@([voice.identifier isEqual:selected]),
            @"color_palette":@{@"c1":@"#496BFF",@"c2":@"#95ACFF",@"c3":@"#E5EAFF"}}];
    }
    return @{@"voices":voices,@"default_voice_id":selected,@"current_voice_id":selected};
}
@interface DSVoiceDemoJob : NSObject
@property(nonatomic,strong) AVSpeechSynthesizer *synth;
@property(nonatomic,strong) AVAudioFile *file;
@property(nonatomic,strong) NSURL *url;
@property(nonatomic,copy) void (^completion)(NSData *,NSError *);
@property(nonatomic) BOOL finished;
- (void)finish:(NSError *)error;
@end
static NSMutableSet *DSDemoJobs(void) {
    static NSMutableSet *jobs; static dispatch_once_t once; dispatch_once(&once,^{ jobs=[NSMutableSet set]; }); return jobs;
}
@implementation DSVoiceDemoJob
- (void)finish:(NSError *)error {
    @synchronized (self) {
        if (self.finished) return; self.finished=YES; self.file=nil;
        NSData *data=error ? nil : [NSData dataWithContentsOfURL:self.url];
        dispatch_async(dispatch_get_main_queue(),^{
            [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate]; self.synth=nil;
            if (self.completion) self.completion(data,error ?: (data.length ? nil : [NSError errorWithDomain:@"DSAPI.Speech" code:1 userInfo:nil]));
            self.completion=nil; [NSFileManager.defaultManager removeItemAtURL:self.url error:NULL]; [DSDemoJobs() removeObject:self];
        });
    }
}
@end
void DSGenerateLocalVoiceDemo(NSString *identifier,void (^completion)(NSData *,NSError *)) {
    AVSpeechSynthesisVoice *voice=[AVSpeechSynthesisVoice voiceWithIdentifier:identifier];
    if (!voice) { completion(nil,[NSError errorWithDomain:@"DSAPI.Speech" code:2 userInfo:nil]); return; }
    DSVoiceDemoJob *job=[DSVoiceDemoJob new]; job.completion=completion;
    job.url=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".caf"]];
    job.synth=[AVSpeechSynthesizer new]; [DSDemoJobs() addObject:job];
    AVSpeechUtterance *utterance=[AVSpeechUtterance speechUtteranceWithString:[voice.language hasPrefix:@"zh"] ? @"你好，这是朗读音色试听。" : @"Hello. This is a preview of the selected voice."];
    utterance.voice=voice; utterance.rate=AVSpeechUtteranceDefaultSpeechRate;
    [job.synth writeUtterance:utterance toBufferCallback:^(AVAudioBuffer *buffer) {
        @synchronized (job) {
            if (job.finished) return;
            if (![buffer isKindOfClass:AVAudioPCMBuffer.class]) { [job finish:[NSError errorWithDomain:@"DSAPI.Speech" code:3 userInfo:nil]]; return; }
            AVAudioPCMBuffer *pcm=(id)buffer;
            if (!pcm.frameLength) { [job finish:nil]; return; }
            NSError *error=nil;
            if (!job.file) job.file=[[AVAudioFile alloc] initForWriting:job.url settings:pcm.format.settings commonFormat:pcm.format.commonFormat interleaved:pcm.format.interleaved error:&error];
            if (!job.file || ![job.file writeFromBuffer:pcm error:&error]) [job finish:error ?: [NSError errorWithDomain:@"DSAPI.Speech" code:4 userInfo:nil]];
        }
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [job finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
    });
}
