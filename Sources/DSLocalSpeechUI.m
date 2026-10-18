#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <NaturalLanguage/NaturalLanguage.h>
#import <objc/runtime.h>
#import "DSVoiceCatalog.h"
#import "DSLocalStore.h"
#import "DSAPILocalization.h"
extern long long DSAPINativeSpeechMessageID(const void *view);
static void (*originalSpeechLayout)(id,SEL);
static char speechMarkerKey, originalSpeechIconKey;
static NSHashTable *speechViews;
@interface DSNativeSpeaker : NSObject <AVSpeechSynthesizerDelegate>
@property(nonatomic,strong) AVSpeechSynthesizer *synth;
@property(nonatomic) long long messageID;
@property(nonatomic,strong) AVSpeechUtterance *activeUtterance;
+ (instancetype)shared;
- (void)playView:(UIView *)view;
@end
static UIImageView *speechIcon(UIView *view) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIImageView.class]) return (id)child;
        UIImageView *image=speechIcon(child); if (image) return image;
    }
    return nil;
}
static BOOL activeForView(UIView *view) {
    UIView *parent=view;
    while (parent && ![NSStringFromClass(parent.class) hasSuffix:@".AgentMessageView"]) parent=parent.superview;
    DSNativeSpeaker *speaker=DSNativeSpeaker.shared;
    return parent && speaker.activeUtterance && DSAPINativeSpeechMessageID((__bridge void *)parent)==speaker.messageID;
}
static NSString *localSpeechLabel(id self,SEL selector) {
    return DSOriginalLocalized(activeForView(self) ? @"readAloudStopLabel" : @"readAloudStartLabel");
}
static void refreshSpeechIcons(void) {
    for (UIView *view in speechViews) {
        BOOL active=activeForView(view);
        UIImageView *icon=speechIcon(view);
        UIImage *original=objc_getAssociatedObject(view,&originalSpeechIconKey);
        if (!original && icon.image) { original=icon.image; objc_setAssociatedObject(view,&originalSpeechIconKey,original,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        UIImage *target=active ? ([UIImage imageNamed:@"chat/message/tts_stop"] ?: original) : original;
        if (icon.image!=target) icon.image=target;
        view.accessibilityLabel=DSOriginalLocalized(active ? @"readAloudStopLabel" : @"readAloudStartLabel");
    }
}
@implementation DSNativeSpeaker
+ (instancetype)shared {
    static DSNativeSpeaker *speaker; static dispatch_once_t once;
    dispatch_once(&once,^{ speaker=[DSNativeSpeaker new]; speaker.synth=[AVSpeechSynthesizer new];
        speaker.synth.usesApplicationAudioSession=NO; speaker.synth.delegate=speaker; }); return speaker;
}
- (void)playView:(UIView *)view {
    UIView *parent=view;
    while (parent && ![NSStringFromClass(parent.class) hasSuffix:@".AgentMessageView"]) parent=parent.superview;
    long long identifier=parent ? DSAPINativeSpeechMessageID((__bridge void *)parent) : 0;
    if (!identifier) { [NSUserDefaults.standardUserDefaults setObject:@"missing-message-context" forKey:@"DSAPIAdapter.speechStatus"]; return; }
    if (self.messageID==identifier && self.activeUtterance) {
        [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate]; self.messageID=0; self.activeUtterance=nil;
        [NSUserDefaults.standardUserDefaults setObject:@"stopped" forKey:@"DSAPIAdapter.speechStatus"]; refreshSpeechIcons(); return;
    }
    NSDictionary *message=nil;
    for (NSDictionary *session in DSLocalStore.shared.sessions) {
        message=[DSLocalStore.shared message:@(identifier) session:session[@"id"]]; if (message) break;
    }
    NSMutableString *text=[NSMutableString string];
    for (NSDictionary *fragment in message[@"fragments"]) if ([fragment[@"type"] isEqual:@"RESPONSE"] && [fragment[@"content"] isKindOfClass:NSString.class]) [text appendString:fragment[@"content"]];
    if (!text.length) return;
    [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *utterance=[AVSpeechUtterance speechUtteranceWithString:text];
    AVSpeechSynthesisVoice *selected=[AVSpeechSynthesisVoice voiceWithIdentifier:DSSelectedLocalVoice()];
    NLLanguageRecognizer *recognizer=[NLLanguageRecognizer new];
    NSRange sample=[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,MIN(text.length,2000))];
    [recognizer processString:[text substringWithRange:sample]];
    NSString *language=recognizer.dominantLanguage;
    NSString *base=[language componentsSeparatedByString:@"-"].firstObject;
    if (base.length && ![base isEqual:@"und"] && ![selected.language hasPrefix:base]) {
        NSString *voiceLanguage=@{@"zh-Hans":@"zh-CN",@"zh-Hant":@"zh-TW",@"yue":@"zh-HK"}[language] ?: language;
        AVSpeechSynthesisVoice *matching=[AVSpeechSynthesisVoice voiceWithLanguage:voiceLanguage];
        if (matching) selected=matching;
    }
    utterance.voice=selected;
    self.messageID=identifier; self.activeUtterance=utterance;
    [NSUserDefaults.standardUserDefaults setObject:@"requested" forKey:@"DSAPIAdapter.speechStatus"];
    [NSUserDefaults.standardUserDefaults setInteger:identifier forKey:@"DSAPIAdapter.lastSpokenMessageID"];
    [NSUserDefaults.standardUserDefaults setObject:selected.identifier ?: @"default" forKey:@"DSAPIAdapter.lastSpeechVoice"];
    [self.synth speakUtterance:utterance];
    refreshSpeechIcons();
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    [NSUserDefaults.standardUserDefaults setObject:@"started" forKey:@"DSAPIAdapter.speechStatus"]; refreshSpeechIcons();
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance==self.activeUtterance) { self.messageID=0; self.activeUtterance=nil;
        [NSUserDefaults.standardUserDefaults setObject:@"finished" forKey:@"DSAPIAdapter.speechStatus"]; }
    refreshSpeechIcons();
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (utterance==self.activeUtterance) { self.messageID=0; self.activeUtterance=nil; }
    refreshSpeechIcons();
}
@end
static void localSpeechLayout(id self,SEL selector) {
    if (originalSpeechLayout) originalSpeechLayout(self,selector);
    UIView *view=self;
    if (!objc_getAssociatedObject(view,&speechMarkerKey)) {
        view.isAccessibilityElement=YES; view.accessibilityTraits=UIAccessibilityTraitButton; view.accessibilityIdentifier=@"DSAPI.ReadAloud";
        objc_setAssociatedObject(view,&speechMarkerKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [speechViews addObject:view];
    }
    refreshSpeechIcons();
}
static BOOL activateLocalSpeech(id self,SEL selector) { [DSNativeSpeaker.shared playView:self]; return YES; }
static void tapLocalSpeech(id self,SEL selector) { [DSNativeSpeaker.shared playView:self]; }
void DSInstallLocalSpeechUI(void) {
    speechViews=[NSHashTable weakObjectsHashTable];
    Class cls=NSClassFromString(@"_TtC13DeepSeek_Chat13TTSButtonView");
    Method method=class_getInstanceMethod(cls,@selector(layoutSubviews));
    if (!method) return;
    originalSpeechLayout=(void *)method_getImplementation(method);
    if (!class_addMethod(cls,@selector(layoutSubviews),(IMP)localSpeechLayout,method_getTypeEncoding(method)))
        class_replaceMethod(cls,@selector(layoutSubviews),(IMP)localSpeechLayout,method_getTypeEncoding(method));
    if (!class_addMethod(cls,@selector(accessibilityActivate),(IMP)activateLocalSpeech,"B@:"))
        class_replaceMethod(cls,@selector(accessibilityActivate),(IMP)activateLocalSpeech,"B@:");
    // Keep accessibility state consistent even when the native configuration refreshes.
    if (!class_addMethod(cls,@selector(accessibilityLabel),(IMP)localSpeechLabel,"@@:"))
        class_replaceMethod(cls,@selector(accessibilityLabel),(IMP)localSpeechLabel,"@@:");
    // The supplied DSButton installs objcOnTap as its native gesture action.
    // Override only this subclass's action, preserving its original recognizer.
    SEL tap=NSSelectorFromString(@"objcOnTap");
    if (class_getInstanceMethod(cls,tap)) {
        if (!class_addMethod(cls,tap,(IMP)tapLocalSpeech,"v@:")) class_replaceMethod(cls,tap,(IMP)tapLocalSpeech,"v@:");
    }
}
