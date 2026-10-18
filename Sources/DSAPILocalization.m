#import "DSAPILocalization.h"
static NSString *const DSLanguageKey=@"DSAPIAdapter.nativeLanguage";
static NSBundle *DSLanguageBundle(void) {
    NSString *language=[NSUserDefaults.standardUserDefaults stringForKey:DSLanguageKey] ?: NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    NSString *path=[NSBundle.mainBundle pathForResource:language ofType:@"lproj"];
    return path ? [NSBundle bundleWithPath:path] : NSBundle.mainBundle;
}
NSString *DSOriginalLocalized(NSString *key) {
    return [DSLanguageBundle() localizedStringForKey:key value:nil table:nil];
}
BOOL DSObserveNativeSettingsLanguage(NSArray<NSString *> *texts) {
    NSSet *observed=[NSSet setWithArray:texts];
    NSString *previous=[NSUserDefaults.standardUserDefaults stringForKey:DSLanguageKey];
    NSString *best=previous ?: NSBundle.mainBundle.preferredLocalizations.firstObject;
    NSUInteger highest=0;
    NSArray *keys=@[@"app_language",@"fontSize",@"personalization",@"profileCheckForUpdates",@"accountAudioInputLanguage"];
    for (NSString *language in NSBundle.mainBundle.localizations) {
        NSBundle *bundle=[NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:language ofType:@"lproj"]];
        if (!bundle) continue;
        NSUInteger score=0;
        for (NSString *key in keys) {
            NSString *value=[bundle localizedStringForKey:key value:nil table:nil];
            if (![value isEqual:key] && [observed containsObject:value]) score++;
        }
        if (score>highest || (score==highest && [language isEqual:previous])) { highest=score; best=language; }
    }
    if (highest<2 || !best.length || [best isEqual:previous]) return NO;
    [NSUserDefaults.standardUserDefaults setObject:best forKey:DSLanguageKey];
    return YES;
}
NSString *DSAPILocalized(NSString *key) {
    if ([key isEqual:@"settings"]) return DSOriginalLocalized(@"settings");
    static NSDictionary *words; static dispatch_once_t once;
    dispatch_once(&once, ^{
        words=@{
          @"api":@[@"API Settings",@"API 设置",@"API 設定"],
          @"usage":@[@"API Usage",@"用量统计",@"用量統計"],
          @"connection":@[@"Connection",@"连接",@"連線"],
          @"models":@[@"Models",@"模型",@"模型"],
          @"advanced":@[@"Advanced",@"高级",@"進階"],
          @"model":@[@"Model",@"模型名",@"模型名稱"],
          @"thinkingModel":@[@"Thinking model (optional)",@"思考模型（可选）",@"思考模型（選填）"],
          @"systemPrompt":@[@"System prompt (optional)",@"系统提示词（可选）",@"系統提示詞（選填）"],
          @"timeout":@[@"Timeout (seconds)",@"请求超时（秒）",@"請求逾時（秒）"],
          @"connectionNote":@[@"Use your provider’s HTTPS Base URL or full /chat/completions URL. The key is stored only in this device’s Keychain.",@"填写服务提供方的 HTTPS Base URL，或完整 /chat/completions 地址。API Key 仅保存到此设备的钥匙串。",@"填寫服務提供者的 HTTPS Base URL，或完整 /chat/completions 位址。API Key 僅儲存於此裝置的鑰匙圈。"],
          @"modelNote":@[@"An optional thinking model can be selected separately. DeepSeek’s thinking mode follows the original Think switch.",@"可单独指定思考模型。DeepSeek 官方模型的思考模式跟随原界面的“思考”开关。",@"可另行指定思考模型。DeepSeek 官方模型的思考模式跟隨原介面的「思考」開關。"],
          @"advancedNote":@[@"Timeout: 10–3600 seconds. The system prompt is prepended to the message history.",@"超时范围 10–3600 秒。系统提示词会加入消息历史的开头。",@"逾時範圍 10–3600 秒。系統提示詞會加入訊息記錄的開頭。"],
          @"saveError":@[@"Unable to save",@"无法保存",@"無法儲存"],
          @"ok":@[@"OK",@"好",@"好"],
          @"invalidURL":@[@"Base URL must use HTTPS and contain no username, password, query or fragment.",@"Base URL 必须是 HTTPS 地址，且不能包含用户名、密码、查询参数或片段。",@"Base URL 必須使用 HTTPS，且不可包含使用者名稱、密碼、查詢參數或片段。"],
          @"invalidFields":@[@"Enter a model name. Timeout must be 10–3600 seconds. API keys cannot contain line breaks.",@"请填写模型名；超时范围为 10–3600 秒；API Key 不能包含换行。",@"請填寫模型名稱；逾時範圍為 10–3600 秒；API Key 不可包含換行。"],
          @"keychainError":@[@"Unable to save the API key to this device’s Keychain.",@"无法将 API Key 保存到设备钥匙串。",@"無法將 API Key 儲存於裝置的鑰匙圈。"],
          @"requests":@[@"Total requests",@"请求总数",@"請求總數"],
          @"succeeded":@[@"Succeeded",@"成功",@"成功"],
          @"failed":@[@"Failed",@"失败",@"失敗"],
          @"cancelled":@[@"Cancelled",@"已取消",@"已取消"],
          @"prompt_tokens":@[@"Input tokens",@"输入 Token",@"輸入 Token"],
          @"completion_tokens":@[@"Output tokens",@"输出 Token",@"輸出 Token"],
          @"total_tokens":@[@"Total tokens",@"Token 总量",@"Token 總量"],
          @"unreported_requests":@[@"Requests without usage data",@"未返回用量的请求",@"未回傳用量的請求"],
          @"recent":@[@"Recent requests",@"最近请求",@"最近請求"],
          @"usageNote":@[@"Token counts come from API usage reports. Missing usage is not estimated. This page stores no messages or API keys; it is not a billing statement.",@"Token 按 API 返回的 usage 累计；未返回的用量不会估算。本页不保存消息或密钥，也不代表服务商账单。",@"Token 依 API 回傳的 usage 累計；未回傳的用量不會估算。本頁不儲存訊息或金鑰，亦不代表服務商帳單。"]
        };
    });
    NSString *language=[NSUserDefaults.standardUserDefaults stringForKey:DSLanguageKey] ?: NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    NSUInteger index=[language hasPrefix:@"zh"] ? ([language containsString:@"Hant"] || [language containsString:@"TW"] || [language containsString:@"HK"] ? 2 : 1) : 0;
    NSArray *values=words[key];
    return values ? values[index] : key;
}
