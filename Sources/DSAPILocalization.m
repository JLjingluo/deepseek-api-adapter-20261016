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
          @"diagnostics":@[@"Connection diagnostics",@"连接诊断",@"連線診斷"],
          @"testConnection":@[@"Test saved connection",@"测试已保存的连接",@"測試已儲存的連線"],
          @"testingConnection":@[@"Testing…",@"正在测试…",@"正在測試…"],
          @"lastDiagnostics":@[@"Latest request details",@"最近请求详情",@"最近請求詳情"],
          @"noDiagnostics":@[@"No request has been recorded yet.",@"还没有请求记录。",@"還沒有請求記錄。"],
          @"diagnosticsNote":@[@"Save your settings first. The connection test sends one short message using the saved key. Diagnostics exclude keys and chat content.",@"请先保存设置。连接测试使用已保存的密钥发送一条简短消息。诊断不包含密钥或聊天内容。",@"請先儲存設定。連線測試使用已儲存的金鑰傳送一則簡短訊息。診斷不包含金鑰或聊天內容。"],
          @"copyDiagnostics":@[@"Copy details",@"复制详情",@"複製詳情"],
          @"requestFailed":@[@"API request failed",@"API 请求失败",@"API 請求失敗"],
          @"connectionSuccess":@[@"Connection succeeded",@"连接成功",@"連線成功"],
          @"keyMissing":@[@"No saved API key was found. Enter your key in API Settings and save again.",@"没有找到已保存的 API Key，请在 API 设置中重新填写并保存。",@"找不到已儲存的 API Key，請在 API 設定中重新填寫並儲存。"],
          @"keyEntitlement":@[@"The app signature does not allow Keychain access. Re-sign with a valid application identifier and Keychain access group.",@"应用签名缺少钥匙串权限。请使用有效的应用标识及钥匙串访问组重新签名。",@"App 簽章缺少鑰匙圈權限。請使用有效的 App 識別碼及鑰匙圈存取群組重新簽署。"],
          @"keyLocked":@[@"The device security service cannot access the key right now. Unlock the iPhone and retry.",@"设备安全服务暂时无法读取密钥，请解锁 iPhone 后重试。",@"裝置安全服務暫時無法讀取金鑰，請解鎖 iPhone 後重試。"],
          @"keyReadFailed":@[@"The saved key could not be read. Check the Keychain status in diagnostics and save the key again.",@"无法读取已保存的密钥，请查看诊断中的钥匙串状态并重新保存密钥。",@"無法讀取已儲存的金鑰，請查看診斷中的鑰匙圈狀態並重新儲存金鑰。"],
          @"authError":@[@"The provider rejected the API key (HTTP 401). Check the key and selected provider.",@"接口拒绝了 API Key（HTTP 401），请核对密钥及服务商。",@"介面拒絕了 API Key（HTTP 401），請核對金鑰及服務商。"],
          @"balanceError":@[@"The provider reports insufficient balance or quota (HTTP 402).",@"接口提示余额或额度不足（HTTP 402）。",@"介面提示餘額或額度不足（HTTP 402）。"],
          @"permissionError":@[@"Access was denied (HTTP 403). Check model permissions and provider restrictions.",@"接口拒绝访问（HTTP 403），请检查模型权限及服务商限制。",@"介面拒絕存取（HTTP 403），請檢查模型權限及服務商限制。"],
          @"endpointError":@[@"Endpoint or model not found (HTTP 404). Check Base URL and model name.",@"接口路径或模型不存在（HTTP 404），请检查 Base URL 和模型名。",@"介面路徑或模型不存在（HTTP 404），請檢查 Base URL 與模型名稱。"],
          @"rateError":@[@"The provider rate limit was reached (HTTP 429). Wait before retrying.",@"请求触发服务商限流（HTTP 429），请稍后重试。",@"請求觸發服務商限流（HTTP 429），請稍後重試。"],
          @"serverError":@[@"The API provider returned a server error. See the HTTP status in diagnostics.",@"API 服务商返回服务器错误，请查看诊断中的 HTTP 状态码。",@"API 服務商回傳伺服器錯誤，請查看診斷中的 HTTP 狀態碼。"],
          @"parametersError":@[@"The model rejected the request parameters. Check model capabilities; image requests require a vision-capable model.",@"模型拒绝了请求参数。请检查模型能力；发送图片需要支持视觉的模型。",@"模型拒絕了請求參數。請檢查模型能力；傳送圖片需要支援視覺的模型。"],
          @"redirectError":@[@"The API address redirected. Enter the final HTTPS Base URL in settings.",@"API 地址发生重定向，请在设置中填写最终的 HTTPS Base URL。",@"API 位址發生重新導向，請在設定中填寫最終的 HTTPS Base URL。"],
          @"sizeError":@[@"The provider rejected the attachment size (HTTP 413). Use a smaller file.",@"接口拒绝了附件大小（HTTP 413），请减小文件后重试。",@"介面拒絕了附件大小（HTTP 413），請縮小檔案後重試。"],
          @"timeoutError":@[@"The API request timed out. Check the connection or increase the timeout.",@"API 请求超时，请检查连接或增加超时时间。",@"API 請求逾時，請檢查連線或增加逾時時間。"],
          @"offlineError":@[@"iOS reports no network connection. Check Wi-Fi, cellular access and the app network permission.",@"iOS 提示没有网络连接，请检查 Wi-Fi、蜂窝网络及应用联网权限。",@"iOS 提示沒有網路連線，請檢查 Wi-Fi、行動網路及 App 連網權限。"],
          @"dnsError":@[@"The API host could not be resolved. Check Base URL and DNS/network settings.",@"无法解析 API 域名，请检查 Base URL 及 DNS、网络设置。",@"無法解析 API 網域，請檢查 Base URL 及 DNS、網路設定。"],
          @"connectError":@[@"The API server could not be reached. Check the address, port and network route.",@"无法连接 API 服务器，请检查地址、端口及网络连接。",@"無法連線 API 伺服器，請檢查位址、連接埠及網路連線。"],
          @"lostError":@[@"The network connection was interrupted during the request.",@"请求过程中网络连接中断，请稍后重试。",@"請求過程中網路連線中斷，請稍後重試。"],
          @"tlsError":@[@"TLS certificate verification failed. Check the API server certificate and device time.",@"TLS 证书验证失败，请检查接口服务器证书及设备时间。",@"TLS 憑證驗證失敗，請檢查介面伺服器憑證及裝置時間。"],
          @"atsError":@[@"iOS blocked an insecure connection. Use an HTTPS API endpoint.",@"iOS 阻止了不安全连接，请使用 HTTPS API 地址。",@"iOS 阻擋了不安全連線，請使用 HTTPS API 位址。"],
          @"transportError":@[@"The API transport failed. See the system error code in diagnostics.",@"API 网络传输失败，请查看诊断中的系统错误码。",@"API 網路傳輸失敗，請查看診斷中的系統錯誤碼。"],
          @"sseError":@[@"The endpoint did not return an SSE stream. Check the OpenAI-compatible chat/completions address.",@"接口没有返回 SSE 流，请检查 OpenAI 兼容的 chat/completions 地址。",@"介面沒有回傳 SSE 串流，請檢查 OpenAI 相容的 chat/completions 位址。"],
          @"streamError":@[@"The API stream was invalid or interrupted. Check provider compatibility and request details.",@"API 流式响应格式无效或提前中断，请检查服务商兼容性和请求详情。",@"API 串流回應格式無效或提前中斷，請檢查服務商相容性及請求詳情。"],
          @"configurationError":@[@"The API configuration is invalid. Check Base URL, key and model in settings.",@"API 配置无效，请在设置中检查 Base URL、密钥和模型。",@"API 設定無效，請在設定中檢查 Base URL、金鑰與模型。"],
          @"cancelled":@[@"Request cancelled.",@"请求已取消。",@"請求已取消。"],
          @"guest":@[@"Guest",@"访客",@"訪客"],
          @"signIn":@[@"Sign in",@"登录",@"登入"],
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
