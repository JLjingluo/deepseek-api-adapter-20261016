#import "DSAPILocalization.h"
static NSString *const DSLanguageKey=@"DSAPIAdapter.nativeLanguage";
static NSString *DSCurrentLanguage(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *preferred=NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    NSString *previous=[defaults stringForKey:@"DSAPIAdapter.preferredLanguage"];
    if (![preferred isEqual:previous]) {
        [defaults setObject:preferred forKey:@"DSAPIAdapter.preferredLanguage"];
        [defaults removeObjectForKey:DSLanguageKey];
    }
    return [defaults stringForKey:DSLanguageKey] ?: preferred;
}
static NSBundle *DSLanguageBundle(void) {
    NSString *language=DSCurrentLanguage();
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
          @"historySync":@[@"Account history sync",@"原账号历史同步",@"原帳號歷史同步"],
          @"skipLogin":@[@"Skip sign in",@"跳过登录",@"跳過登入"],
          @"signInRequired":@[@"Sign in or use API",@"登录或使用 API",@"登入或使用 API"],
          @"signInNote":@[@"You have not signed in. Sign in to use the original service, or configure your own API in Settings.",@"你还没有登录。登录后可使用原服务，也可以前往设置启用自己的 API。",@"你還沒有登入。登入後可使用原服務，也可以前往設定啟用自己的 API。"],
          @"useAPI":@[@"Use API",@"使用 API",@"使用 API"],
          @"showAPIInChat":@[@"Show API in conversations",@"在对话中显示 API",@"在對話中顯示 API"],
          @"providers":@[@"Provider preset",@"服务商预设",@"服務商預設"],
          @"customProvider":@[@"Custom OpenAI-compatible API",@"自定义 OpenAI 兼容接口",@"自訂 OpenAI 相容介面"],
          @"providerNote":@[@"Presets fill the address and a suggested model. Enter your own API key. Changing provider clears the unsaved key field; nothing is sent until you request models or send a message.",@"预设填写地址和建议模型，密钥需自行输入。切换服务商会清空尚未保存的密钥输入框；获取模型或发送消息时才会请求接口。",@"預設填寫位址及建議模型，金鑰需自行輸入。切換服務商會清空尚未儲存的金鑰欄位；取得模型或傳送訊息時才會請求介面。"],
          @"automaticModels":@[@"Fetch models automatically",@"自动获取模型列表",@"自動取得模型列表"],
          @"fetchModels":@[@"Fetch model list",@"获取模型列表",@"取得模型列表"],
          @"fetchingModels":@[@"Fetching models…",@"正在获取模型…",@"正在取得模型…"],
          @"modelsFailed":@[@"Could not fetch models",@"获取模型失败",@"取得模型失敗"],
          @"modelsInvalid":@[@"The provider did not return a valid model list.",@"服务商没有返回有效的模型列表。",@"服務商未回傳有效的模型列表。"],
          @"modelsEmpty":@[@"No accessible models were returned. You can still enter a model manually.",@"没有返回可用模型，你仍可手动填写模型名。",@"未回傳可用模型，你仍可手動填寫模型名稱。"],
          @"modelSearch":@[@"Search models",@"搜索模型",@"搜尋模型"],
          @"effort":@[@"Reasoning effort",@"推理强度",@"推理強度"],
          @"auto":@[@"Automatic",@"自动",@"自動"],
          @"low":@[@"Low",@"低",@"低"],
          @"medium":@[@"Medium",@"中",@"中"],
          @"high":@[@"High",@"高",@"高"],
          @"max":@[@"Max",@"Max",@"Max"],
          @"effortNote":@[@"Applies while Think is on. Automatic sends no effort parameter. Other levels require a compatible model; Max uses xhigh on OpenAI-compatible services and max on DeepSeek. Unsupported levels can produce an API error.",@"开启思考时生效。自动不发送强度参数；其他档位需模型支持。Max 在 OpenAI 兼容接口中发送 xhigh，在 DeepSeek 中发送 max；不支持的模型可能返回接口错误。",@"開啟思考時生效。自動不傳送強度參數；其他檔位需模型支援。Max 在 OpenAI 相容介面中傳送 xhigh，在 DeepSeek 中傳送 max；不支援的模型可能回傳錯誤。"],

          @"mode":@[@"Chat mode",@"对话模式",@"對話模式"],
          @"enableAPI":@[@"Use API for chat",@"使用 API 对话",@"使用 API 對話"],
          @"restartTitle":@[@"Restart to switch modes",@"重新启动以切换模式",@"重新啟動以切換模式"],
          @"modeNote":@[@"Off keeps the original service. On uses your API for chat while retaining the original sign-in and account. Save, then close and reopen the app to switch modes. API replies are stored on this device. While signed in, original account history can be loaded and continued using API; API replies are not uploaded to the original cloud.",@"关闭时使用原版服务；开启后使用 API 对话，保留原登录和账号。保存后请关闭并重新打开应用以切换模式。API 回复保存在此设备；已登录时可载入原账号历史，并使用 API 接续，API 回复不会上传到原云端。",@"關閉時使用原版服務；開啟後使用 API 對話，保留原登入及帳號。儲存後請關閉並重新開啟應用以切換模式。API 回覆保存在此裝置；已登入時可載入原帳號歷史並使用 API 接續，API 回覆不會上傳至原雲端。"],
          @"api":@[@"API Settings",@"API 设置",@"API 設定"],
          @"usage":@[@"API Usage",@"用量统计",@"用量統計"],
          @"connection":@[@"Connection",@"连接",@"連線"],
          @"models":@[@"Models",@"模型",@"模型"],
          @"advanced":@[@"Advanced",@"高级",@"進階"],
          @"model":@[@"Model",@"模型名",@"模型名稱"],
          @"thinkingModel":@[@"Thinking model (optional)",@"思考模型（可选）",@"思考模型（選填）"],
          @"systemPrompt":@[@"System prompt (optional)",@"系统提示词（可选）",@"系統提示詞（選填）"],
          @"timeout":@[@"Timeout (seconds)",@"请求超时（秒）",@"請求逾時（秒）"],
          @"requestUsage":@[@"Request token usage",@"请求 Token 用量",@"請求 Token 用量"],
          @"connectionNote":@[@"Use your provider’s HTTPS Base URL or full /chat/completions URL. The key is stored only in this device’s Keychain.",@"填写服务提供方的 HTTPS Base URL，或完整 /chat/completions 地址。API Key 仅保存到此设备的钥匙串。",@"填寫服務提供者的 HTTPS Base URL，或完整 /chat/completions 位址。API Key 僅儲存於此裝置的鑰匙圈。"],
          @"modelNote":@[@"You may fetch the model list or enter a model manually. An optional thinking model can be selected separately. DeepSeek’s thinking mode follows the original Think switch.",@"可自动获取模型列表，也可手动填写模型名。可单独指定思考模型。DeepSeek 官方模型的思考模式跟随原界面的“思考”开关。",@"可自動取得模型列表，也可手動填寫模型名稱。可另行指定思考模型。DeepSeek 官方模型的思考模式跟隨原介面的「思考」開關。"],
          @"advancedNote":@[@"Timeout: 10–3600 seconds. The system prompt is prepended to the message history. Turn off token usage requests if an older provider rejects this option.",@"超时范围 10–3600 秒。系统提示词会加入消息历史的开头。若旧接口不支持用量请求，可关闭此项。",@"逾時範圍 10–3600 秒。系統提示詞會加入訊息記錄的開頭。若舊介面不支援用量請求，可關閉此項。"],
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
    NSString *language=DSCurrentLanguage();
    NSUInteger index=[language hasPrefix:@"zh"] ? ([language containsString:@"Hant"] || [language containsString:@"TW"] || [language containsString:@"HK"] ? 2 : 1) : 0;
    NSArray *values=words[key];
    return values ? values[index] : key;
}
