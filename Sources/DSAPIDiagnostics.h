#import <Foundation/Foundation.h>
@class DSAPIConfiguration;
FOUNDATION_EXPORT NSDictionary *DSAPILastDiagnostic(void);
FOUNDATION_EXPORT NSString *DSAPIDiagnosticText(NSDictionary *record);
FOUNDATION_EXPORT NSError *DSAPIAnnotateError(NSError *error, NSString *stage, DSAPIConfiguration *configuration);
FOUNDATION_EXPORT void DSAPIRecordOutcome(DSAPIConfiguration *configuration, NSString *outcome, NSTimeInterval duration, NSInteger status);
FOUNDATION_EXPORT void DSAPIPresentRequestFailure(NSError *error);
